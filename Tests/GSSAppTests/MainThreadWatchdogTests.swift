import XCTest
@testable import GSSApp

/// The main-thread watchdog of the live measurement (issue #157). Tolerances are wide so a busy CI machine does not fail them.
final class MainThreadWatchdogTests: XCTestCase {
    /// Lets the main queue answer the watchdog's pings for a while.
    private func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    func testBlockedMainThreadRecordsOneStallWithTheActivitySetBeforeIt() {
        let watchdog = MainThreadWatchdog(interval: 0.05, threshold: 0.1)
        watchdog.start()
        defer { watchdog.stop() }
        spin(0.2)
        watchdog.setActivity("block")
        Thread.sleep(forTimeInterval: 0.3)
        watchdog.setActivity("idle")
        spin(0.3)
        XCTAssertEqual(watchdog.stalls.count, 1, "\(watchdog.stalls)")
        XCTAssertEqual(watchdog.stalls.first?.activity, "block")
        XCTAssertEqual(watchdog.stalls.first?.durationMs ?? 0, 300, accuracy: 150)
        XCTAssertGreaterThanOrEqual(watchdog.stalls.first?.startSeconds ?? -1, 0)
    }

    func testIdleMainThreadRecordsNoStall() {
        let watchdog = MainThreadWatchdog(interval: 0.05, threshold: 0.1)
        watchdog.start()
        defer { watchdog.stop() }
        spin(0.5)
        XCTAssertEqual(watchdog.stalls, [])
    }

    func testStopEndsRecording() {
        let watchdog = MainThreadWatchdog(interval: 0.05, threshold: 0.1)
        watchdog.start()
        spin(0.2)
        watchdog.stop()
        Thread.sleep(forTimeInterval: 0.3)
        spin(0.3)
        XCTAssertEqual(watchdog.stalls, [])
    }
}
