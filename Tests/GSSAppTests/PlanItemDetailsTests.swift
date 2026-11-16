import GSSCore
import GSSLibrary
import XCTest
@testable import GSSApp

/// The sequence and team notes of a plan item, and the recent services (issue #100); every text here is invented.
final class PlanItemDetailsTests: XCTestCase {
    private var dawn: Song {
        var song = Song(title: "Dawn Invented", language: "en", sections: [
            SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Dawn one"])]),
            SongSection(id: "c", kind: .chorus, lines: [SongLine(text: ["en": "Dawn chorus"])])])
        song.arrangements = [SongArrangement(id: "short", name: "Short", sequence: ["c"])]
        return song
    }

    private func temporaryFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PlanItemDetailsTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// A header and Dawn, with Dawn prepared.
    private func service(_ song: Song) -> AppState {
        let state = AppState()
        let items = [PlanItem(id: "hi", kind: .header, title: "Welcome"), PlanItem(id: "dawn", kind: .song, song: song.id)]
        state.perform(.openPlan(Plan(title: "Invented", items: items), songs: [song]))
        state.perform(.loadSong(song))
        return state
    }

    private func lines(_ state: AppState, item: Int) -> [[String]] {
        state.program.slides.filter { $0.item == item }.map(\.slide.lines)
    }

    private func apply(_ edit: PlanEditing.SequenceEdit, to state: AppState, song: Song) {
        let item = PlanEditing.edited(state.program.plan.items[1], song: song, edit)
        state.perform(.updatePlanItem(at: 1, item))
    }

    func testSequenceEditsChangeOnlyThePlanAndTheSlidesFollow() throws {
        let song = dawn
        let url = try Library.open(temporaryFolder()).save(song)
        let bytes = try Data(contentsOf: url)
        let state = service(song)
        XCTAssertEqual(PlanEditing.sequence(of: state.program.plan.items[1], song: song), ["v1", "c"], "without a sequence, the song order")
        apply(.add("c"), to: state, song: song)
        XCTAssertEqual(state.program.plan.items[1].sequence, ["v1", "c", "c"])
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        apply(.move(from: 2, to: 0), to: state, song: song)
        XCTAssertEqual(state.program.plan.items[1].sequence, ["c", "v1", "c"])
        XCTAssertEqual(lines(state, item: 1), [["Dawn chorus"], ["Dawn one"], ["Dawn chorus"]])
        apply(.remove(1), to: state, song: song)
        XCTAssertEqual(lines(state, item: 1), [["Dawn chorus"], ["Dawn chorus"]])
        apply(.move(from: 0, to: 5), to: state, song: song)
        apply(.add("missing"), to: state, song: song)
        apply(.remove(7), to: state, song: song)
        XCTAssertEqual(state.program.plan.items[1].sequence, ["c", "c"], "invalid edits are ignored")
        apply(.remove(0), to: state, song: song)
        apply(.remove(0), to: state, song: song)
        XCTAssertEqual(state.program.plan.items[1].sequence, ["c"], "the last part is never removed")
        apply(.useSongOrder, to: state, song: song)
        XCTAssertNil(state.program.plan.items[1].sequence)
        XCTAssertEqual(lines(state, item: 1), [["Dawn one"], ["Dawn chorus"]])
        XCTAssertEqual(state.song, song)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testTheSongOrderOfAnItemFollowsItsArrangement() {
        var item = PlanItem(id: "dawn", kind: .song, song: dawn.id)
        item.arrangement = "short"
        XCTAssertEqual(PlanEditing.sequence(of: item, song: dawn), ["c"])
        let edited = PlanEditing.edited(item, song: dawn, .add("v1"))
        XCTAssertEqual(edited.sequence, ["c", "v1"])
        XCTAssertEqual(edited.arrangement, "short", "the arrangement stays chosen")
    }

    func testNoteEditsOnAnyItemKind() {
        let state = service(dawn)
        var item = PlanEditing.edited(state.program.plan.items[0], .add)
        state.perform(.updatePlanItem(at: 0, item))
        XCTAssertEqual(state.program.plan.items[0].notes, [PlanNote(category: "Vocals", text: "")])
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        item = PlanEditing.edited(item, .set(0, PlanNote(category: "Invented Team", text: "Invented note")))
        item = PlanEditing.edited(item, .add)
        item = PlanEditing.edited(item, .remove(9))
        item = PlanEditing.edited(item, .set(9, PlanNote(category: "Ignored", text: "Ignored")))
        state.perform(.updatePlanItem(at: 0, item))
        XCTAssertEqual(state.program.plan.items[0].notes, [PlanNote(category: "Invented Team", text: "Invented note"), PlanNote(category: "Vocals", text: "")])
        item = PlanEditing.edited(PlanEditing.edited(item, .remove(0)), .remove(0))
        state.perform(.updatePlanItem(at: 0, item))
        XCTAssertNil(state.program.plan.items[0].notes, "no notes are left in the file")
    }

    func testTeamCategoriesAreSavedInEnglishAndShownInTheInterfaceLanguage() {
        XCTAssertEqual(PlanEditing.teams, ["Vocals", "Band", "Media", "Lighting"])
        XCTAssertEqual(PlanEditing.categoryText("Lighting", language: "es"), "Luces")
        XCTAssertEqual(PlanEditing.categoryText("Invented Team", language: "es"), "Invented Team")
        XCTAssertEqual(PlanEditing.category(typed: "Voces", language: "es"), "Vocals")
        XCTAssertEqual(PlanEditing.category(typed: "Invented Team", language: "es"), "Invented Team")
    }

    func testRecentServicesAreTheFiveNewestDatedServices() throws {
        let library = try Library.open(temporaryFolder())
        var urls: [URL] = []
        for day in 1...7 {
            let url = try library.save(Plan(title: "Invented \(day)", date: "2026-10-0\(day)", items: []))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(day) * 1000)], ofItemAtPath: url.path)
            urls.append(url)
        }
        // The oldest day, changed last, comes first.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 9000)], ofItemAtPath: urls[0].path)
        let template = try library.save(Plan(title: "Invented Template", items: []))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10000)], ofItemAtPath: template.path)
        let recent = ServiceFile.recent(try library.plans()).map(\.url.lastPathComponent)
        let expected = [urls[0], urls[6], urls[5], urls[4], urls[3]].map(\.lastPathComponent)
        XCTAssertEqual(recent, expected)
    }
}
