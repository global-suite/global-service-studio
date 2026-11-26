import XCTest
@testable import GSSApp

/// The launch arguments of the live measurement mode (issue #157).
final class LiveMeasurementOptionsTests: XCTestCase {
    func testWithoutTheArgumentNothingIsMeasured() throws {
        XCTAssertNil(try LiveMeasurementOptions.parse(["GlobalServiceStudio", "-NSDocumentRevisionsDebugMode", "YES"]))
    }

    func testDefaultsAndValues() throws {
        XCTAssertEqual(try LiveMeasurementOptions.parse(["app", "--measure-live", "/tmp/report.json"]),
                       LiveMeasurementOptions(report: URL(fileURLWithPath: "/tmp/report.json"), rounds: 3, pace: 1.5))
        XCTAssertEqual(try LiveMeasurementOptions.parse(["app", "--rounds", "5", "--measure-live", "r.json", "--pace", "0.5"]),
                       LiveMeasurementOptions(report: URL(fileURLWithPath: "r.json"), rounds: 5, pace: 0.5))
    }

    func testInvalidValuesAreRefusedWithAMessage() {
        for arguments in [["app", "--measure-live"], ["app", "--measure-live", "--rounds", "2"], ["app", "--measure-live", "r.json", "--rounds", "0"],
                          ["app", "--measure-live", "r.json", "--rounds"], ["app", "--measure-live", "r.json", "--pace", "fast"]] {
            XCTAssertThrowsError(try LiveMeasurementOptions.parse(arguments), "\(arguments)") { error in
                XCTAssertFalse((error as? LiveMeasurementOptions.Invalid)?.message.isEmpty ?? true)
            }
        }
    }
}
