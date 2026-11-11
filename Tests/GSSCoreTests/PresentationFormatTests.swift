import Foundation
import XCTest

@testable import GSSCore

/// The presentation example of ADR 0005.
let presentationExample = """
{
  "format": "gss.presentation", "version": 1, "id": "0a9d3f77-41c2-4b0e-9d6a-3c5f2e8b7a19", "title": "Welcome",
  "theme": "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421",
  "slides": [
    { "id": "s1", "label": "Welcome", "elements": [
      { "id": "e1", "kind": "text", "slot": "lyrics", "text": { "en": "Welcome", "es": "Bienvenidos" } },
      { "id": "e2", "kind": "image", "frame": { "x": 0.4, "y": 0.05, "width": 0.2, "height": 0.12 },
        "media": { "path": "Media/logo.png", "sha256": "…" } }
    ] }
  ]
}
"""

/// The canonical bytes of the example with each `(old, new)` text replacement applied.
func presentationData(_ replacements: [(String, String)] = []) throws -> Data {
    let json = replacements.reduce(presentationExample) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    return try JSONValue(parsing: Data(json.utf8)).canonicalData()
}

func decodePresentation(_ replacements: [(String, String)] = []) throws -> Presentation {
    try Presentation.decode(from: presentationData(replacements))
}

func assertPresentationDecodeThrows(_ error: FormatError, _ replacements: [(String, String)]) {
    XCTAssertThrowsError(try decodePresentation(replacements)) { XCTAssertEqual($0 as? FormatError, error) }
}

final class PresentationFormatTests: XCTestCase {
    private func assertRoundTrips(_ replacements: [(String, String)]) throws {
        XCTAssertEqual(try decodePresentation(replacements).encoded(), try presentationData(replacements))
    }

    func testDecodesTheExample() throws {
        let presentation = try decodePresentation()
        XCTAssertEqual(presentation.id, UUID(uuidString: "0a9d3f77-41c2-4b0e-9d6a-3c5f2e8b7a19"))
        XCTAssertEqual(presentation.title, "Welcome")
        XCTAssertEqual(presentation.theme, UUID(uuidString: "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421"))
        XCTAssertEqual(presentation.slides.map(\.id), ["s1"])
        XCTAssertEqual(presentation.slides[0].label, "Welcome")
        XCTAssertEqual(presentation.slides[0].elements, [
            PresentationElement(id: "e1", kind: .text, slot: "lyrics", text: ["en": "Welcome", "es": "Bienvenidos"]),
            PresentationElement(id: "e2", kind: .image, frame: ThemeFrame(x: 0.4, y: 0.05, width: 0.2, height: 0.12),
                                media: MediaReference(path: "Media/logo.png", sha256: "…")),
        ])
    }

    func testEncodingTheExampleGivesCanonicalBytes() throws {
        try assertRoundTrips([])
        let presentation = try decodePresentation()
        XCTAssertEqual(try Presentation.decode(from: presentation.encoded()), presentation)
        XCTAssertTrue(String(decoding: try presentation.encoded(), as: UTF8.self)
            .contains(#""theme": "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421""#))
    }

    func testUnknownFieldsSurviveAtEveryLevel() throws {
        let edits = [
            (#""title": "Welcome","#, #""title": "Welcome", "x-presentation": 1,"#),
            (#""label": "Welcome","#, #""label": "Welcome", "x-slide": true,"#),
            (#""id": "e1","#, #""id": "e1", "x-element": [1],"#),
        ]
        try assertRoundTrips(edits)
        let presentation = try decodePresentation(edits)
        XCTAssertEqual(presentation.unknown, ["x-presentation": .integer(1)])
        XCTAssertEqual(presentation.slides[0].unknown, ["x-slide": .bool(true)])
        XCTAssertEqual(presentation.slides[0].elements[0].unknown, ["x-element": .array([.integer(1)])])
    }

    func testUnknownElementKindSurvives() throws {
        let edits = [(#""kind": "text""#, #""kind": "countdown""#)]
        try assertRoundTrips(edits)
        XCTAssertEqual(try decodePresentation(edits).slides[0].elements[0].kind,
                       PresentationElementKind(rawValue: "countdown"))
    }

    func testAbsentOptionalFieldsStayAbsent() throws {
        let presentation = try decodePresentation([(#""theme": "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421","#, "")])
        XCTAssertNil(presentation.theme)
        XCTAssertNil(presentation.slides[0].notes)
        XCTAssertNil(presentation.slides[0].elements[0].frame)
        XCTAssertNil(presentation.slides[0].elements[1].font)
        let text = String(decoding: try presentation.encoded(), as: UTF8.self)
        for key in ["theme", "notes", "font", "color", "align", "externalIds", "extensions"] {
            XCTAssertFalse(text.contains("\"\(key)\""), key)
        }
    }

    func testNewerVersionIsRejected() {
        assertPresentationDecodeThrows(.unsupportedVersion(found: 2, supported: 1),
                                       [(#""version": 1"#, #""version": 2"#)])
    }

    func testWrongFormatIsRejected() {
        assertPresentationDecodeThrows(.wrongFormat(expected: "gss.presentation", found: "gss.theme"),
                                       [(#""gss.presentation""#, #""gss.theme""#)])
    }

    func testThemeMustBeAUUID() {
        assertPresentationDecodeThrows(.invalidField("theme"),
                                       [(#""b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421""#, #""Clean Dark""#)])
    }

    func testMissingRequiredFieldReportsItsKeyPath() {
        assertPresentationDecodeThrows(.missingField("slides[0].elements[1].media.sha256"),
                                       [(#", "sha256": "…""#, "")])
    }
}
