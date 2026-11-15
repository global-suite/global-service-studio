import GSSCore
import GSSLibrary
import XCTest
@testable import GSSApp

/// Editing the service plan (issue #90); every text here is invented.
final class PlanEditingTests: XCTestCase {
    private var dawn: Song {
        var song = Song(title: "Dawn Invented", language: "en", sections: [
            SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Dawn one"]), SongLine(text: ["en": "Dawn two"]), SongLine(text: ["en": "Dawn three"])]),
            SongSection(id: "c", kind: .chorus, lines: [SongLine(text: ["en": "Dawn chorus"])])])
        song.arrangements = [SongArrangement(id: "short", name: "Short", sequence: ["c", "v1"])]
        return song
    }
    private let dusk = Song(title: "Dusk Invented", language: "en", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Dusk one"])])])

    /// Header, Dawn, Talk, Dusk, with the second slide of Dawn on air.
    private func onAir() -> AppState {
        let state = AppState(), song = dawn
        let items = [PlanItem(id: "hi", kind: .header, title: "Welcome"), PlanItem(id: "dawn", kind: .song, song: song.id),
                     PlanItem(id: "talk", kind: .item, title: "Talk"), PlanItem(id: "dusk", kind: .song, song: dusk.id)]
        state.perform(.openPlan(Plan(title: "Invented", items: items), songs: [song, dusk]))
        state.perform(.loadSong(song))
        state.perform(.nextSlide)
        state.perform(.nextSlide)
        return state
    }
    private func ids(_ state: AppState) -> [String] { state.program.plan.items.map(\.id) }

    func testMovingKeepsTheOnAirItemAndSlide() {
        let state = onAir()
        let lines = state.shownLines
        state.perform(.movePlanItem(from: 1, to: 3))
        XCTAssertEqual(ids(state), ["hi", "talk", "dusk", "dawn"])
        XCTAssertEqual(state.liveItem, 3)
        XCTAssertEqual(state.shownLines, lines)
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        state.perform(.movePlanItem(from: 2, to: 0))
        XCTAssertEqual(ids(state), ["dusk", "hi", "talk", "dawn"])
        XCTAssertEqual(state.liveItem, 3)
        state.perform(.movePlanItem(from: 3, to: 4))
        XCTAssertEqual(ids(state), ["dusk", "hi", "talk", "dawn"], "a move outside the plan is ignored")
        state.perform(.nextSlide)
        XCTAssertEqual(state.shownLines, ["Dawn chorus"])
    }

    func testRemovingIgnoresTheOnAirItemAndClearsTheSelection() {
        let state = onAir()
        state.perform(.selectPlanItem(1))
        state.perform(.removePlanItem(at: 1))
        XCTAssertEqual(ids(state), ["hi", "dawn", "talk", "dusk"])
        XCTAssertFalse(state.hasUnsavedServiceChanges)
        XCTAssertEqual(state.selectedPlanItem, 1)
        state.perform(.selectPlanItem(99))
        XCTAssertEqual(state.selectedPlanItem, 1, "an item outside the plan cannot be selected")
        state.perform(.selectPlanItem(2))
        state.perform(.removePlanItem(at: 2))
        XCTAssertNil(state.selectedPlanItem)
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        state.perform(.selectPlanItem(2))
        state.perform(.removePlanItem(at: 0))
        XCTAssertEqual(ids(state), ["dawn", "dusk"])
        XCTAssertEqual(state.selectedPlanItem, 1, "the selection stays on its item")
        XCTAssertEqual(state.liveItem, 0)
        XCTAssertEqual(state.shownLines, ["Dawn three"])
    }

    func testInsertingKeepsTheOnAirItemAndIgnoresInvalidItems() {
        let state = onAir()
        state.perform(.selectPlanItem(2))
        state.perform(.insertPlanItem(PlanItem(id: "new", kind: .header, title: "Invented Header"), at: 0))
        XCTAssertEqual(ids(state), ["new", "hi", "dawn", "talk", "dusk"])
        XCTAssertEqual(state.liveItem, 2)
        XCTAssertEqual(state.selectedPlanItem, 3)
        XCTAssertEqual(state.shownLines, ["Dawn three"])
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        state.perform(.insertPlanItem(PlanItem(id: "new", kind: .item), at: 5))
        state.perform(.insertPlanItem(PlanItem(id: "other", kind: .item), at: 6))
        XCTAssertEqual(ids(state).count, 5, "a duplicate id or a place outside the plan is ignored")
        for kind in [PlanItemKind.header, .item, .presentation, .media] {
            state.perform(.insertPlanItem(PlanEditing.newItem(kind), at: 5))
        }
        XCTAssertEqual(ids(state).count, 9, "every new item of the Add menu is valid")
    }

    func testSequenceAndArrangementChangeOnlyThePlan() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PlanEditingTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = try Library.open(folder).save(dawn)
        let bytes = try Data(contentsOf: url)
        let state = onAir(), song = state.song
        var item = state.program.plan.items[1]
        item.sequence = ["c"]
        state.perform(.updatePlanItem(at: 1, item))
        XCTAssertEqual(state.program.slides.filter { $0.item == 1 }.map(\.slide.lines), [["Dawn chorus"]])
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        (item.sequence, item.arrangement) = (nil, "short")
        state.perform(.updatePlanItem(at: 1, item))
        XCTAssertEqual(state.program.slides.filter { $0.item == 1 }.first?.slide.lines, ["Dawn chorus"])
        XCTAssertEqual(state.song, song)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testUpdatingTheOtherFieldsAndIgnoringInvalidItems() {
        let state = onAir()
        var item = state.program.plan.items[2]
        (item.title, item.length, item.position, item.key) = ("Invented Talk", 330, .during, "A")
        item.notes = [PlanNote(category: "Invented Team", text: "Invented note")]
        state.perform(.updatePlanItem(at: 2, item))
        XCTAssertEqual(state.program.plan.items[2], item)
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        item.length = -1
        state.perform(.updatePlanItem(at: 2, item))
        state.perform(.updatePlanItem(at: 9, item))
        XCTAssertEqual(state.program.plan.items[2].length, 330)
        XCTAssertEqual(PlanEditing.lengthText(330), "5:30")
        XCTAssertEqual([PlanEditing.seconds("3:05"), PlanEditing.seconds("4"), PlanEditing.seconds("1:75"), PlanEditing.seconds("x")], [185, 240, nil, nil])
    }
}
