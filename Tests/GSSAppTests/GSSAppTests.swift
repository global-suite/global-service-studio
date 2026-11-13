import AppKit
import Combine
import SwiftUI
import XCTest
@testable import GSSApp

final class GSSAppTests: XCTestCase {
    private func strings(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(Strings.bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    func testEnglishAndSpanishHaveTheSameKeysAndNoEmptyValues() throws {
        let english = try strings("en"), spanish = try strings("es")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(spanish.keys))
        XCTAssertFalse(english.values.contains { $0.isEmpty } || spanish.values.contains { $0.isEmpty })
    }

    func testModeNamesAreTranslated() throws {
        let english = try strings("en"), spanish = try strings("es")
        XCTAssertNotEqual(english["Prepare"], spanish["Prepare"])
        XCTAssertNotEqual(english["Live"], spanish["Live"])
    }

    func testStateStartsInPrepareAndChangesThroughCommands() {
        let state = AppState()
        var published: [AppMode] = []
        let subscription = state.$mode.dropFirst().sink { published.append($0) }
        XCTAssertEqual(state.mode, .prepare)
        state.perform(.setMode(.live))
        state.perform(.setMode(.live))
        XCTAssertEqual(state.mode, .live)
        XCTAssertEqual(published, [.live])
        subscription.cancel()
    }

    func testMidnightIsTheDefaultAndPalettesDiffer() {
        XCTAssertEqual(Appearance.standard, .midnight)
        XCTAssertEqual(Appearance.midnight.window, RGBA(28, 28, 28))
        XCTAssertEqual(Set([Appearance.midnight, .graphite, .black].map { "\($0.window)" }).count, 3)
    }

    func testWindowHasLocalizedModeSwitchInTheToolbar() throws {
        let controller = MainWindowController(state: AppState())
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(controller.modeControl.segmentCount, 2)
        XCTAssertEqual((0..<2).map { controller.modeControl.label(forSegment: $0) }, AppMode.allCases.map(\.title))
        XCTAssertEqual(window.toolbar?.centeredItemIdentifier, .mode)
        XCTAssertEqual(window.contentMinSize, NSSize(width: 1100, height: 700))
        let liveItem = NSMenuItem()
        liveItem.tag = 1
        controller.selectMode(liveItem)
        XCTAssertEqual(controller.modeControl.selectedSegment, 1)
    }

    func testInterfaceFollowsTheSystemLanguageWithoutAnAppBundle() {
        XCTAssertEqual(Strings.language(for: ["es-US", "en-US"]), "es")
        XCTAssertEqual(Strings.language(for: ["fr-FR", "en-GB"]), "en")
        XCTAssertEqual(Strings.text("Live", language: "es"), "En vivo")
    }

    func testSampleSongHasElevenSlidesInArrangementOrder() {
        let slides = AppState().slides
        XCTAssertEqual(slides.map(\.section), ["Verse 1", "Verse 1", "Chorus", "Chorus", "Verse 2", "Verse 2", "Chorus", "Chorus", "Bridge", "Chorus", "Chorus"])
        XCTAssertEqual(slides[2].lines, ["We lift our voice", "We lift our eyes"])
        XCTAssertEqual([slides[2].part, slides[2].partCount, slides[3].part, slides[8].partCount], [1, 2, 2, 1])
    }

    func testSlideCommandsMoveTheLiveSlideAndStopAtTheEnds() {
        let state = AppState()
        var published: [Int] = []
        let subscription = state.$liveIndex.dropFirst().sink { published.append($0) }
        XCTAssertEqual(state.liveIndex, 0)
        XCTAssertNil(state.previousSlide)
        state.perform(.previousSlide)
        XCTAssertEqual(state.liveIndex, 0)
        state.perform(.nextSlide)
        XCTAssertEqual([state.previousSlide, state.liveSlide, state.nextSlide], Array(state.slides[0...2]))
        state.perform(.goToSlide(10))
        XCTAssertNil(state.nextSlide)
        state.perform(.nextSlide)
        state.perform(.goToSlide(11))
        state.perform(.goToSlide(-1))
        XCTAssertEqual(state.liveIndex, 10)
        XCTAssertEqual(published, [1, 10])
        subscription.cancel()
    }

    func testLiveKeysMoveTheSlideOnlyInLiveMode() throws {
        let controller = MainWindowController(state: AppState())
        let window = try XCTUnwrap(controller.window)
        func key(_ code: UInt16, _ characters: String) -> NSEvent? {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            return controller.handleKey(try! XCTUnwrap(event))
        }
        XCTAssertNotNil(key(49, " "))
        XCTAssertEqual(controller.state.liveIndex, 0)
        controller.state.perform(.setMode(.live))
        XCTAssertNil(key(49, " "))
        XCTAssertNil(key(124, "\u{F703}"))
        XCTAssertNil(key(123, "\u{F702}"))
        XCTAssertNotNil(key(0, "a"))
        XCTAssertEqual(controller.state.liveIndex, 1)
    }

    func testLiveLabelsAreTranslatedAndTheLiveViewLaysOut() {
        XCTAssertEqual(Strings.text("LIVE", language: "es"), "EN VIVO")
        XCTAssertEqual(Strings.text("NEXT", language: "es"), "SIGUIENTE")
        XCTAssertEqual(String(format: Strings.text("%1$@ · %2$ld of %3$ld", language: "es"), "Coro", 1, 2), "Coro · 1 de 2")
        let view = NSHostingView(rootView: LiveView(state: AppState(), appearance: .standard))
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 850)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }
    func testSizeClassAndGridColumnsFollowTheContentWidth() {
        XCTAssertEqual([1100, 1599, 1600, 2399, 2400, 3440].map { SizeClass(contentWidth: $0) }, [.compact, .compact, .regular, .regular, .wide, .wide])
        XCTAssertEqual(SizeClass.compact.gridColumns(slides: 11, width: 1100, height: 200), 5)
        XCTAssertEqual([420, 480, 900].map { SizeClass.regular.gridColumns(slides: 11, width: 1200, height: $0) }, [6, 5, 4])
        XCTAssertEqual(SizeClass.wide.gridColumns(slides: 40, width: 2600, height: 500), 6)
        XCTAssertEqual(SizeClass.wide.gridColumns(slides: 3, width: 2600, height: 2000), 4)
    }

    func testClearCommandsBlankTheLiveSlideUntilTheOperatorMoves() {
        let state = AppState()
        var published: [Bool] = []
        let subscription = state.$isCleared.dropFirst().sink { published.append($0) }
        XCTAssertEqual(state.shownLines, state.slides[0].lines)
        state.perform(.clearSlide)
        XCTAssertTrue(state.isCleared)
        XCTAssertEqual(state.shownLines, [])
        state.perform(.nextSlide)
        XCTAssertEqual([state.liveIndex, state.shownLines.count], [1, 2])
        state.perform(.clearAll)
        state.perform(.goToSlide(1))
        XCTAssertFalse(state.isCleared)
        state.perform(.clearSlide)
        state.perform(.previousSlide)
        XCTAssertEqual(state.liveIndex, 0)
        XCTAssertEqual(published, [true, false, true, false, true, false])
        subscription.cancel()
    }

    func testFunctionKeysClearOnlyInLiveMode() throws {
        let controller = MainWindowController(state: AppState())
        let window = try XCTUnwrap(controller.window)
        func key(_ code: UInt16) -> NSEvent? {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)
            return controller.handleKey(try! XCTUnwrap(event))
        }
        XCTAssertNotNil(key(122))
        XCTAssertFalse(controller.state.isCleared)
        controller.state.perform(.setMode(.live))
        XCTAssertNil(key(122))
        XCTAssertTrue(controller.state.isCleared)
        controller.state.perform(.nextSlide)
        XCTAssertNil(key(99))
        XCTAssertTrue(controller.state.isCleared)
        XCTAssertNotNil(key(120))
    }

    func testSampleOutputsAreLocalizedAndTheWideLiveViewLaysOut() {
        XCTAssertEqual(LiveOutput.samples.map(\.kind), [.audience, .audience, .stage, .key])
        XCTAssertEqual(LiveOutput.samples.map { Strings.text($0.name, language: "es") }, ["Centro", "Laterales", "Escenario", "Key"])
        XCTAssertEqual(Strings.text("Cleared", language: "es"), "Borrado")
        XCTAssertEqual(Strings.text("Available when backgrounds exist", language: "es"), "Disponible cuando haya fondos")
        let view = NSHostingView(rootView: LiveView(state: AppState(), appearance: .standard))
        view.frame = NSRect(x: 0, y: 0, width: 3200, height: 1340)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }
}
