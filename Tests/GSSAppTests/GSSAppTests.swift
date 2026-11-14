import AppKit
import Combine
import GSSCore
import GSSLibrary
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
        let verse = { String(format: Strings.text("%1$@ %2$ld"), Strings.text("Verse"), $0) }, (c, b) = (Strings.text("Chorus"), Strings.text("Bridge"))
        XCTAssertEqual(slides.map(\.section), [verse(1), verse(1), c, c, verse(2), verse(2), c, c, b, c, c])
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

    func testPartsFollowTheSungOrderAndMarkRepeats() {
        let state = AppState()
        XCTAssertEqual(state.parts.map(\.section.id), ["v1", "c", "v2", "c", "b", "c"])
        XCTAssertEqual(state.parts.map(\.isRepeat), [false, false, false, true, false, true])
        XCTAssertEqual(state.parts.map(\.slideRange), [0..<2, 2..<4, 4..<6, 6..<8, 8..<9, 9..<11])
        XCTAssertEqual(state.parts.flatMap(\.slides), state.slides)
    }

    func testSelectPartChangesTheSelectionAndIgnoresPartsOutsideTheSong() {
        let state = AppState()
        XCTAssertEqual([state.selectedPart, state.livePart], [0, 0])
        state.perform(.selectPart(3))
        state.perform(.selectPart(6))
        state.perform(.selectPart(-1))
        XCTAssertEqual(state.selectedPart, 3)
        state.perform(.goToSlide(9))
        XCTAssertEqual([state.selectedPart, state.livePart, state.part(containing: 4)], [3, 5, 2])
    }

    func testSetLinesReplacesTheWordsAndRebuildsTheSlides() {
        let state = AppState()
        state.perform(.setLines(sectionID: "c", lines: ["  Placeholder one ", "", "Placeholder two", "   "]))
        XCTAssertEqual(state.song.sections[1].lines.map { $0.text["en"] }, ["Placeholder one", "Placeholder two"])
        XCTAssertEqual(state.song.sections[1].kind, .chorus)
        XCTAssertEqual(state.slides.count, 8)
        XCTAssertEqual(state.slides[2].lines, ["Placeholder one", "Placeholder two"])
        XCTAssertEqual(state.parts.map(\.slides.count), [2, 1, 2, 1, 1, 1])
        state.perform(.setLines(sectionID: "c", lines: ["A", "B", "C"]))
        XCTAssertEqual(state.slides.count, 11)
    }

    func testSetLinesIgnoresWordsThatWouldLeaveThePartEmpty() {
        let state = AppState()
        let song = state.song
        state.perform(.setLines(sectionID: "b", lines: [" ", "\t", ""]))
        state.perform(.setLines(sectionID: "missing", lines: ["Placeholder"]))
        XCTAssertEqual(state.song, song)
        XCTAssertEqual(state.slides.count, 11)
    }

    func testSetLinesKeepsTheLiveSlideInsideAShorterSong() {
        let state = AppState()
        state.perform(.goToSlide(10))
        state.perform(.setLines(sectionID: "c", lines: ["Placeholder one", "Placeholder two"]))
        XCTAssertEqual(state.liveIndex, 7)
        XCTAssertEqual(state.liveSlide.lines, ["Placeholder one", "Placeholder two"])
    }

    func testSlideCountsUseThePluralOfEachLanguage() {
        XCTAssertEqual([1, 2].map { Strings.slideCount($0, language: "en") }, ["1 slide", "2 slides"])
        XCTAssertEqual([1, 2].map { Strings.slideCount($0, language: "es") }, ["1 diapositiva", "2 diapositivas"])
        XCTAssertEqual([Strings.text("Editing", language: "es"), Strings.text("Whole song", language: "es")], ["Editando", "Toda la canción"])
        let view = NSHostingView(rootView: PrepareView(state: AppState(), appearance: .standard))
        view.frame = NSRect(x: 0, y: 0, width: 1180, height: 830)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }

    func testDefaultOutputScreenIsADisplayOtherThanTheOperators() {
        let (a, b, c) = (ScreenInfo(id: 1, name: "A"), ScreenInfo(id: 2, name: "B"), ScreenInfo(id: 3, name: "C"))
        XCTAssertEqual(defaultOutputScreen(screens: [a, b], operatorScreenID: 1), b)
        XCTAssertEqual(defaultOutputScreen(screens: [a, b], operatorScreenID: 2), a)
        XCTAssertNil(defaultOutputScreen(screens: [a], operatorScreenID: 1))
        XCTAssertNil(defaultOutputScreen(screens: [], operatorScreenID: nil))
        XCTAssertEqual(defaultOutputScreen(screens: [a, b, c], operatorScreenID: 1), b)
        XCTAssertEqual(defaultOutputScreen(screens: [a, b, c], operatorScreenID: 2), a)
        XCTAssertEqual(defaultOutputScreen(screens: [a, b, c], operatorScreenID: nil), b)
    }

    func testOutputCommandsShowTheAudienceOutputOnlyWithAChosenDisplay() {
        let state = AppState()
        var published: [Bool] = []
        let subscription = state.$isAudienceOutputShown.dropFirst().sink { published.append($0) }
        XCTAssertNil(state.outputScreen)
        state.perform(.showAudienceOutput(true))
        XCTAssertFalse(state.isAudienceOutputShown)
        state.perform(.selectOutputScreen(7))
        state.perform(.showAudienceOutput(true))
        state.perform(.showAudienceOutput(true))
        XCTAssertEqual(state.outputScreen, 7)
        state.perform(.selectOutputScreen(8))
        XCTAssertTrue(state.isAudienceOutputShown)
        state.perform(.showAudienceOutput(false))
        state.perform(.showAudienceOutput(true))
        state.perform(.selectOutputScreen(nil))
        XCTAssertNil(state.outputScreen)
        XCTAssertEqual(published, [true, false, true, false])
        subscription.cancel()
    }

    func testAudienceOutputShowsTheLiveLinesAndNothingWhenCleared() {
        let state = AppState()
        XCTAssertEqual(AudienceOutputView.lines(state), ["Morning light is rising", "Over all the earth"])
        state.perform(.clearSlide)
        XCTAssertEqual(AudienceOutputView.lines(state), [])
        state.perform(.goToSlide(10))
        state.perform(.nextSlide)
        XCTAssertEqual(AudienceOutputView.lines(state), state.slides[10].lines, "at the end of the song the last slide stays")
        state.perform(.clearAll)
        XCTAssertEqual(AudienceOutputView.lines(state), [])
        let view = NSHostingView(rootView: AudienceOutputView(state: state))
        view.frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }

    func testOutputMenuListsDisplaysAndNeedsASecondOne() throws {
        var screens = [ScreenInfo(id: 900_001, name: "Built-in")]
        let state = AppState(), controller = AudienceOutputController(state: state, operatorWindow: nil) { screens }
        let menu = controller.menu
        func toggle() throws -> NSMenuItem { try XCTUnwrap(menu.items.last) }
        XCTAssertEqual(try toggle().keyEquivalent, "o")
        XCTAssertEqual(try toggle().keyEquivalentModifierMask, [.command, .shift])
        XCTAssertFalse(controller.validateMenuItem(try toggle()))
        XCTAssertTrue(menu.items.contains { $0.title == Strings.text("Connect a second display to show the audience output.") })
        XCTAssertEqual(Strings.text("Output", language: "es"), "Salida")
        screens.append(ScreenInfo(id: 900_002, name: "Projector"))
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.prefix(2).map(\.title), ["Built-in", "Projector"])
        XCTAssertTrue(controller.validateMenuItem(try toggle()))
        XCTAssertEqual(try toggle().title, Strings.text("Show Audience Output"))
        controller.toggleOutput(nil)
        XCTAssertEqual([state.outputScreen, state.isAudienceOutputShown ? 1 : 0], [900_002, 1])
        XCTAssertNil(controller.window, "no window opens for a display that is not connected")
        XCTAssertTrue(controller.validateMenuItem(try toggle()))
        XCTAssertEqual(try toggle().title, Strings.text("Hide Audience Output"))
        controller.selectScreen(menu.items[0])
        XCTAssertEqual(menu.items.prefix(2).map(controller.validateMenuItem), [true, true])
        XCTAssertEqual(menu.items.prefix(2).map(\.state), [.on, .off])
        XCTAssertEqual(state.outputScreen, 900_001)
        screens.removeFirst()
        controller.screensChanged()
        XCTAssertNil(state.outputScreen)
        XCTAssertFalse(state.isAudienceOutputShown)
    }

    func testLoadSongReplacesTheSongAndStartsAtTheFirstSlide() throws {
        let state = AppState()
        state.perform(.goToSlide(9))
        state.perform(.selectPart(4))
        state.perform(.clearSlide)
        let song = try PlainTextSongImporter.song(from: "First words\nSecond words\nThird words\n\nChorus\nRefrain words\n\nChorus", fallbackTitle: "Placeholder")
        state.perform(.loadSong(song))
        XCTAssertEqual(state.song, song)
        XCTAssertEqual(state.parts.map(\.section.id), ["v1", "c1", "c1"])
        XCTAssertEqual(state.slides.map(\.lines), [["First words", "Second words"], ["Third words"], ["Refrain words"], ["Refrain words"]])
        XCTAssertEqual([state.liveIndex, state.selectedPart], [0, 0])
        XCTAssertFalse(state.isCleared)
        state.perform(.loadSong(Song(title: "Empty", language: "en", sections: [])))
        XCTAssertEqual(state.song, song, "a song without slides is ignored")
    }

    func testSectionsWithoutALabelGetALocalizedName() {
        let verse = SongSection(id: "v3", kind: .verse, number: 3, lines: []), chorus = SongSection(id: "c1", kind: .chorus, lines: [])
        XCTAssertEqual([verse, chorus].map { Strings.sectionName($0, language: "en") }, ["Verse 3", "Chorus"])
        XCTAssertEqual([verse, chorus].map { Strings.sectionName($0, language: "es") }, ["Verso 3", "Coro"])
        XCTAssertEqual(Strings.sectionName(SongSection(id: "x", kind: SongSectionKind(rawValue: "rap"), label: "Rap", lines: []), language: "es"), "Rap")
    }

    func testRecognizedKindsIgnoreTheCaseWrittenInTheFile() {
        let verse = SongSection(id: "v1", kind: .verse, number: 1, label: "VERSO 1", lines: [])
        let chorus = SongSection(id: "c1", kind: .chorus, label: "coro", lines: []), bridge = SongSection(id: "b1", kind: .bridge, label: "PUENTE", lines: [])
        XCTAssertEqual([verse, chorus, bridge].map { Strings.sectionName($0, language: "en") }, ["Verse 1", "Chorus", "Bridge"])
        XCTAssertEqual([verse, chorus, bridge].map { Strings.sectionName($0, language: "es") }, ["Verso 1", "Coro", "Puente"])
        XCTAssertEqual(Strings.sectionName(SongSection(id: "x", kind: SongSectionKind(rawValue: "rap"), label: "RAP Break", lines: []), language: "en"), "RAP Break")
        XCTAssertEqual(Strings.sectionName(SongSection(id: "x", kind: SongSectionKind(rawValue: "rap"), lines: []), language: "en"), "rap")
    }

    func testOpenSongReadsPlainTextFilesAndExplainsFailures() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let utf16 = folder.appendingPathComponent("Placeholder Hymn.txt"), empty = folder.appendingPathComponent("Empty.txt")
        try "Coro\nPalabras de ejemplo".write(to: utf16, atomically: true, encoding: .utf16)
        try "\n\n".write(to: empty, atomically: true, encoding: .utf8)
        let song = try SongFile.read(utf16)
        XCTAssertEqual([song.title, song.sections[0].lines[0].text["en"]], ["Placeholder Hymn", "Palabras de ejemplo"])
        XCTAssertThrowsError(try SongFile.read(empty)) { XCTAssertEqual(SongFile.message(for: $0), Strings.text("This file has no lyrics.")) }
        XCTAssertThrowsError(try SongFile.read(folder.appendingPathComponent("Missing.txt"))) { XCTAssertEqual(SongFile.message(for: $0), Strings.text("This file could not be read.")) }
        XCTAssertEqual(Strings.text("This file has no lyrics.", language: "es"), "Este archivo no tiene letra.")
        let file = try XCTUnwrap(MainMenu.make(output: NSMenu()).items.first { $0.title == Strings.text("File") }?.submenu?.items.first)
        XCTAssertEqual([file.title, file.keyEquivalent, Strings.text("File", language: "es"), Strings.text("Open Song…", language: "es")], [Strings.text("Open Song…"), "o", "Archivo", "Abrir canción…"])
        XCTAssertEqual(file.action, #selector(MainWindowController.openSong(_:)))
    }
    private func order(_ state: AppState) -> [String] { state.parts.map(\.section.id) }

    func testMoveArrangementItemReordersThePartsKeepsTheLiveSlideAndIgnoresInvalidMoves() {
        let state = AppState()
        state.perform(.setMode(.live))
        state.perform(.goToSlide(1))
        let live = state.liveSlide
        state.perform(.moveArrangementItem(from: 0, to: 2))
        XCTAssertEqual(order(state), ["c", "v2", "v1", "c", "b", "c"])
        XCTAssertEqual(state.song.arrangements?.first?.sequence, order(state))
        XCTAssertEqual([state.selectedPart, state.liveIndex], [2, 5])
        XCTAssertEqual(state.liveSlide, live)
        XCTAssertEqual(state.slides[0].lines, ["We lift our voice", "We lift our eyes"], "Live sees the new order")
        let song = state.song
        for (from, to) in [(1, 1), (-1, 0), (0, 6), (6, 0)] { state.perform(.moveArrangementItem(from: from, to: to)) }
        XCTAssertEqual(state.song, song)
    }

    func testInsertArrangementItemRepeatsASectionAndIgnoresInvalidOnes() {
        let state = AppState()
        state.perform(.goToSlide(9))
        state.perform(.insertArrangementItem(sectionID: "v1", at: 0))
        XCTAssertEqual(order(state), ["v1", "v1", "c", "v2", "c", "b", "c"])
        XCTAssertEqual(state.parts.map(\.isRepeat).prefix(2), [false, true])
        XCTAssertEqual([state.selectedPart, state.liveIndex, state.slides.count], [0, 11, 13])
        state.perform(.insertArrangementItem(sectionID: "b", at: 7))
        XCTAssertEqual(order(state).last, "b")
        XCTAssertEqual(state.selectedPart, 7)
        let song = state.song
        state.perform(.insertArrangementItem(sectionID: "missing", at: 0))
        state.perform(.insertArrangementItem(sectionID: "c", at: -1))
        state.perform(.insertArrangementItem(sectionID: "c", at: 9))
        XCTAssertEqual(state.song, song)
    }

    func testRemoveArrangementItemKeepsSectionsWithWordsAndNeverEmptiesTheOrder() throws {
        let state = AppState()
        state.perform(.goToSlide(10))
        state.perform(.removeArrangementItem(at: 4))
        XCTAssertEqual(order(state), ["v1", "c", "v2", "c", "c"])
        XCTAssertEqual(state.song.sections.map(\.id), ["v1", "c", "v2", "b"], "an unused section with words stays")
        XCTAssertEqual([state.liveIndex, state.selectedPart], [9, 4])
        state.perform(.removeArrangementItem(at: 4))
        XCTAssertEqual([state.liveIndex, state.selectedPart, state.slides.count], [7, 3, 8])
        state.perform(.removeArrangementItem(at: 4))
        state.perform(.removeArrangementItem(at: -1))
        XCTAssertEqual(state.parts.count, 4)
        let single = try PlainTextSongImporter.song(from: "Only words", fallbackTitle: "Placeholder")
        state.perform(.loadSong(single))
        state.perform(.removeArrangementItem(at: 0))
        XCTAssertEqual(state.song, single)
    }

    func testAddSectionCreatesUniqueValidSectionsAndRemovingAnUnusedEmptyOneDeletesIt() throws {
        let state = AppState()
        state.perform(.goToSlide(2))
        state.perform(.addSection(kind: .verse, at: 2))
        XCTAssertEqual(order(state), ["v1", "c", "v3", "v2", "c", "b", "c"])
        XCTAssertEqual([state.selectedPart, state.liveIndex], [2, 2])
        let verse = try XCTUnwrap(state.song.sections.last)
        XCTAssertEqual([verse.number, verse.lines.count], [3, 1])
        XCTAssertEqual(verse.lines[0].text["en"], Strings.text("New Verse"))
        for kind in [SongSectionKind.chorus, .bridge, .ending, .prechorus] { state.perform(.addSection(kind: kind, at: state.parts.count)) }
        XCTAssertEqual(state.song.sections.suffix(4).map(\.id), ["c2", "b2", "e1", "p1"])
        XCTAssertEqual(state.song.sections.suffix(4).map(\.number), [2, 2, nil, nil])
        XCTAssertNoThrow(try state.song.validate())
        let song = state.song
        state.perform(.addSection(kind: .verse, at: -1))
        state.perform(.addSection(kind: .verse, at: 12))
        XCTAssertEqual(state.song, song)
        state.perform(.setLines(sectionID: "c2", lines: ["Invented words"]))
        state.perform(.removeArrangementItem(at: 7))
        state.perform(.removeArrangementItem(at: 2))
        XCTAssertFalse(state.song.sections.contains { $0.id == "v3" }, "an unused section without words is removed")
        XCTAssertTrue(state.song.sections.contains { $0.id == "c2" })
        XCTAssertNoThrow(try state.song.validate())
        XCTAssertEqual([Strings.text("New Verse", language: "es"), Strings.text("Remove from Order", language: "es")], ["Nuevo verso", "Quitar del orden"])
    }

    func testEditingTheOrderOfASongWithoutArrangementsCreatesADefaultOne() throws {
        let state = AppState()
        var song = Song(title: "Placeholder", language: "en", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Invented line"])])])
        state.perform(.loadSong(song))
        state.perform(.insertArrangementItem(sectionID: "v1", at: 1))
        XCTAssertEqual(order(state), ["v1", "v1"])
        XCTAssertNoThrow(try state.song.validate())
        song.arrangements = [SongArrangement(id: "default", name: "Default", sequence: ["v1", "v1"])]
        song.defaultArrangement = "default"
        XCTAssertEqual(state.song, song)
    }

    func testRepetitionsAreRunsOfTheSameSectionInTheSungOrder() {
        let runs = SongPart.repetitions(of: ["v1", "c", "c", "c", "b", "b", "v1", "c", "v1"])
        XCTAssertEqual(runs.map { [$0.repetition, $0.count] }, [[1, 1], [1, 3], [2, 3], [3, 3], [1, 2], [2, 2], [1, 1], [1, 1], [1, 1]])
        XCTAssertTrue(SongPart.repetitions(of: []).isEmpty)
    }

    func testPartsAndTheirSlidesCarryTheRepetitionOfTheirRun() {
        let state = AppState()
        state.perform(.insertArrangementItem(sectionID: "c", at: 2))
        state.perform(.insertArrangementItem(sectionID: "c", at: 2))
        XCTAssertEqual(order(state), ["v1", "c", "c", "c", "v2", "c", "b", "c"])
        XCTAssertEqual(state.parts.map(\.repetition), [1, 1, 2, 3, 1, 1, 1, 1])
        XCTAssertEqual(state.parts.map(\.repetitionCount), [1, 3, 3, 3, 1, 1, 1, 1], "a chorus after a verse starts a new count")
        XCTAssertEqual(state.slides.map(\.repetition), state.parts.flatMap { part in part.slides.map { _ in part.repetition } })
        XCTAssertEqual([state.slides[4].repetition, state.slides[4].repetitionCount, state.slides[4].part], [2, 3, 1])
        XCTAssertEqual(state.slides[4].position(language: "en"), String(format: "%@ · repetition 2 of 3 · 1 of 2", Strings.text("Chorus")))
        XCTAssertEqual(state.parts.map { Strings.orderMark($0, language: "en") }, [nil, "×3", "2/3", "3/3", nil, "repeat", nil, "repeat"])
        XCTAssertEqual(state.slides.map(\.repetitionMark), [nil, nil, "1/3", "1/3", "2/3", "2/3", "3/3", "3/3"] + Array(repeating: nil, count: 7))
        let view = NSHostingView(rootView: LiveView(state: state, appearance: .standard))
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 850)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }

    func testRepetitionTextIsLocalizedAndOnlyShownForRepeatedParts() {
        let repeated = LiveSlide(section: "Coro", part: 1, partCount: 2, lines: [], repetition: 2, repetitionCount: 3)
        XCTAssertEqual(repeated.position(language: "es"), "Coro · repetición 2 de 3 · 1 de 2")
        XCTAssertEqual(repeated.heading(language: "es"), "Coro · repetición 2 de 3")
        XCTAssertEqual(LiveSlide(section: "Chorus", part: 2, partCount: 2, lines: [], repetition: 3, repetitionCount: 3).position(language: "en"), "Chorus · repetition 3 of 3 · 2 of 2")
        XCTAssertEqual(LiveSlide(section: "Chorus", part: 1, partCount: 1, lines: [], repetition: 1, repetitionCount: 2).heading(language: "en"), "Chorus · repetition 1 of 2")
        XCTAssertEqual(LiveSlide(section: "Coro", part: 1, partCount: 2, lines: []).position(language: "es"), "Coro · 1 de 2")
        XCTAssertEqual(["en", "es"].map { Strings.repetitionMark(2, of: 3, language: $0) }, ["2/3", "2/3"])
        XCTAssertNil(Strings.repetitionMark(1, of: 1))
        let state = AppState()
        XCTAssertTrue(state.slides.allSatisfy { $0.repetitionCount == 1 && $0.repetitionMark == nil && $0.heading() == $0.section })
        XCTAssertEqual(state.slides.map { $0.position(language: "en") }, state.slides.map { "\($0.section) · \($0.part) of \($0.partCount)" })
        XCTAssertEqual(state.parts.map { Strings.orderMark($0, language: "es") }, [nil, nil, nil, "repetición", nil, "repetición"])
        state.perform(.insertArrangementItem(sectionID: "b", at: 5))
        XCTAssertEqual(Strings.orderMark(state.parts[4], language: "es"), "×2")
    }

    func testPrepareKeysSelectAndRemovePartsOutsideTheEditor() throws {
        let controller = MainWindowController(state: AppState())
        let window = try XCTUnwrap(controller.window)
        func key(_ code: UInt16) -> NSEvent? {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)
            return controller.handleKey(try! XCTUnwrap(event))
        }
        XCTAssertNil(key(124))
        XCTAssertNil(key(124))
        XCTAssertNil(key(123))
        XCTAssertEqual(controller.state.selectedPart, 1)
        XCTAssertNil(key(51))
        XCTAssertEqual(controller.state.parts.map(\.section.id), ["v1", "v2", "c", "b", "c"])
        XCTAssertEqual(controller.state.liveIndex, 0)
    }

    private func settings() -> (AppSettings, UserDefaults) {
        let name = "GSSAppTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (AppSettings(defaults: defaults), defaults)
    }

    func testSettingsAreStoredAndUnknownValuesFallBackToDefaults() {
        let (settings, defaults) = settings()
        XCTAssertEqual(settings.language, .system)
        XCTAssertEqual(settings.repetitionMode, .separateSlides)
        settings.language = .es
        settings.repetitionMode = .oncePerRun
        XCTAssertEqual(AppSettings(defaults: defaults).language, .es)
        XCTAssertEqual(AppSettings(defaults: defaults).repetitionMode, .oncePerRun)
        defaults.set("fr", forKey: "language")
        defaults.set("twice", forKey: "repetitionMode")
        XCTAssertEqual(settings.language, .system)
        XCTAssertEqual(settings.repetitionMode, .separateSlides)
    }

    func testInterfaceLanguageFollowsTheSettingOrTheSystem() {
        XCTAssertEqual(Strings.language(for: .system, system: ["es-AR"]), "es")
        XCTAssertEqual(Strings.language(for: .system, system: ["fr-FR"]), "en")
        XCTAssertEqual(Strings.language(for: .en, system: ["es-AR"]), "en")
        XCTAssertEqual(Strings.language(for: .es, system: ["en-US"]), "es")
        XCTAssertEqual(InterfaceLanguage.allCases.map { Strings.languageName($0, language: "es") }, ["Sistema", "English", "Español"])
        XCTAssertEqual(InterfaceLanguage.allCases.map { Strings.languageName($0, language: "en") }, ["System", "English", "Español"])
        XCTAssertEqual(RepetitionMode.allCases.map { Strings.text($0.title, language: "es") },
                       ["Diapositivas separadas en cada repetición", "Mostrar las partes repetidas una sola vez"])
    }

    func testRepeatedPartsShownOnceCollapseEachRunIntoOnePass() {
        let (settings, _) = settings()
        let state = AppState(settings: settings)
        state.perform(.insertArrangementItem(sectionID: "c", at: 2))
        state.perform(.insertArrangementItem(sectionID: "c", at: 2))
        state.perform(.goToSlide(7))
        XCTAssertEqual(state.slides.count, 15)
        state.perform(.setRepetitionMode(.oncePerRun))
        XCTAssertEqual(settings.repetitionMode, .oncePerRun)
        XCTAssertEqual(state.repetitionMode, .oncePerRun)
        XCTAssertEqual(state.parts.count, 8, "the song order is unchanged")
        XCTAssertEqual(state.parts.map(\.slides.count), [2, 2, 0, 0, 2, 2, 1, 2])
        XCTAssertEqual(state.slides.count, 11)
        XCTAssertEqual(state.slides[2].position(language: "en"), String(format: "%@ ×3 · 1 of 2", Strings.text("Chorus")))
        XCTAssertTrue(state.slides.allSatisfy { $0.repetitionCount == 1 })
        XCTAssertEqual(state.liveIndex, 3, "the live slide stays on the second slide of the chorus")
        XCTAssertEqual(state.livePart, 1)
        state.perform(.goToSlide(5))
        state.perform(.setRepetitionMode(.separateSlides))
        XCTAssertEqual(state.slides.count, 15)
        XCTAssertEqual(state.liveIndex, 9, "the live slide stays on the second verse")
        XCTAssertEqual(String(format: Strings.text("%1$@ ×%2$ld", language: "es"), "Coro", 3), "Coro ×3")
        XCTAssertEqual(AppState().repetitionMode, .separateSlides)
    }

    private func libraryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GSSAppTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSaveSongCommandWritesTheCurrentSongToTheChosenLibrary() throws {
        let (settings, _) = settings(), folder = libraryFolder()
        XCTAssertEqual(settings.libraryFolder.path, NSHomeDirectory() + "/Documents/Global Service Studio Library")
        let state = AppState(settings: settings)
        state.perform(.chooseLibraryFolder(folder))
        XCTAssertEqual([state.libraryFolder, settings.libraryFolder].map(\.path), [folder.path, folder.path])
        state.perform(.saveSong)
        state.perform(.setLines(sectionID: "b", lines: ["Invented words"]))
        state.perform(.saveSong)
        XCTAssertEqual(try Library.open(folder).songs().songs.map(\.song), [state.song])
        XCTAssertNil(state.alert)
        let file = try XCTUnwrap(MainMenu.make(output: NSMenu()).items.first { $0.title == Strings.text("File") }?.submenu)
        XCTAssertEqual(file.items.map(\.keyEquivalent), ["o", "s", ""])
        XCTAssertEqual(file.items.map(\.action), [#selector(MainWindowController.openSong(_:)), #selector(MainWindowController.saveSong(_:)), #selector(MainWindowController.chooseLibraryFolder(_:))])
        XCTAssertEqual(["Save Song", "Choose Library Folder…"].map { Strings.text($0, language: "es") }, ["Guardar canción", "Elegir carpeta de biblioteca…"])
    }

    func testARefusedLibraryFolderIsReportedAndLeftUnchanged() throws {
        let state = AppState(), folder = libraryFolder(), previous = state.libraryFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("Invented notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        state.perform(.chooseLibraryFolder(folder))
        XCTAssertEqual(state.libraryFolder, previous)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["notes.txt"])
        XCTAssertEqual(state.alert, AppAlert(title: Strings.text("The library folder could not be opened."),
                                             message: Strings.text("This folder is not empty and is not a library. Choose an empty folder or an existing library.")))
        XCTAssertEqual(Strings.text("The song could not be saved.", language: "es"), "No se pudo guardar la canción.")
    }

    func testOpenMostRecentSongLoadsTheLatestSongOrKeepsTheSample() throws {
        let state = AppState(), folder = libraryFolder(), sample = state.song
        state.perform(.chooseLibraryFolder(folder.appendingPathComponent("Missing")))
        try FileManager.default.removeItem(at: folder)
        state.perform(.openMostRecentSong)
        XCTAssertEqual(state.song, sample)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "opening does not create the library")
        let song = try PlainTextSongImporter.song(from: "Invented words", fallbackTitle: "Placeholder")
        try Library.open(folder).save(song)
        state.perform(.chooseLibraryFolder(folder))
        state.perform(.openMostRecentSong)
        XCTAssertEqual(state.song, song)
    }

    func testKeyOutputCommandsShowItOnlyWithAChosenDisplay() {
        let state = AppState()
        XCTAssertNil(state.keyOutputScreen)
        state.perform(.showKeyOutput(true))
        XCTAssertFalse(state.isKeyOutputShown)
        state.perform(.selectKeyOutputScreen(8))
        state.perform(.showKeyOutput(true))
        XCTAssertEqual(state.keyOutputScreen, 8)
        XCTAssertTrue(state.isKeyOutputShown)
        XCTAssertFalse(state.isAudienceOutputShown, "the key output is independent of the audience output")
        state.perform(.selectKeyOutputScreen(nil))
        XCTAssertNil(state.keyOutputScreen)
        XCTAssertFalse(state.isKeyOutputShown)
    }

    func testADisplayHoldsOneOutputAndChoosingItMovesTheOtherOff() {
        let state = AppState()
        state.perform(.selectOutputScreen(7))
        state.perform(.showAudienceOutput(true))
        state.perform(.selectKeyOutputScreen(7))
        state.perform(.showKeyOutput(true))
        XCTAssertEqual(state.keyOutputScreen, 7)
        XCTAssertTrue(state.isKeyOutputShown)
        XCTAssertNil(state.outputScreen)
        XCTAssertFalse(state.isAudienceOutputShown)
        state.perform(.selectOutputScreen(7))
        XCTAssertEqual(state.outputScreen, 7)
        XCTAssertNil(state.keyOutputScreen)
        XCTAssertFalse(state.isKeyOutputShown)
        state.perform(.selectKeyOutputScreen(8))
        XCTAssertEqual([state.outputScreen, state.keyOutputScreen], [7, 8], "different displays leave each other alone")
    }

    func testKeyColorAcceptsOnlyHexColorsAndIsSaved() {
        let (settings, defaults) = settings()
        XCTAssertEqual(settings.keyColor, "#00B140")
        let state = AppState(settings: settings)
        XCTAssertEqual(state.keyColor, "#00B140")
        state.perform(.setKeyColor("#0047bb"))
        XCTAssertEqual(state.keyColor, "#0047BB")
        XCTAssertEqual(AppSettings(defaults: defaults).keyColor, "#0047BB")
        for invalid in ["green", "#12345", "0047BB", "#0047BG", "#0047BB00", ""] { state.perform(.setKeyColor(invalid)) }
        XCTAssertEqual(state.keyColor, "#0047BB")
        XCTAssertEqual(AppSettings(defaults: defaults).keyColor, "#0047BB")
        defaults.set("blue", forKey: "keyColor")
        XCTAssertEqual(settings.keyColor, "#00B140")
        XCTAssertEqual(KeyColor.green.hex, "#00B140")
        XCTAssertEqual(KeyColor.blue.hex, "#0047BB")
        XCTAssertEqual(KeyColor(hex: "#0047BB"), .blue)
        XCTAssertEqual(KeyColor(hex: "#102030")?.rgba, RGBA(hex: 0x102030))
        XCTAssertNil(KeyColor(hex: "#1020"))
    }

    func testKeyOutputShowsTheLiveLinesOverTheKeyColorOnly() {
        let state = AppState()
        XCTAssertEqual(KeyOutputView.lines(state), state.liveSlide.lines)
        state.perform(.clearSlide)
        XCTAssertEqual(KeyOutputView.lines(state), [])
        XCTAssertEqual(KeyOutputView.background(state), KeyColor.green.rgba)
        state.perform(.setKeyColor("#0047BB"))
        XCTAssertEqual(KeyOutputView.background(state), KeyColor.blue.rgba)
        XCTAssertEqual(AudienceOutputView.background, RGBA(hex: 0x000000))
        let view = NSHostingView(rootView: KeyOutputView(state: state))
        view.frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }

    func testKeyOutputMenuUsesItsOwnTitlesShortcutAndAvoidsTheAudienceDisplay() throws {
        let screens = [ScreenInfo(id: 900_001, name: "Built-in"), ScreenInfo(id: 900_002, name: "Projector"), ScreenInfo(id: 900_003, name: "Switcher")]
        let state = AppState(), controller = AudienceOutputController(state: state, role: .key, operatorWindow: nil) { screens }
        let toggle = try XCTUnwrap(controller.menu.items.last)
        XCTAssertEqual(controller.menu.title, Strings.text("Key Output"))
        XCTAssertEqual(toggle.keyEquivalent, "k")
        XCTAssertEqual(toggle.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertTrue(controller.validateMenuItem(toggle))
        XCTAssertEqual(toggle.title, Strings.text("Show Key Output"))
        state.perform(.selectOutputScreen(900_002))
        controller.toggleOutput(nil)
        XCTAssertEqual(state.keyOutputScreen, 900_003, "the default display is neither the operator's nor the audience's")
        XCTAssertTrue(state.isKeyOutputShown)
        XCTAssertEqual(state.outputScreen, 900_002)
        XCTAssertTrue(controller.validateMenuItem(toggle))
        XCTAssertEqual(toggle.title, Strings.text("Hide Key Output"))
        controller.selectScreen(controller.menu.items[1])
        XCTAssertEqual(state.keyOutputScreen, 900_002)
        XCTAssertNil(state.outputScreen)
        XCTAssertEqual(defaultOutputScreen(screens: screens, operatorScreenID: 900_001, avoiding: 900_002)?.id, 900_003)
        XCTAssertEqual(defaultOutputScreen(screens: Array(screens.prefix(2)), operatorScreenID: 900_001, avoiding: 900_002)?.id, 900_002)
    }

    func testOutputMenuHoldsTheAudienceAndKeySubmenus() {
        let audience = NSMenu(title: "A"), key = NSMenu(title: "K")
        let menu = OutputMenu.make(audience: audience, key: key)
        XCTAssertEqual(menu.title, Strings.text("Output"))
        XCTAssertEqual(menu.items.map(\.submenu), [audience, key])
        XCTAssertEqual(menu.items.map(\.title), ["A", "K"])
    }

    func testKeyOutputStringsAreTranslated() {
        for key in ["Key Output", "Show Key Output", "Hide Key Output", "Audience Output", "Key color", "Green", "Blue", "Custom",
                    "The Key output shows the lyrics over this color, for a video switcher to remove. It never shows backgrounds."] {
            XCTAssertNotEqual(Strings.text(key, language: "es"), key, key)
            XCTAssertEqual(Strings.text(key, language: "en"), key, key)
        }
    }

    /// A state whose library is `folder`, with its index in a temporary folder, once the index is loaded.
    private func libraryState(_ folder: URL) -> AppState {
        let indexes = libraryFolder()
        let state = AppState(indexURL: { indexes.appendingPathComponent("\($0.id.uuidString).sqlite") })
        state.perform(.chooseLibraryFolder(folder))
        waitForLibrary(state)
        return state
    }

    private func waitForLibrary(_ state: AppState) {
        let deadline = Date(timeIntervalSinceNow: 10)
        while state.isLibraryLoading, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        XCTAssertFalse(state.isLibraryLoading)
    }

    private func invented(_ title: String) throws -> Song {
        try PlainTextSongImporter.song(from: "Invented words of \(title)", fallbackTitle: title)
    }

    func testTheLibraryListIsSortedByTitleAndSearchFiltersIt() throws {
        let folder = libraryFolder(), library = try Library.open(folder)
        for title in ["Zeta Invented", "Canción del Alba", "Amanecer Nuevo", "Cantar Placeholder"] { try library.save(try invented(title)) }
        let state = libraryState(folder)
        XCTAssertEqual(state.librarySongs.map(\.title), ["Amanecer Nuevo", "Canción del Alba", "Cantar Placeholder", "Zeta Invented"])
        state.perform(.setLibrarySearch("cancion"))
        XCTAssertEqual(state.librarySearch, "cancion")
        XCTAssertEqual(state.librarySongs.map(\.title), ["Canción del Alba"])
        state.perform(.setLibrarySearch("CAN"))
        XCTAssertEqual(Set(state.librarySongs.map(\.title)), ["Canción del Alba", "Cantar Placeholder"])
        state.perform(.setLibrarySearch(" "))
        XCTAssertEqual(state.librarySongs.count, 4)
        XCTAssertEqual(Strings.songCount(4, language: "es"), "4 canciones")
        XCTAssertEqual(Strings.songCount(1, language: "en"), "1 song")
    }

    func testOpeningALibrarySongLoadsItAndMarksItOpen() throws {
        let folder = libraryFolder(), song = try invented("Alba Invented")
        try Library.open(folder).save(song)
        let state = libraryState(folder)
        XCTAssertNil(state.openSongFile, "the sample song is not in the library")
        let row = try XCTUnwrap(state.librarySongs.first)
        state.perform(.openLibrarySong(row.url))
        XCTAssertEqual(state.song, song)
        XCTAssertEqual(state.openSongFile, row.url)
        state.perform(.openLibrarySong(folder.appendingPathComponent("Songs/missing.song.json")))
        XCTAssertEqual(state.song, song)
        XCTAssertEqual(state.alert?.title, Strings.text("The song could not be opened."))
    }

    func testSavingASongAddsItToTheListAtOnce() throws {
        let folder = libraryFolder()
        try Library.open(folder).save(try invented("Zeta Invented"))
        let state = libraryState(folder)
        state.perform(.loadSong(try invented("Alba Invented")))
        state.perform(.saveSong)
        XCTAssertFalse(state.isLibraryLoading)
        XCTAssertEqual(state.librarySongs.map(\.title), ["Alba Invented", "Zeta Invented"])
        XCTAssertEqual(state.openSongFile, state.librarySongs.first?.url)
        XCTAssertNil(state.alert)
    }

    func testAnEmptyLibraryShowsAHintAndTheFirstSaveListsTheSong() throws {
        let folder = libraryFolder(), state = libraryState(folder)
        XCTAssertEqual(state.librarySongs, [])
        XCTAssertEqual(state.libraryProblems, [])
        XCTAssertEqual(Strings.text("Save a song with ⌘S or open a song file with ⌘O.", language: "es"), "Guarda una canción con ⌘S o abre un archivo de canción con ⌘O.")
        state.perform(.saveSong)
        waitForLibrary(state)
        XCTAssertEqual(state.librarySongs.map(\.id), [state.song.id])
    }

    func testInvalidFilesAndSharedIDsAreListedAsProblems() throws {
        let folder = libraryFolder(), library = try Library.open(folder)
        let url = try library.save(try invented("Alba Invented"))
        try FileManager.default.copyItem(at: url, to: library.songsFolder.appendingPathComponent("copy.song.json"))
        try Data("{".utf8).write(to: library.songsFolder.appendingPathComponent("broken.song.json"))
        let state = libraryState(folder)
        let invalid = LibraryProblem(file: "broken.song.json", reason: Strings.text("This file is not a valid song file."))
        let shared = Strings.text("Another file has the same song ID.")
        let expected = [invalid, LibraryProblem(file: url.lastPathComponent, reason: shared), LibraryProblem(file: "copy.song.json", reason: shared)]
        XCTAssertEqual(state.libraryProblems, expected)
        XCTAssertEqual(Strings.problemsTitle(3, language: "es"), "Problemas (3)")
        let copy = library.songsFolder.appendingPathComponent("copy.song.json")
        state.perform(.openLibrarySong(copy))
        XCTAssertEqual(state.openSongFile, copy, "the clicked file is selected, not the first file with its id")
    }

    func testSwitchingFoldersSavingAndSearchingWhileLoadingEndOnTheLastFolderWithoutAnAlert() throws {
        let first = libraryFolder(), second = libraryFolder(), indexes = libraryFolder(), queue = DispatchQueue(label: "GSSAppTests.held")
        try Library.open(first).save(try invented("First Invented"))
        try Library.open(second).save(try invented("Second Invented"))
        queue.suspend()
        let state = AppState(indexURL: { indexes.appendingPathComponent("\($0.id.uuidString).sqlite") }, indexQueue: queue)
        for folder in [first, second, first] { state.perform(.chooseLibraryFolder(folder)) }
        state.perform(.setLibrarySearch("first"))
        state.perform(.loadSong(try invented("Alba Invented")))
        state.perform(.saveSong)
        queue.resume()
        waitForLibrary(state)
        XCTAssertNil(state.alert)
        XCTAssertEqual(state.librarySongs.map(\.title), ["First Invented"])
        state.perform(.setLibrarySearch(""))
        XCTAssertEqual(state.librarySongs.map(\.title), ["Alba Invented", "First Invented"])
        state.perform(.chooseLibraryFolder(second))
        waitForLibrary(state)
        XCTAssertEqual(state.librarySongs.map(\.title), ["Second Invented"])
    }
}
