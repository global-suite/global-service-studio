import Foundation
import os

/// A time the main thread answered the watchdog later than its threshold.
public struct MainThreadStall: Codable, Equatable, Sendable {
    /// Seconds from `start()` to the ping the main thread answered late.
    public let startSeconds: Double
    /// How long the main thread took to answer, in milliseconds.
    public let durationMs: Double
    /// The activity label that was current when the stall began.
    public let activity: String
}

/// Watches the main thread from a background timer and records every stall above a threshold (issue #157, ADR 0012).
/// The outputs share the main thread, so a main-thread stall freezes the screens. The main thread only answers the ping:
/// it takes a lock and reads the clock, and never logs or records anything itself. Times use the uptime clock, so a Mac asleep is no stall.
public final class MainThreadWatchdog: Sendable {
    private struct State {
        /// Not Sendable; it is only touched under the lock.
        var timer: DispatchSourceTimer?
        var origin: UInt64 = 0
        var activity = ""
        /// The ping waiting for the main thread: its number and when it was sent.
        var ping: UInt64 = 0
        var sent: UInt64?
        /// The label seen by the timer while the ping was already late, which is the one current when the stall began.
        var stallActivity: String?
        /// When the main thread answered the ping, with the label current then.
        var answer: (at: UInt64, activity: String)?
        var stalls: [MainThreadStall] = []
    }

    private let interval: UInt64, threshold: UInt64
    private let queue = DispatchQueue(label: "GSS main thread watchdog", qos: .utility)
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// Pings the main thread every `interval` seconds and records answers slower than `threshold` seconds.
    public init(interval: TimeInterval = 0.05, threshold: TimeInterval = 0.1) {
        (self.interval, self.threshold) = (UInt64(interval * 1e9), UInt64(threshold * 1e9))
    }

    deinit { state.withLockUnchecked { $0.timer }?.cancel() }

    /// Starts a new recording, dropping the stalls of the previous one; does nothing while running.
    public func start() {
        // Created only when not running: libdispatch traps when a timer that was never resumed is released.
        let timer = state.withLockUnchecked { state -> DispatchSourceTimer? in
            guard state.timer == nil else { return nil }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .nanoseconds(Int(interval)), repeating: .nanoseconds(Int(interval)), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in self?.tick() }
            state = State(timer: timer, origin: Self.now(), activity: state.activity, ping: state.ping)
            return timer
        }
        timer?.resume()
    }

    /// Stops recording; the stalls stay readable. Called on the main thread, it counts as the answer to a ping still waiting.
    public func stop() {
        let now = Self.now(), onMain = Thread.isMainThread
        let timer = state.withLockUnchecked { state -> DispatchSourceTimer? in
            if onMain, state.sent != nil, state.answer == nil { state.answer = (now, state.activity) }
            settle(&state)
            defer { (state.timer, state.sent) = (nil, nil) }
            return state.timer
        }
        timer?.cancel()
    }

    /// Names what the app is doing, such as an operator action; stalls that begin while it is current carry it.
    public func setActivity(_ label: String) { state.withLockUnchecked { $0.activity = label } }

    /// The stalls recorded since `start()`, oldest first.
    public var stalls: [MainThreadStall] { state.withLockUnchecked { $0.stalls } }

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// On the watchdog queue: records a late answer, else waits for the ping, else sends a new one.
    private func tick() {
        let now = Self.now()
        let ping = state.withLockUnchecked { state -> UInt64? in
            guard state.timer != nil else { return nil }
            if let sent = state.sent, state.answer == nil {
                if state.stallActivity == nil, now - sent > threshold { state.stallActivity = state.activity }
                return nil
            }
            settle(&state)
            state.ping += 1
            (state.sent, state.answer, state.stallActivity) = (now, nil, nil)
            return state.ping
        }
        if let ping { DispatchQueue.main.async { [weak self] in self?.answer(ping) } }
    }

    /// On the main thread: notes when the ping was answered; nothing else.
    private func answer(_ ping: UInt64) {
        let now = Self.now()
        state.withLockUnchecked { state in
            if state.timer != nil, state.ping == ping, state.sent != nil, state.answer == nil { state.answer = (now, state.activity) }
        }
    }

    /// Records the answered ping as a stall when it came later than the threshold.
    private func settle(_ state: inout State) {
        guard let sent = state.sent, let answer = state.answer, answer.at > sent, answer.at - sent > threshold else { return }
        state.stalls.append(MainThreadStall(startSeconds: Double(sent - state.origin) / 1e9, durationMs: Double(answer.at - sent) / 1e6,
                                            activity: state.stallActivity ?? answer.activity))
    }
}
