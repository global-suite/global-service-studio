import Foundation
import XCTest

@testable import GSSCore

final class PlanValidationTests: XCTestCase {
    /// Edits the example; with a `reason`, validation must fail with it at `path`, otherwise pass.
    private func check(_ reason: String?, at path: String = "", _ edit: (inout Plan) -> Void) throws {
        var plan = try decodePlan()
        edit(&plan)
        guard let reason else { return XCTAssertNoThrow(try plan.validate()) }
        XCTAssertThrowsError(try plan.validate(), path) {
            XCTAssertEqual($0 as? FormatError, .validation(reason: reason, at: path))
        }
    }

    func testDecodingRunsValidation() {
        assertPlanDecodeThrows(.validation(reason: "duplicateItemId", at: "items[2].id"),
                               [(#""id": "i3""#, #""id": "i1""#)])
    }

    func testItemIdsAreUniqueAndNotEmpty() throws {
        try check("duplicateItemId", at: "items[4].id") { $0.items[4].id = "i2" }
        try check("emptyItemId", at: "items[0].id") { $0.items[0].id = "" }
    }

    func testEachKnownKindHasWhatItNeedsAndUnknownValuesPass() throws {
        try check("missingSong", at: "items[1].song") { $0.items[1].song = nil }
        try check("missingPresentation", at: "items[2].presentation") { $0.items[2].presentation = nil }
        try check("missingMedia", at: "items[3].media") { $0.items[3].media = nil }
        try check("invalidMediaPath", at: "items[3].media.path") { $0.items[3].media?.path = "/Users/a/clip.mp4" }
        try check(nil) { $0.items[2].kind = PlanItemKind(rawValue: "offering"); $0.items[2].presentation = nil }
        try check(nil) { $0.items[1].position = PlanItemPosition(rawValue: "afterglow") }
    }

    func testLengthIsNotNegative() throws {
        try check("negativeLength", at: "items[4].length") { $0.items[4].length = -1 }
        try check(nil) { $0.items[4].length = 0 }
    }

    func testTimeStartIsHoursAndMinutes() throws {
        for start in ["", "9:00", "24:00", "10:60", "10-00", "10:00:00", "ab:cd", "١٠:٠٠"] {
            try check("invalidTime", at: "times[0].start") { $0.times?[0].start = start }
        }
        for start in ["00:00", "09:05", "23:59"] { try check(nil) { $0.times?[0].start = start } }
    }

    func testDateIsACalendarDay() throws {
        for date in ["", "2026-11-31", "2026-02-29", "2026-13-01", "2026-1-15", "15/11/2026", "2026-11-15T10:00"] {
            try check("invalidDate", at: "date") { $0.date = date }
        }
        for date in ["2028-02-29", "2026-12-31", "2000-02-29"] { try check(nil) { $0.date = date } }
    }
}
