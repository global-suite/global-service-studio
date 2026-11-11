import Foundation
import XCTest

@testable import GSSCore

final class SongValidationTests: XCTestCase {
    private func assertInvalid(_ reason: String, at path: String, _ edit: (inout Song) -> Void) throws {
        var song = try decodeSong()
        edit(&song)
        XCTAssertThrowsError(try song.validate()) {
            XCTAssertEqual($0 as? FormatError, .validation(reason: reason, at: path))
        }
    }

    func testSectionIdsAreUnique() throws {
        try assertInvalid("duplicateSectionId", at: "sections[1].id") { $0.sections[1].id = "v1" }
    }

    func testDecodingRunsValidation() {
        let json = songExample.replacingOccurrences(of: #""id": "c1""#, with: #""id": "v1""#)
        XCTAssertThrowsError(try decodeSong(json)) {
            XCTAssertEqual($0 as? FormatError, .validation(reason: "duplicateSectionId", at: "sections[1].id"))
        }
    }

    func testArrangementsReferenceExistingSections() throws {
        try assertInvalid("unknownSection", at: "arrangements[1].sequence[2]") {
            $0.arrangements?[1].sequence.append("b9")
        }
    }

    func testArrangementIdsAreUnique() throws {
        try assertInvalid("duplicateArrangementId", at: "arrangements[1].id") { $0.arrangements?[1].id = "default" }
    }

    func testDefaultArrangementExists() throws {
        try assertInvalid("unknownArrangement", at: "defaultArrangement") { $0.defaultArrangement = "long" }
    }

    func testEveryLineHasThePrimaryLanguage() throws {
        try assertInvalid("missingPrimaryText", at: "sections[1].lines[0].text.en") {
            $0.sections[1].lines[0].text["en"] = nil
        }
    }

    func testSecondaryLanguageMayBeMissing() throws {
        var song = try decodeSong()
        song.sections[1].lines[0].text["es"] = nil
        XCTAssertNoThrow(try song.validate())
    }

    func testChordsStayWithinThePrimaryText() throws {
        // "Morning light is rising" has 23 code points, so 23 is the last valid offset.
        var song = try decodeSong()
        song.sections[0].lines[0].chords?[1].at = 23
        XCTAssertNoThrow(try song.validate())
        try assertInvalid("chordOutOfRange", at: "sections[0].lines[0].chords[1].at") {
            $0.sections[0].lines[0].chords?[1].at = 24
        }
        try assertInvalid("chordOutOfRange", at: "sections[0].lines[0].chords[0].at") {
            $0.sections[0].lines[0].chords?[0].at = -1
        }
    }
}
