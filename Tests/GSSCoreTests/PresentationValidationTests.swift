import Foundation
import XCTest

@testable import GSSCore

final class PresentationValidationTests: XCTestCase {
    /// Edits the example; with a `reason`, validation must fail with it at `path`, otherwise pass.
    private func check(_ reason: String?, at path: String = "", _ edit: (inout [PresentationElement]) -> Void) throws {
        var presentation = try decodePresentation()
        edit(&presentation.slides[0].elements)
        guard let reason else { return XCTAssertNoThrow(try presentation.validate()) }
        XCTAssertThrowsError(try presentation.validate(), path) {
            XCTAssertEqual($0 as? FormatError, .validation(reason: reason, at: path))
        }
    }

    private let element = "slides[0].elements[1]"

    func testDecodingRunsValidation() {
        assertPresentationDecodeThrows(.validation(reason: "duplicateElementId", at: "slides[0].elements[1].id"),
                                       [(#""id": "e2""#, #""id": "e1""#)])
    }

    func testSlideIdsAreUnique() throws {
        var presentation = try decodePresentation()
        presentation.slides.append(PresentationSlide(id: "s1", elements: []))
        XCTAssertThrowsError(try presentation.validate()) {
            XCTAssertEqual($0 as? FormatError, .validation(reason: "duplicateSlideId", at: "slides[1].id"))
        }
    }

    func testElementIdsAreUniqueWithinASlide() throws {
        try check("duplicateElementId", at: "\(element).id") { $0[1].id = "e1" }
    }

    func testTextElementHasText() throws {
        try check("missingText", at: "slides[0].elements[0].text") { $0[0].text = nil }
        try check("missingText", at: "slides[0].elements[0].text") { $0[0].text = [:] }
    }

    func testTextElementHasASlotOrAFrame() throws {
        try check("missingSlotOrFrame", at: "slides[0].elements[0]") { $0[0].slot = nil }
        try check(nil) { $0[0].slot = nil; $0[0].frame = ThemeFrame(x: 0.1, y: 0.1, width: 0.5, height: 0.5) }
    }

    func testMediaElementHasAFrame() throws {
        try check("missingFrame", at: "\(element).frame") { $0[1].frame = nil }
    }

    func testMediaElementHasARelativePath() throws {
        try check("missingMedia", at: "\(element).media") { $0[1].kind = .video; $0[1].media = nil }
        for path in ["", "/Users/a/logo.png", "~/logo.png", "Media/../../logo.png"] {
            try check("invalidMediaPath", at: "\(element).media.path") { $0[1].media?.path = path }
        }
    }

    func testFrameSizeIsPositive() throws {
        try check("nonPositiveSize", at: "\(element).frame.width") { $0[1].frame?.width = 0 }
        try check("nonPositiveSize", at: "\(element).frame.height") { $0[1].frame?.height = -1 }
    }

    func testFrameLiesWithinTheCanvas() throws {
        try check("frameOutsideCanvas", at: "\(element).frame") { $0[1].frame?.x = -0.01 }
        try check("frameOutsideCanvas", at: "\(element).frame") { $0[1].frame?.y = -0.01 }
        try check("frameOutsideCanvas", at: "\(element).frame") { $0[1].frame?.x = 0.81 }
        try check("frameOutsideCanvas", at: "\(element).frame") { $0[1].frame?.y = 0.89 }
        try check(nil) { $0[1].frame = ThemeFrame(x: 0.7, y: 0.9, width: 0.3, height: 0.1) }
    }

    func testFontSizeIsPositive() throws {
        let font = ThemeFont(family: "Helvetica Neue", weight: .bold, size: 0)
        try check("nonPositiveSize", at: "slides[0].elements[0].font.size") { $0[0].font = font }
    }

    func testColorsAreHex() throws {
        try check("invalidColor", at: "slides[0].elements[0].color") { $0[0].color = "white" }
        try check("invalidColor", at: "slides[0].elements[0].color") { $0[0].color = "#FFF" }
        try check(nil) { $0[0].color = "#ffffff80" }
    }

    func testUnknownKindIsOnlyCheckedForFrameFontAndColor() throws {
        let clock = PresentationElement(id: "e2", kind: PresentationElementKind(rawValue: "clock"))
        try check(nil) { $0[1] = clock }
        try check("frameOutsideCanvas", at: "\(element).frame") {
            $0[1] = clock; $0[1].frame = ThemeFrame(x: 0.9, y: 0, width: 0.2, height: 0.1)
        }
        try check("invalidColor", at: "\(element).color") { $0[1] = clock; $0[1].color = "red" }
    }
}
