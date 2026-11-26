import Foundation

/// How long one operator action took on the main thread.
public struct ActionSample: Equatable, Sendable {
    public let action: String
    public let ms: Double
}

/// The Mac a measurement ran on.
public struct MachineInfo: Codable, Equatable, Sendable {
    public var model, cpu: String
    public var memoryGB: Double
    public var macOS, architecture: String

    /// This Mac: `hw.model`, `machdep.cpu.brand_string`, physical memory, macOS version and the architecture the app runs as.
    public static func current() -> MachineInfo {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return MachineInfo(model: sysctl("hw.model"), cpu: sysctl("machdep.cpu.brand_string"), memoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
                           macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", architecture: architecture)
    }

    private static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// How many items the library held.
public struct LibrarySize: Codable, Equatable, Sendable {
    public var songs, presentations, plans: Int
}

/// The timings of one action, with the stalls that began while it was the current activity.
public struct ActionTiming: Codable, Equatable, Sendable {
    public var action: String
    public var count: Int
    public var averageMs, p95Ms, maxMs: Double
    public var stalls: Int
    public var worstStallMs: Double
}

public struct LiveMeasurementTotals: Codable, Equatable, Sendable {
    public var actions, stalls: Int
    public var longestStallMs, stallMs, durationSeconds: Double
}

/// The result of a live measurement run (issue #157): written as JSON, printed as a table. A developer tool: English only.
public struct LiveMeasurementReport: Codable, Equatable, Sendable {
    public var machine: MachineInfo
    public var library: LibrarySize
    public var rounds: Int
    public var pace: Double
    /// Slides of the service, stepped through once per round.
    public var slides: Int
    public var outputs: [String]
    public var actions: [ActionTiming]
    public var stalls: [MainThreadStall]
    public var totals: LiveMeasurementTotals

    public init(machine: MachineInfo, library: LibrarySize, rounds: Int, pace: Double, slides: Int, outputs: [String],
                samples: [ActionSample], stalls: [MainThreadStall], durationSeconds: Double) {
        (self.machine, self.library, self.rounds, self.pace, self.slides, self.outputs, self.stalls) = (machine, library, rounds, pace, slides, outputs, stalls)
        actions = Self.summarize(samples, stalls: stalls)
        totals = LiveMeasurementTotals(actions: samples.count, stalls: stalls.count, longestStallMs: stalls.map(\.durationMs).max() ?? 0,
                                       stallMs: stalls.map(\.durationMs).reduce(0, +), durationSeconds: durationSeconds)
    }

    /// One timing per action, in the order the actions first ran; the 95th percentile is the nearest rank.
    public static func summarize(_ samples: [ActionSample], stalls: [MainThreadStall]) -> [ActionTiming] {
        var order: [String] = [], byAction: [String: [Double]] = [:]
        for sample in samples {
            if byAction[sample.action] == nil { order.append(sample.action) }
            byAction[sample.action, default: []].append(sample.ms)
        }
        return order.map { action in
            let ms = byAction[action, default: []].sorted(), late = stalls.filter { $0.activity == action }.map(\.durationMs)
            let rank = Int((0.95 * Double(ms.count)).rounded(.up))
            return ActionTiming(action: action, count: ms.count, averageMs: ms.reduce(0, +) / Double(ms.count), p95Ms: ms[max(rank, 1) - 1],
                                maxMs: ms.last ?? 0, stalls: late.count, worstStallMs: late.max() ?? 0)
        }
    }

    /// The report as JSON with sorted keys, so the same report always gives the same bytes.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static let tableHeader = "action                     count   avg ms   p95 ms   max ms  stalls  worst stall ms"

    /// The summary for the console: the machine, the library, one row per action and the totals.
    public var table: String {
        func number(_ value: Double, _ width: Int) -> String { String(format: "%\(width).1f", value) }
        let rows = actions.map { timing in
            timing.action.padding(toLength: 26, withPad: " ", startingAt: 0) + String(format: " %6d", timing.count) + number(timing.averageMs, 9)
                + number(timing.p95Ms, 9) + number(timing.maxMs, 9) + String(format: " %7d", timing.stalls) + number(timing.worstStallMs, 16)
        }
        let worst = stalls.max { $0.durationMs < $1.durationMs }
        return ([
            "machine: \(machine.model), \(machine.cpu), \(number(machine.memoryGB, 0)) GB, macOS \(machine.macOS), \(machine.architecture)",
            "library: \(library.songs) songs, \(library.presentations) presentations, \(library.plans) plans",
            "run: \(rounds) rounds of \(slides) slides at \(pace) s, outputs: \(outputs.isEmpty ? "none" : outputs.joined(separator: ", "))",
            "", Self.tableHeader,
        ] + rows + [
            "", "stalls over the threshold: \(totals.stalls), \(number(totals.stallMs, 0)) ms in total"
                + (worst.map { ", longest \(number($0.durationMs, 0)) ms during \($0.activity)" } ?? ""),
        ]).joined(separator: "\n")
    }
}
