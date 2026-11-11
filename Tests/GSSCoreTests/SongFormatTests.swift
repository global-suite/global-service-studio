import Foundation
import XCTest

@testable import GSSCore

/// The song example of ADR 0005, with invented text.
let songExample = """
{
  "format": "gss.song", "version": 1, "id": "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10",
  "title": "Morning Light", "titles": { "es": "Luz de la mañana" }, "language": "en",
  "authors": [{ "name": "A. Writer", "role": "words" }], "copyright": "Public Domain", "ccliNumber": null,
  "key": "G", "tempo": 72, "timeSignature": "4/4", "tags": ["hymn"],
  "sections": [
    { "id": "v1", "kind": "verse", "number": 1, "lines": [
      { "text": { "en": "Morning light is rising", "es": "La luz del día nace" },
        "chords": [{ "at": 0, "chord": "G" }, { "at": 17, "chord": "C" }] },
      { "text": { "en": "Over all the earth", "es": "Sobre la tierra" }, "breakAfter": "slide" }
    ] },
    { "id": "c1", "kind": "chorus", "lines": [{ "text": { "en": "We lift our voice", "es": "Alzamos nuestra voz" } }] }
  ],
  "arrangements": [
    { "id": "default", "name": "Default", "sequence": ["v1", "c1", "v1", "c1"] },
    { "id": "short", "name": "Short", "sequence": ["v1", "c1"] }
  ],
  "defaultArrangement": "default", "externalIds": {}, "extensions": {}
}
"""

/// Decodes `json` after `edit` changes its parsed value.
func decodeSong(_ json: String = songExample, _ edit: (inout [String: JSONValue]) -> Void = { _ in }) throws -> Song {
    guard case .object(var fields) = try JSONValue(parsing: Data(json.utf8)) else { throw FormatError.invalidJSON }
    edit(&fields)
    return try Song.decode(from: JSONValue.object(fields).canonicalData())
}

final class SongFormatTests: XCTestCase {
    func testDecodesTheExample() throws {
        let song = try decodeSong()
        XCTAssertEqual(song.id, UUID(uuidString: "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10"))
        XCTAssertEqual(song.title, "Morning Light")
        XCTAssertEqual(song.titles, ["es": "Luz de la mañana"])
        XCTAssertEqual(song.authors, [SongAuthor(name: "A. Writer", role: "words")])
        XCTAssertNil(song.ccliNumber)
        XCTAssertEqual(song.tempo, 72)
        XCTAssertEqual(song.sections.map(\.kind), [.verse, .chorus])
        XCTAssertEqual(song.sections[0].lines[0].chords, [SongChord(at: 0, chord: "G"), SongChord(at: 17, chord: "C")])
        XCTAssertEqual(song.sections[0].lines[1].text["es"], "Sobre la tierra")
        XCTAssertEqual(song.sections[0].lines[1].breakAfter, "slide")
        XCTAssertEqual(song.arrangements?.map(\.sequence), [["v1", "c1", "v1", "c1"], ["v1", "c1"]])
        XCTAssertEqual(song.defaultArrangement, "default")
    }

    func testEncodingTheExampleGivesCanonicalBytes() throws {
        let canonical = try JSONValue(parsing: Data(songExample.utf8)).canonicalData()
        let song = try Song.decode(from: canonical)
        XCTAssertEqual(try song.encoded(), canonical)
        XCTAssertEqual(try Song.decode(from: song.encoded()), song)
    }

    func testUnknownFieldsSurviveAtEveryLevel() throws {
        let json = songExample
            .replacingOccurrences(of: #""title": "Morning Light","#, with: #""title": "Morning Light", "x-song": 1,"#)
            .replacingOccurrences(of: #""kind": "chorus","#, with: #""kind": "chorus", "x-section": [true],"#)
            .replacingOccurrences(of: #""breakAfter": "slide""#, with: #""breakAfter": "slide", "x-line": null"#)
            .replacingOccurrences(of: #""chord": "C""#, with: #""chord": "C", "x-chord": 2.5"#)
            .replacingOccurrences(of: #""role": "words""#, with: #""role": "words", "x-author": "a""#)
            .replacingOccurrences(of: #""name": "Short","#, with: #""name": "Short", "x-arrangement": {"k": "v"},"#)
        let original = try JSONValue(parsing: Data(json.utf8))
        let song = try decodeSong(json)
        XCTAssertEqual(song.unknown, ["x-song": .integer(1), "ccliNumber": .null])
        XCTAssertEqual(song.sections[1].unknown, ["x-section": .array([.bool(true)])])
        XCTAssertEqual(song.sections[0].lines[1].unknown, ["x-line": .null])
        XCTAssertEqual(song.sections[0].lines[0].chords?[1].unknown, ["x-chord": .double(2.5)])
        XCTAssertEqual(song.authors?[0].unknown, ["x-author": .string("a")])
        XCTAssertEqual(song.arrangements?[1].unknown, ["x-arrangement": .object(["k": .string("v")])])
        XCTAssertEqual(try JSONValue(parsing: song.encoded()), original)
    }

    func testUnknownSectionKindSurvives() throws {
        let song = try decodeSong(songExample.replacingOccurrences(of: #""kind": "chorus""#, with: #""kind": "vamp""#))
        XCTAssertEqual(song.sections[1].kind, SongSectionKind(rawValue: "vamp"))
        XCTAssertTrue(String(decoding: try song.encoded(), as: UTF8.self).contains(#""kind": "vamp""#))
    }

    func testAbsentOptionalFieldsStayAbsent() throws {
        let minimal = """
        {"format": "gss.song", "version": 1, "id": "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10", "title": "T", "language": "en",
         "sections": [{"id": "a", "kind": "verse", "lines": [{"text": {"en": "Line"}}]}]}
        """
        let canonical = try JSONValue(parsing: Data(minimal.utf8)).canonicalData()
        XCTAssertEqual(try Song.decode(from: canonical).encoded(), canonical)
    }

    func testNewerVersionIsRejected() {
        XCTAssertThrowsError(try decodeSong { $0["version"] = .integer(2) }) {
            XCTAssertEqual($0 as? FormatError, .unsupportedVersion(found: 2, supported: 1))
        }
    }

    func testWrongFormatIsRejected() {
        XCTAssertThrowsError(try decodeSong { $0["format"] = .string("gss.theme") }) {
            XCTAssertEqual($0 as? FormatError, .wrongFormat(expected: "gss.song", found: "gss.theme"))
        }
    }

    func testMissingRequiredFieldReportsItsKeyPath() {
        let text = #""text": { "en": "Over all the earth", "es": "Sobre la tierra" }, "#
        let json = songExample.replacingOccurrences(of: text, with: "")
        XCTAssertThrowsError(try decodeSong(json)) {
            XCTAssertEqual($0 as? FormatError, .missingField("sections[0].lines[1].text"))
        }
    }
}
