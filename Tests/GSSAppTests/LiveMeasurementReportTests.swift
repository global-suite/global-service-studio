import XCTest
@testable import GSSApp

/// The report of the live measurement (issue #157); every value here is invented.
final class LiveMeasurementReportTests: XCTestCase {
    private let samples = (1...20).map { ActionSample(action: "nextSlide", ms: Double($0)) } + [ActionSample(action: "clearAll", ms: 5)]
    private let stalls = [MainThreadStall(startSeconds: 1, durationMs: 150, activity: "nextSlide"), MainThreadStall(startSeconds: 2, durationMs: 120, activity: "nextSlide")]

    private var report: LiveMeasurementReport {
        LiveMeasurementReport(machine: MachineInfo(model: "MacBookPro14,3", cpu: "Invented CPU", memoryGB: 16, macOS: "13.6.0", architecture: "x86_64"),
                              library: LibrarySize(songs: 3, presentations: 1, plans: 2), rounds: 3, pace: 1.5, slides: 7, outputs: ["audience"],
                              samples: samples, stalls: stalls, durationSeconds: 42)
    }

    func testSummaryCountsAveragesPercentileAndMaximumInFirstSeenOrder() {
        let summary = LiveMeasurementReport.summarize(samples, stalls: stalls)
        XCTAssertEqual(summary, [
            ActionTiming(action: "nextSlide", count: 20, averageMs: 10.5, p95Ms: 19, maxMs: 20, stalls: 2, worstStallMs: 150),
            ActionTiming(action: "clearAll", count: 1, averageMs: 5, p95Ms: 5, maxMs: 5, stalls: 0, worstStallMs: 0),
        ])
    }

    func testSummaryOfNoSamplesIsEmpty() {
        XCTAssertEqual(LiveMeasurementReport.summarize([], stalls: []), [])
    }

    func testTotalsCountActionsAndStalls() {
        XCTAssertEqual(report.totals, LiveMeasurementTotals(actions: 21, stalls: 2, longestStallMs: 150, stallMs: 270, durationSeconds: 42))
    }

    func testJSONHasSortedKeysAndTheSameBytesEveryTime() throws {
        let data = try report.json()
        XCTAssertEqual(data, try report.json())
        let text = String(decoding: data, as: UTF8.self)
        // Top-level keys, by their indentation in the pretty-printed JSON.
        let keys = ["actions", "library", "machine", "outputs", "stalls", "totals"].map { text.range(of: "\n  \"\($0)\"")?.lowerBound }
        XCTAssertFalse(keys.contains(nil), text)
        XCTAssertEqual(keys.compactMap { $0 }, keys.compactMap { $0 }.sorted())
        XCTAssertEqual(try JSONDecoder().decode(LiveMeasurementReport.self, from: data), report)
    }

    func testTableHasTheHeaderAndOneRowPerAction() {
        let lines = report.table.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains(LiveMeasurementReport.tableHeader), report.table)
        for action in ["nextSlide", "clearAll"] {
            XCTAssertEqual(lines.filter { $0.hasPrefix(action + " ") }.count, 1, report.table)
        }
    }
}
