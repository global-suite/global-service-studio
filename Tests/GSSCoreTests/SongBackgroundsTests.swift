import Foundation
import XCTest

@testable import GSSCore

/// The song example with a default background and a background for the chorus, with invented media.
let songWithBackgrounds = songExample.replacingOccurrences(of: #""extensions": {}"#, with: """
    "extensions": {},
    "backgrounds": {
      "default": { "kind": "video", "media": { "path": "Media/waves.mp4", "sha256": "ab12" } },
      "sections": { "c1": { "kind": "image", "media": { "path": "Media/light.jpg", "sha256": "cd34" } },
                    "v1": { "kind": "color", "color": "#102030" } }
    }
    """)

final class SongBackgroundsTests: XCTestCase {
    private func assertInvalid(_ reason: String, at path: String, _ edit: (inout Song) -> Void) throws {
        var song = try decodeSong(songWithBackgrounds)
        edit(&song)
        XCTAssertThrowsError(try song.validate(), path) {
            XCTAssertEqual($0 as? FormatError, .validation(reason: reason, at: path))
        }
    }

    func testDecodesDefaultAndSectionBackgrounds() throws {
        let backgrounds = try XCTUnwrap(try decodeSong(songWithBackgrounds).backgrounds)
        XCTAssertEqual(backgrounds.defaultBackground,
                       ThemeBackground(kind: .video, media: MediaReference(path: "Media/waves.mp4", sha256: "ab12")))
        XCTAssertEqual(backgrounds.sections?["c1"],
                       ThemeBackground(kind: .image, media: MediaReference(path: "Media/light.jpg", sha256: "cd34")))
        XCTAssertEqual(backgrounds.sections?["v1"], ThemeBackground(kind: .color, color: "#102030"))
    }

    func testEncodingBackgroundsGivesCanonicalBytes() throws {
        let canonical = try JSONValue(parsing: Data(songWithBackgrounds.utf8)).canonicalData()
        let song = try Song.decode(from: canonical)
        XCTAssertEqual(try song.encoded(), canonical)
        XCTAssertEqual(try Song.decode(from: song.encoded()), song)
    }

    func testAbsentBackgroundsStayAbsent() throws {
        let song = try decodeSong()
        XCTAssertNil(song.backgrounds)
        guard case .object(let fields) = try JSONValue(parsing: song.encoded()) else { return XCTFail("not an object") }
        XCTAssertNil(fields["backgrounds"])
    }

    func testAbsentDefaultAndSectionsStayAbsent() throws {
        let json = songExample.replacingOccurrences(of: #""extensions": {}"#,
                                                    with: #""extensions": {}, "backgrounds": {}"#)
        let song = try decodeSong(json)
        XCTAssertEqual(song.backgrounds, SongBackgrounds())
        XCTAssertEqual(try JSONValue(parsing: song.encoded()), try JSONValue(parsing: Data(json.utf8)))
    }

    func testUnknownFieldsInsideBackgroundsSurvive() throws {
        let json = songWithBackgrounds
            .replacingOccurrences(of: #""backgrounds": {"#, with: #""backgrounds": { "x-backgrounds": [1],"#)
            .replacingOccurrences(of: #""kind": "color","#, with: #""kind": "color", "x-background": "a","#)
        let song = try decodeSong(json)
        XCTAssertEqual(song.backgrounds?.unknown, ["x-backgrounds": .array([.integer(1)])])
        XCTAssertEqual(song.backgrounds?.sections?["v1"]?.unknown, ["x-background": .string("a")])
        XCTAssertEqual(try JSONValue(parsing: song.encoded()), try JSONValue(parsing: Data(json.utf8)))
    }

    func testUnknownBackgroundKindSurvives() throws {
        let json = songWithBackgrounds.replacingOccurrences(of: #""kind": "color""#, with: #""kind": "gradient""#)
        let song = try decodeSong(json)
        XCTAssertEqual(song.backgrounds?.sections?["v1"]?.kind, ThemeBackgroundKind(rawValue: "gradient"))
        XCTAssertEqual(try JSONValue(parsing: song.encoded()), try JSONValue(parsing: Data(json.utf8)))
    }

    func testSectionKeyThatNamesNoSectionIsKept() throws {
        let json = songWithBackgrounds.replacingOccurrences(of: #""c1": { "kind""#, with: #""b9": { "kind""#)
        let song = try decodeSong(json)
        XCTAssertNotNil(song.backgrounds?.sections?["b9"])
        XCTAssertEqual(try JSONValue(parsing: song.encoded()), try JSONValue(parsing: Data(json.utf8)))
    }

    func testDecodingValidatesBackgrounds() {
        let json = songWithBackgrounds.replacingOccurrences(of: "#102030", with: "blue")
        XCTAssertThrowsError(try decodeSong(json)) {
            XCTAssertEqual($0 as? FormatError, .validation(reason: "invalidColor", at: "backgrounds.sections.v1.color"))
        }
    }

    func testColorIsValid() throws {
        try assertInvalid("invalidColor", at: "backgrounds.default.color") {
            $0.backgrounds?.defaultBackground = ThemeBackground(kind: .color, color: "#12")
        }
        try assertInvalid("invalidColor", at: "backgrounds.sections.c.color") {
            $0.backgrounds?.sections?["c"] = ThemeBackground(kind: .color, color: "black")
        }
    }

    func testColorKindNeedsAColor() throws {
        try assertInvalid("missingColor", at: "backgrounds.default.color") {
            $0.backgrounds?.defaultBackground = ThemeBackground(kind: .color)
        }
        try assertInvalid("missingColor", at: "backgrounds.sections.v1.color") {
            $0.backgrounds?.sections?["v1"]?.color = nil
        }
    }

    func testImageAndVideoNeedMedia() throws {
        try assertInvalid("missingMedia", at: "backgrounds.default.media") {
            $0.backgrounds?.defaultBackground?.media = nil
        }
        try assertInvalid("missingMedia", at: "backgrounds.sections.c1.media") {
            $0.backgrounds?.sections?["c1"]?.media = nil
        }
    }

    func testMediaPathIsLibraryRelative() throws {
        for path in ["", "/Users/a/waves.mp4", "~/waves.mp4", "Media/../../waves.mp4"] {
            try assertInvalid("invalidMediaPath", at: "backgrounds.default.media.path") {
                $0.backgrounds?.defaultBackground?.media?.path = path
            }
            try assertInvalid("invalidMediaPath", at: "backgrounds.sections.c1.media.path") {
                $0.backgrounds?.sections?["c1"]?.media?.path = path
            }
        }
    }

    func testValidBackgroundsPass() throws {
        var song = try decodeSong(songWithBackgrounds)
        song.backgrounds?.sections?["b9"] = ThemeBackground(kind: ThemeBackgroundKind(rawValue: "gradient"))
        XCTAssertNoThrow(try song.validate())
    }

    func testDefaultIsCheckedBeforeSectionsAndSectionsInKeyOrder() throws {
        try assertInvalid("missingColor", at: "backgrounds.default.color") {
            $0.backgrounds?.defaultBackground = ThemeBackground(kind: .color)
            $0.backgrounds?.sections?["a"] = ThemeBackground(kind: .color, color: "x")
        }
        try assertInvalid("missingMedia", at: "backgrounds.sections.a.media") {
            $0.backgrounds?.sections = ["b": ThemeBackground(kind: .color, color: "x"),
                                        "a": ThemeBackground(kind: .video), "c": ThemeBackground(kind: .image)]
        }
    }

    func testSongRulesComeBeforeBackgrounds() throws {
        try assertInvalid("duplicateSectionId", at: "sections[1].id") {
            $0.sections[1].id = $0.sections[0].id
            $0.backgrounds?.defaultBackground = ThemeBackground(kind: .color)
        }
    }

    func testColorIsCheckedBeforeMediaEvenForUnknownKinds() throws {
        try assertInvalid("invalidColor", at: "backgrounds.default.color") {
            $0.backgrounds?.defaultBackground = ThemeBackground(kind: .image, color: "zz")
        }
        try assertInvalid("invalidColor", at: "backgrounds.default.color") {
            $0.backgrounds?.defaultBackground = ThemeBackground(kind: ThemeBackgroundKind(rawValue: "gradient"), color: "nope")
        }
    }
}
