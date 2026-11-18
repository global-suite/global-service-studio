import Foundation
import XCTest

@testable import GSSCore

/// Theme slot defaults, slide layouts and layout changes of ADR 0011.
final class TextSlideTests: XCTestCase {
    private let lyrics = ThemeSlot(frame: ThemeFrame(x: 0.1, y: 0.2, width: 0.8, height: 0.5),
                                   font: ThemeFont(family: "Placeholder Sans", weight: .medium, size: 0.05),
                                   color: "#FAFAFA", align: .leading, maxLines: 4, wrap: .balanced)
    private let lyricsFrame = ThemeFrame(x: 0.1, y: 0.2, width: 0.8, height: 0.5)

    private func theme(_ slots: [String: ThemeSlot]) -> Theme {
        Theme(name: "Plain", canvas: ThemeCanvas(width: 1920, height: 1080),
              background: ThemeBackground(kind: .color, color: "#000000"), slots: slots,
              languages: ThemeLanguages(layout: .primaryOnly))
    }

    private func text(_ id: String, _ slot: String, _ value: String) -> PresentationElement {
        PresentationElement(id: id, kind: .text, slot: slot, text: ["en": value])
    }

    private let picture = PresentationElement(
        id: "p1", kind: .image, frame: ThemeFrame(x: 0, y: 0, width: 1, height: 1),
        media: MediaReference(path: "Media/sky.png", sha256: "ab12"))

    func testBodyDefaultCopiesLyricsUnderTheTitle() {
        var expected = lyrics
        expected.frame = ThemeFrame(x: 0.1, y: 0.3, width: 0.8, height: 0.6)
        XCTAssertEqual(theme(["lyrics": lyrics]).slot("body", builtInLyrics: lyrics), expected)
    }

    func testTitleDefaultIsBoldAndLarger() throws {
        let title = try XCTUnwrap(theme(["lyrics": lyrics]).slot("title", builtInLyrics: lyrics))
        XCTAssertEqual(title.frame, ThemeFrame(x: 0.1, y: 0.08, width: 0.8, height: 0.18))
        XCTAssertEqual(title.font.family, "Placeholder Sans")
        XCTAssertEqual(title.font.weight, .bold)
        XCTAssertEqual(title.font.size, 0.07, accuracy: 1e-12)
        XCTAssertEqual([title.color, title.align.rawValue], ["#FAFAFA", "leading"])
        XCTAssertNil(title.maxLines)
    }

    func testCaptionDefaultIsSmallerWithTwoLines() throws {
        let caption = try XCTUnwrap(theme(["lyrics": lyrics]).slot("caption", builtInLyrics: lyrics))
        XCTAssertEqual(caption.frame, ThemeFrame(x: 0.1, y: 0.82, width: 0.8, height: 0.1))
        XCTAssertEqual(caption.font.weight, .medium)
        XCTAssertEqual(caption.font.size, 0.03, accuracy: 1e-12)
        XCTAssertEqual(caption.maxLines, 2)
    }

    func testThemeSlotWinsAndMissingLyricsUsesTheBuiltInOne() throws {
        var own = lyrics
        own.color = "#123456"
        XCTAssertEqual(theme(["title": own]).slot("title", builtInLyrics: lyrics), own)
        let title = try XCTUnwrap(theme([:]).slot("title", builtInLyrics: lyrics))
        XCTAssertEqual(title.font.family, "Placeholder Sans")
        XCTAssertNil(theme([:]).slot("footer", builtInLyrics: lyrics))
    }

    func testNewSlideForEachLayoutHasEmptyTextInItsSlotsAndValidates() throws {
        let expected: [(PresentationSlideLayout, [String])] = [
            (.title, ["title", "body"]), (.titleText, ["title", "body"]), (.text, ["body"]),
            (.imageCaption, ["caption"]), (.image, []),
        ]
        for (layout, slots) in expected {
            let slide = PresentationSlide.empty(id: "n1", layout: layout, language: "en")
            XCTAssertEqual(slide.layout, layout)
            XCTAssertEqual(slide.elements.map { $0.slot ?? "" }, slots)
            XCTAssertEqual(slide.elements.map { $0.text ?? [:] }, slots.map { _ in ["en": ""] })
            XCTAssertNoThrow(try Presentation(title: "New", slides: [slide]).validate())
        }
    }

    func testTitleToTextJoinsTheTitleIntoTheBody() {
        let slide = PresentationSlide(id: "s1", elements: [text("t", "title", "Hello"), text("b", "body", "Line")],
                                      layout: .title)
        let changed = slide.changingLayout(to: .text, lyricsFrame: lyricsFrame)
        XCTAssertEqual(changed.layout, .text)
        XCTAssertEqual(changed.elements, [text("b", "body", "Line\nHello")])
    }

    func testTitleTextToImageCaptionMovesTextToTheBody() {
        let slide = PresentationSlide(id: "s1", elements: [text("t", "title", "Hello"), text("b", "body", "")],
                                      layout: .titleText)
        let changed = slide.changingLayout(to: .imageCaption, lyricsFrame: lyricsFrame)
        XCTAssertEqual(changed.elements, [text("b", "body", "Hello")])
    }

    func testImageCaptionToTextDropsTheImage() {
        let slide = PresentationSlide(id: "s1", elements: [picture, text("c", "caption", "Below")],
                                      layout: .imageCaption)
        let changed = slide.changingLayout(to: .text, lyricsFrame: lyricsFrame)
        XCTAssertEqual(changed.elements, [text("c", "body", "Below")])
    }

    func testImageToImageCaptionKeepsTheImageInTheLayoutFrame() {
        let slide = PresentationSlide(id: "s1", elements: [picture], layout: .image)
        let changed = slide.changingLayout(to: .imageCaption, lyricsFrame: lyricsFrame)
        var moved = picture
        moved.frame = ThemeFrame(x: 0.1, y: 0.08, width: 0.8, height: 0.7)
        XCTAssertEqual(changed.elements, [moved])
        let back = changed.changingLayout(to: .image, lyricsFrame: lyricsFrame)
        XCTAssertEqual(back.elements, [picture])
    }

    func testTextToImageKeepsTheTextInTheBody() {
        let slide = PresentationSlide(id: "s1", elements: [text("b", "body", "Kept")], layout: .text)
        XCTAssertEqual(slide.changingLayout(to: .image, lyricsFrame: lyricsFrame).elements, [text("b", "body", "Kept")])
    }

    func testUnknownLayoutKeepsTheElements() {
        let slide = PresentationSlide(id: "s1", elements: [picture, text("t", "title", "Hello")], layout: .title)
        let changed = slide.changingLayout(to: PresentationSlideLayout(rawValue: "split"), lyricsFrame: lyricsFrame)
        XCTAssertEqual(changed.layout, PresentationSlideLayout(rawValue: "split"))
        XCTAssertEqual(changed.elements, slide.elements)
    }
}
