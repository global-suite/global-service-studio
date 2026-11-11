import Foundation
import XCTest

@testable import GSSCore

final class ThemeValidationTests: XCTestCase {
    /// Edits the example; with a `reason`, validation must fail with it at `path`, otherwise pass.
    private func check(_ reason: String?, at path: String = "", _ edit: (inout Theme) -> Void) throws {
        var theme = try decodeTheme()
        edit(&theme)
        guard let reason else { return XCTAssertNoThrow(try theme.validate()) }
        XCTAssertThrowsError(try theme.validate(), path) {
            XCTAssertEqual($0 as? FormatError, .validation(reason: reason, at: path))
        }
    }

    func testDecodingRunsValidation() {
        assertDecodeThrows(.validation(reason: "invalidMaxLines", at: "slots.lyrics.maxLines"),
                           [(#""maxLines": 4"#, #""maxLines": 0"#)])
    }

    func testCanvasSizeIsPositive() throws {
        try check("nonPositiveSize", at: "canvas.width") { $0.canvas.width = 0 }
        try check("nonPositiveSize", at: "canvas.height") { $0.canvas.height = -1 }
    }

    func testFrameSizeIsPositive() throws {
        try check("nonPositiveSize", at: "slots.lyrics.frame.width") { $0.slots["lyrics"]?.frame.width = 0 }
        try check("nonPositiveSize", at: "slots.footer.frame.height") { $0.slots["footer"]?.frame.height = 0 }
    }

    func testFrameLiesWithinTheCanvas() throws {
        try check("frameOutsideCanvas", at: "slots.lyrics.frame") { $0.slots["lyrics"]?.frame.x = -0.01 }
        try check("frameOutsideCanvas", at: "slots.lyrics.frame") { $0.slots["lyrics"]?.frame.y = -0.01 }
        try check("frameOutsideCanvas", at: "slots.lyrics.frame") { $0.slots["lyrics"]?.frame.x = 0.17 }
        try check("frameOutsideCanvas", at: "slots.footer.frame") { $0.slots["footer"]?.frame.y = 0.96 }
        try check(nil) { $0.slots["footer"]?.frame = ThemeFrame(x: 0.7, y: 0.9, width: 0.3, height: 0.1) }
    }

    func testFontSizeIsPositive() throws {
        try check("nonPositiveSize", at: "slots.footer.font.size") { $0.slots["footer"]?.font.size = 0 }
    }

    func testMaxLinesIsAtLeastOne() throws {
        try check("invalidMaxLines", at: "slots.translation.maxLines") { $0.slots["translation"]?.maxLines = 0 }
        try check(nil) { $0.slots["translation"]?.maxLines = 1 }
    }

    func testColorsAreHex() throws {
        try check("invalidColor", at: "background.color") { $0.background.color = "black" }
        try check("invalidColor", at: "slots.lyrics.color") { $0.slots["lyrics"]?.color = "#FFF" }
        try check("invalidColor", at: "slots.footer.color") { $0.slots["footer"]?.color = "#GG0000" }
        try check(nil) { $0.slots["footer"]?.color = "#ffffff80" }
    }

    func testColorBackgroundHasAColor() throws {
        try check("missingColor", at: "background.color") { $0.background.color = nil }
    }

    func testMediaBackgroundHasARelativePath() throws {
        try check("missingMedia", at: "background.media") { $0.background = ThemeBackground(kind: .video) }
        for path in ["", "/Users/a/sky.jpg", "~/sky.jpg", "media/../../sky.jpg"] {
            try check("invalidMediaPath", at: "background.media.path") {
                $0.background = ThemeBackground(kind: .image, media: ThemeMediaReference(path: path, sha256: "ab12"))
            }
        }
    }
}
