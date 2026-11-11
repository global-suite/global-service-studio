import Foundation
import XCTest

@testable import GSSCore

/// The theme example of ADR 0005.
let themeExample = """
{
  "format": "gss.theme", "version": 1, "id": "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421", "name": "Clean Dark",
  "canvas": { "width": 1920, "height": 1080 }, "background": { "kind": "color", "color": "#000000" },
  "slots": {
    "lyrics": { "frame": { "x": 0.08, "y": 0.2, "width": 0.84, "height": 0.6 },
      "font": { "family": "Helvetica Neue", "weight": "bold", "size": 0.075 },
      "color": "#FFFFFF", "align": "center", "maxLines": 4, "wrap": "balanced" },
    "translation": { "frame": { "x": 0.08, "y": 0.62, "width": 0.84, "height": 0.25 },
      "font": { "family": "Helvetica Neue", "weight": "regular", "size": 0.05 },
      "color": "#CFCFCF", "align": "center", "maxLines": 4, "wrap": "balanced" },
    "footer": { "frame": { "x": 0.08, "y": 0.92, "width": 0.84, "height": 0.05 },
      "font": { "family": "Helvetica Neue", "weight": "regular", "size": 0.02 }, "color": "#8A8A8A", "align": "center" }
  },
  "languages": { "layout": "stacked" }
}
"""

/// The canonical bytes of the example with each `(old, new)` text replacement applied.
func themeData(_ replacements: [(String, String)] = []) throws -> Data {
    let json = replacements.reduce(themeExample) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    return try JSONValue(parsing: Data(json.utf8)).canonicalData()
}

func decodeTheme(_ replacements: [(String, String)] = []) throws -> Theme {
    try Theme.decode(from: themeData(replacements))
}

func assertDecodeThrows(_ error: FormatError, _ replacements: [(String, String)]) {
    XCTAssertThrowsError(try decodeTheme(replacements)) { XCTAssertEqual($0 as? FormatError, error) }
}

final class ThemeFormatTests: XCTestCase {
    private func assertRoundTrips(_ replacements: [(String, String)]) throws {
        XCTAssertEqual(try decodeTheme(replacements).encoded(), try themeData(replacements))
    }

    func testDecodesTheExample() throws {
        let theme = try decodeTheme()
        XCTAssertEqual(theme.id, UUID(uuidString: "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421"))
        XCTAssertEqual(theme.name, "Clean Dark")
        XCTAssertEqual(theme.canvas, ThemeCanvas(width: 1920, height: 1080))
        XCTAssertEqual(theme.background, ThemeBackground(kind: .color, color: "#000000"))
        XCTAssertEqual(theme.slots[Theme.lyricsSlot], ThemeSlot(
            frame: ThemeFrame(x: 0.08, y: 0.2, width: 0.84, height: 0.6),
            font: ThemeFont(family: "Helvetica Neue", weight: .bold, size: 0.075),
            color: "#FFFFFF", align: .center, maxLines: 4, wrap: .balanced))
        XCTAssertEqual(theme.slots[Theme.footerSlot]?.font.weight, .regular)
        XCTAssertEqual(theme.languages.layout, .stacked)
    }

    func testEncodingTheExampleGivesCanonicalBytes() throws {
        try assertRoundTrips([])
        let theme = try decodeTheme()
        XCTAssertEqual(try Theme.decode(from: theme.encoded()), theme)
    }

    func testUnknownFieldsSurviveAtEveryLevel() throws {
        let edits = [
            (#""name": "Clean Dark","#, #""name": "Clean Dark", "x-theme": 1,"#),
            (#""footer": {"#, #""footer": { "x-slot": true,"#), (#"0.05 }"#, #"0.05, "x-f": [1] }"#),
            (#""size": 0.02 }"#, #""size": 0.02, "x-font": "f" }"#), (#"1080 }"#, #"1080, "x": 2 }"#),
            (#""kind": "color","#, #""kind": "color", "x-bg": null,"#), (#""stacked""#, #""stacked", "x": 3"#),
        ]
        try assertRoundTrips(edits)
        XCTAssertEqual(try decodeTheme(edits).slots["footer"]?.unknown, ["x-slot": .bool(true)])
    }

    func testUnknownValuesSurvive() throws {
        let edits = [(#""footer""#, #""ticker""#), (#""balanced""#, #""shrink""#),
                     (#""stacked""#, #""sideBySide""#), (#""kind": "color""#, #""kind": "gradient""#)]
        try assertRoundTrips(edits)
        let theme = try decodeTheme(edits)
        XCTAssertNotNil(theme.slots["ticker"])
        XCTAssertEqual(theme.slots["lyrics"]?.wrap, ThemeWrap(rawValue: "shrink"))
        XCTAssertEqual(theme.languages.layout, ThemeLanguageLayout(rawValue: "sideBySide"))
        XCTAssertEqual(theme.background.kind, ThemeBackgroundKind(rawValue: "gradient"))
    }

    func testAbsentOptionalFieldsStayAbsent() throws {
        let theme = try decodeTheme()
        XCTAssertNil(theme.slots["footer"]?.maxLines)
        XCTAssertNil(theme.slots["footer"]?.wrap)
        XCTAssertFalse(String(decoding: try theme.encoded(), as: UTF8.self).contains("externalIds"))
    }

    func testNewerVersionIsRejected() {
        assertDecodeThrows(.unsupportedVersion(found: 2, supported: 1), [(#""version": 1"#, #""version": 2"#)])
    }

    func testWrongFormatIsRejected() {
        assertDecodeThrows(.wrongFormat(expected: "gss.theme", found: "gss.song"), [(#""gss.theme""#, #""gss.song""#)])
    }

    func testMissingRequiredFieldReportsItsKeyPath() {
        assertDecodeThrows(.missingField("slots.footer.font.size"), [(#", "size": 0.02"#, "")])
    }

    func testImageBackgroundWithMediaDecodes() throws {
        let image = [(##""kind": "color", "color": "#000000""##,
                      #""kind": "image", "media": { "path": "media/sky.jpg", "sha256": "ab12", "x-media": 1 }"#)]
        let media = try decodeTheme(image).background.media
        XCTAssertEqual(media?.path, "media/sky.jpg")
        XCTAssertEqual(media?.unknown, ["x-media": .integer(1)])
        try assertRoundTrips(image)
    }
}
