import AppKit
import CoreGraphics
import GSSCore
import SwiftUI
import XCTest
@testable import GSSApp

final class OutputThemeTests: XCTestCase {
    private func lyrics(_ theme: Theme) throws -> ThemeSlot { try XCTUnwrap(theme.slots[Theme.lyricsSlot]) }

    private func assertRect(_ rect: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (value, wanted) in [(rect.minX, expected.minX), (rect.minY, expected.minY), (rect.width, expected.width), (rect.height, expected.height)] {
            XCTAssertEqual(value, wanted, accuracy: 0.001, file: file, line: line)
        }
    }

    func testBuiltInThemesAreValidAndRoundTrip() throws {
        for theme in [OutputThemes.audience, OutputThemes.key] {
            XCTAssertNoThrow(try theme.validate())
            XCTAssertEqual(try Theme.decode(from: theme.encoded()), theme)
            XCTAssertEqual(theme.background.kind, .color)
            XCTAssertEqual(try lyrics(theme).font.weight, .bold)
            XCTAssertEqual(try lyrics(theme).color, "#FFFFFF")
            XCTAssertEqual(try lyrics(theme).align, .center)
        }
        XCTAssertEqual(OutputThemes.audience.background.color, "#000000")
        XCTAssertNotEqual(OutputThemes.audience.id, OutputThemes.key.id)
        XCTAssertEqual(OutputThemes.theme(for: .audience), OutputThemes.audience)
        XCTAssertEqual(OutputThemes.theme(for: .key), OutputThemes.key)
        XCTAssertEqual(OutputThemes.theme(for: .stage), OutputThemes.audience)
        XCTAssertEqual(AudienceOutputView(state: AppState()).theme, OutputThemes.audience)
        XCTAssertEqual(KeyOutputView(state: AppState()).theme, OutputThemes.key)
    }

    func testLayoutConvertsFractionsToPoints() throws {
        let audience = try lyrics(OutputThemes.audience), key = try lyrics(OutputThemes.key)
        var layout = SlotLayout(slot: audience, size: CGSize(width: 1920, height: 1080), lineCount: 2)
        assertRect(layout.frame, CGRect(x: 115.2, y: 108, width: 1689.6, height: 864))
        XCTAssertEqual(layout.fontSize, 75.6, accuracy: 0.001)
        XCTAssertEqual(layout.font.pointSize, 75.6, accuracy: 0.001)
        layout = SlotLayout(slot: audience, size: CGSize(width: 1280, height: 720), lineCount: 2)
        assertRect(layout.frame, CGRect(x: 76.8, y: 72, width: 1126.4, height: 576))
        XCTAssertEqual(layout.fontSize, 50.4, accuracy: 0.001)
        layout = SlotLayout(slot: key, size: CGSize(width: 1920, height: 1080), lineCount: 2)
        assertRect(layout.frame, CGRect(x: 96, y: 734.4, width: 1728, height: 280.8))
        XCTAssertEqual(layout.fontSize, 64.8, accuracy: 0.001)
        layout = SlotLayout(slot: key, size: CGSize(width: 1280, height: 720), lineCount: 2)
        assertRect(layout.frame, CGRect(x: 64, y: 489.6, width: 1152, height: 187.2))
        XCTAssertEqual(layout.fontSize, 43.2, accuracy: 0.001)
    }

    func testLayoutShrinksTheFontSoEveryLineFitsTheSlotHeight() throws {
        let key = try lyrics(OutputThemes.key)
        let layout = SlotLayout(slot: key, size: CGSize(width: 1920, height: 1080), lineCount: 8)
        XCTAssertLessThan(layout.fontSize, 64.8)
        XCTAssertLessThanOrEqual(NSLayoutManager().defaultLineHeight(for: layout.font) * 8, layout.frame.height + 0.001)
        XCTAssertEqual(layout.font.pointSize, layout.fontSize, accuracy: 0.001)
        XCTAssertEqual(SlotLayout(slot: key, size: CGSize(width: 1920, height: 1080), lineCount: 0).fontSize, 64.8, accuracy: 0.001)
    }

    func testAlignmentMapsFromTheTheme() throws {
        var slot = try lyrics(OutputThemes.audience)
        let size = CGSize(width: 1920, height: 1080)
        let cases: [(ThemeAlignment, TextAlignment, Alignment)] = [
            (.leading, .leading, .leading), (.center, .center, .center), (.trailing, .trailing, .trailing),
            (ThemeAlignment(rawValue: "justified"), .center, .center),
        ]
        for (align, text, frame) in cases {
            slot.align = align
            let layout = SlotLayout(slot: slot, size: size)
            XCTAssertEqual(layout.textAlignment, text, align.rawValue)
            XCTAssertEqual(layout.alignment, frame, align.rawValue)
        }
    }

    func testFontUsesTheFamilyAndFallsBackToTheSystemFont() {
        let installed = SlotLayout.font(ThemeFont(family: "Helvetica Neue", weight: .bold, size: 0.07), size: 50)
        XCTAssertEqual(installed.familyName, "Helvetica Neue")
        XCTAssertEqual(installed.pointSize, 50)
        XCTAssertTrue(NSFontManager.shared.traits(of: installed).contains(.boldFontMask))
        let regular = SlotLayout.font(ThemeFont(family: "Helvetica Neue", weight: .regular, size: 0.07), size: 50)
        XCTAssertFalse(NSFontManager.shared.traits(of: regular).contains(.boldFontMask))

        let missing = SlotLayout.font(ThemeFont(family: "Invented Missing Sans", weight: .bold, size: 0.07), size: 40)
        let system = NSFont.systemFont(ofSize: 40, weight: .bold)
        XCTAssertEqual(missing.familyName, system.familyName)
        XCTAssertEqual(missing.fontName, system.fontName)
        XCTAssertEqual(missing.pointSize, 40)
    }

    func testThemeColorsParseWithAndWithoutAlpha() {
        XCTAssertEqual(RGBA(themeHex: "#FFFFFF"), RGBA(255, 255, 255))
        XCTAssertEqual(RGBA(themeHex: "#0b1f3a"), RGBA(hex: 0x0B1F3A))
        XCTAssertEqual(RGBA(themeHex: "#FF000080"), RGBA(255, 0, 0, 128.0 / 255))
        for invalid in ["white", "#FFF", "FFFFFF", "#GGGGGG", "#FFFFFFF", ""] { XCTAssertNil(RGBA(themeHex: invalid), invalid) }
        var slot = ThemeSlot(frame: ThemeFrame(x: 0, y: 0, width: 1, height: 1), font: ThemeFont(family: "Helvetica Neue", weight: .bold, size: 0.1),
                             color: "#102030", align: .center)
        XCTAssertEqual(SlotLayout(slot: slot, size: CGSize(width: 100, height: 100)).color, RGBA(hex: 0x102030))
        slot.color = "nope"
        XCTAssertEqual(SlotLayout(slot: slot, size: CGSize(width: 100, height: 100)).color, RGBA(255, 255, 255))
    }

    func testAudienceMediaShowsTheThemeColorUntilABackgroundIsChosenAndKeyNever() throws {
        let state = AppState()
        var theme = OutputThemes.audience
        theme.background = ThemeBackground(kind: .color, color: "#102030")
        XCTAssertEqual(state.mediaFill(for: .audience, theme: theme), .color(RGBA(hex: 0x102030)))
        XCTAssertEqual(state.mediaFill(for: .audience, theme: OutputThemes.audience), .color(RGBA(hex: 0x000000)))
        XCTAssertNil(state.mediaFill(for: .key, theme: theme), "the key output never shows the media layer")
        XCTAssertNil(state.mediaFill(for: .stage, theme: theme))
        state.perform(.setBackground(.color("#0B1F3A")))
        XCTAssertEqual(state.mediaFill(for: .audience, theme: theme), .color(RGBA(hex: 0x0B1F3A)), "a chosen background wins")
        XCTAssertNil(state.mediaFill(for: .key, theme: theme))
        state.perform(.clearBackground)
        XCTAssertEqual(state.mediaFill(for: .audience, theme: theme), .color(RGBA(hex: 0x102030)))
        XCTAssertNil(state.mediaFill(for: .audience), "the operator's background alone is still nil")

        theme.background = ThemeBackground(kind: .image, media: MediaReference(path: "Media/invented.jpg", sha256: String(repeating: "a", count: 64)))
        XCTAssertNil(state.mediaFill(for: .audience, theme: theme), "image and video theme backgrounds wait for the media bin")
    }

    func testOutputsDrawTheThemedSlideLayerAtEverySize() throws {
        let state = AppState()
        let leading = { () -> ThemeSlot in var slot = try! self.lyrics(OutputThemes.audience); slot.align = .leading; return slot }()
        let views = [AnyView(AudienceOutputView(state: state)), AnyView(KeyOutputView(state: state)),
                     AnyView(SlideLayer(lines: ["Invented line one", "Invented line two"], slot: leading)),
                     AnyView(SlideLayer(lines: [], slot: try lyrics(OutputThemes.key), shadow: true))]
            + LiveOutput.samples.map { AnyView(OutputMonitor(output: $0, state: state, width: 320)) }
        for size in [NSSize(width: 1920, height: 1080), NSSize(width: 1280, height: 720)] {
            for view in views {
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.fittingSize.height, 0)
            }
        }
    }
}
