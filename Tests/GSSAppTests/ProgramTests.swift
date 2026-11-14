import GSSCore
import GSSLibrary
import SwiftUI
import XCTest
@testable import GSSApp

/// Live shows only the items of the plan (issue #82); every text here is invented.
final class ProgramTests: XCTestCase {
    private let dawn = ProgramTests.song("Dawn Invented", ["Dawn one", "Dawn two", "Dawn three"]), dusk = ProgramTests.song("Dusk Invented", ["Dusk one"])
    private let talk = PlanItem(id: "talk", kind: .item, title: "Talk")

    private static func song(_ title: String, _ lines: [String]) -> Song {
        Song(title: title, language: "en", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: lines.map { SongLine(text: ["en": $0]) }),
                                                      SongSection(id: "c", kind: .chorus, lines: [SongLine(text: ["en": "\(title) chorus"])])])
    }
    private func songItem(_ song: Song, _ sequence: [String]? = nil) -> PlanItem {
        var item = PlanItem(id: song.title, kind: .song, song: song.id)
        item.sequence = sequence
        return item
    }
    /// A header, Dawn with its own sequence, a plain item, a presentation without a file, then Dusk.
    private var plan: Plan {
        Plan(title: "Invented", items: [PlanItem(id: "hi", kind: .header, title: "Welcome"), songItem(dawn, ["c"]), talk,
                                        PlanItem(id: "deck", kind: .presentation, presentation: UUID()), songItem(dusk)])
    }
    /// A state running `items` with Dawn and Dusk, nothing on air, and Dawn prepared.
    private func running(_ items: [PlanItem]) -> AppState {
        let state = AppState()
        state.perform(.openPlan(Plan(title: "Invented", items: items), songs: [dawn, dusk]))
        state.perform(.loadSong(dawn))
        return state
    }
    private func savedDusk() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProgramTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return try Library.open(folder).save(dusk)
    }

    func testProgramIsBuiltFromThePlanItems() {
        let program = Program(plan: plan, songs: [dawn.id: dawn, dusk.id: dusk])
        XCTAssertEqual(program.slides.map(\.item), [1, 2, 4, 4])
        XCTAssertEqual(program.slides.map(\.slide.lines), [["Dawn Invented chorus"], [], ["Dusk one"], ["Dusk Invented chorus"]])
        XCTAssertEqual([program.range(of: 0), program.range(of: 4)], [0..<0, 2..<4])
        XCTAssertEqual(program.title(of: 4), "Dusk Invented")
        XCTAssertEqual(Program(plan: plan, songs: [dusk.id: dusk]).slides.map(\.item), [2, 4, 4], "a song item whose song is missing is skipped")
    }

    func testNextCrossesItemsStopsWithoutLyricsAndSkipsPlaceholders() {
        let state = running(plan.items)
        state.perform(.setBackground(.color("#102030")))
        XCTAssertEqual([state.programIndex, state.liveIndex], [-1, -1], "nothing is on air until Next")
        state.perform(.nextSlide)
        XCTAssertEqual(state.shownLines, ["Dawn Invented chorus"])
        XCTAssertEqual(state.nextItem, 2)
        state.perform(.nextSlide)
        XCTAssertEqual(state.liveItem, 2)
        XCTAssertEqual(state.shownLines, [], "a stop shows no lyrics")
        XCTAssertFalse(state.isCleared)
        XCTAssertEqual(state.background, .color("#102030"), "a stop keeps the background")
        state.perform(.nextSlide)
        XCTAssertEqual(state.liveItem, 4, "the presentation without a file is skipped")
        state.perform(.nextSlide)
        state.perform(.nextSlide)
        state.perform(.previousSlide)
        XCTAssertEqual(state.shownLines, ["Dusk one"])
    }

    func testPreviewingAnItemNeverChangesTheAirUntilASlideIsClicked() {
        let state = running(plan.items)
        state.perform(.nextSlide)
        state.perform(.previewItem(4))
        state.perform(.previewItem(0))
        state.perform(.previewItem(99))
        state.perform(.previewItem(-1))
        XCTAssertEqual(state.previewItem, 4, "a header and items outside the plan have no slides to preview")
        XCTAssertEqual(state.shownLines, ["Dawn Invented chorus"])
        state.perform(.previewItem(nil))
        XCTAssertNil(state.previewItem)
        state.perform(.previewItem(4))
        state.perform(.goToSlide(3))
        XCTAssertNil(state.previewItem)
        XCTAssertEqual(state.shownLines, ["Dusk Invented chorus"])
    }

    func testOpeningASongInPrepareNeverChangesTheAir() throws {
        let url = try savedDusk(), state = AppState()
        state.perform(.goToSlide(2))
        let shown = state.shownLines
        state.perform(.openLibrarySong(url))
        XCTAssertEqual(state.song, dusk)
        XCTAssertEqual(state.shownLines, shown)
        state.perform(.clearSlide)
        state.perform(.openLibrarySong(url))
        XCTAssertTrue(state.isCleared)
        XCTAssertEqual([state.programIndex, state.liveIndex], [2, -1])
        XCTAssertEqual(state.shownLines, [])
    }

    func testAddToServiceAddsAfterTheLiveItemOrAtTheEndWithoutGoingOnAir() throws {
        let url = try savedDusk(), state = running([songItem(dawn), talk])
        state.perform(.addToService(url, position: .next))
        XCTAssertEqual(state.program.plan.items.first?.title, "Dusk Invented", "with nothing on air, the next item is the first")
        XCTAssertEqual(state.programIndex, -1)
        XCTAssertEqual(state.shownLines, [])
        state.perform(.goToSlide(2))
        state.perform(.addToService(url, position: .end))
        state.perform(.addToService(url, position: .next))
        state.perform(.addToService(url.deletingLastPathComponent().appendingPathComponent("missing.song.json"), position: .end))
        XCTAssertEqual(state.program.plan.items.map { $0.title ?? "" }, ["Dusk Invented", "", "Dusk Invented", "Talk", "Dusk Invented"])
        XCTAssertEqual([state.programIndex, state.liveItem, state.nextItem], [2, 1, 2])
        XCTAssertEqual(state.shownLines, ["Dawn one", "Dawn two"])
        XCTAssertEqual(state.alert?.title, Strings.text("The song could not be opened."))
    }

    func testAnEmptyPlanShowsNothingOnAir() {
        let state = running([])
        state.perform(.nextSlide)
        XCTAssertFalse(state.isOnAir)
        XCTAssertEqual(state.shownLines, [])
        XCTAssertEqual(Strings.text("Add songs to the service from the Library.", language: "es"), "Agrega canciones al servicio desde la Biblioteca.")
        let view = NSHostingView(rootView: LiveView(state: state, appearance: .standard))
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 850)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }

    func testEditingThePreparedSongInThePlanKeepsTheLiveSlide() {
        let state = running([talk, songItem(dawn)])
        state.perform(.goToSlide(2))
        XCTAssertEqual(state.liveIndex, 1)
        state.perform(.moveArrangementItem(from: 1, to: 0))
        state.perform(.setLines(sectionID: "c", lines: ["Changed chorus"]))
        XCTAssertEqual(state.program.slides[1].slide.lines, ["Changed chorus"])
        XCTAssertEqual(state.programIndex, 3)
        XCTAssertEqual(state.shownLines, ["Dawn three"])
        state.perform(.goToSlide(0))
        state.perform(.setLines(sectionID: "c", lines: ["Changed again"]))
        XCTAssertEqual([state.programIndex, state.liveIndex], [0, -1])
    }

    func testReorderingKeepsTheLivePartWhenTheItemHasItsOwnSequence() {
        let state = running([songItem(dawn, ["v1", "c"])])
        state.perform(.goToSlide(2))
        state.perform(.moveArrangementItem(from: 1, to: 0))
        XCTAssertEqual(state.programIndex, 2)
        XCTAssertEqual(state.shownLines, ["Dawn Invented chorus"])
    }

    func testEditingAPlanSongBeforeTheLiveItemKeepsTheAir() {
        let state = running([songItem(dawn), talk])
        state.perform(.goToSlide(3))
        state.perform(.removeArrangementItem(at: 0))
        XCTAssertEqual([state.programIndex, state.liveItem], [1, 1])
        XCTAssertEqual(state.shownLines, [])
    }
}
