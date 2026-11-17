import GSSCore
import GSSLibrary
import XCTest
@testable import GSSApp

/// The run sheet, the service start time and the add-to-service shortcuts (issue #102); every text here is invented.
final class RunSheetTests: XCTestCase {
    private func item(_ id: String, _ kind: PlanItemKind, _ length: Double?) -> PlanItem {
        PlanItem(id: id, kind: kind, title: id, length: length)
    }
    /// Opening, 90 s (header); Song A, 300 s; Talk, no length; Closing (header); Prayer, 120 s.
    private func plan(start: String?) -> Plan {
        var plan = Plan(title: "Invented", items: [item("Opening", .header, nil), item("Song A", .item, 300), item("Talk", .item, nil),
                                                   item("Closing", .header, nil), item("Prayer", .item, 120)])
        plan.times = start.map { [PlanTime(name: "Morning", start: $0)] }
        return plan
    }
    private func sheet(_ plan: Plan) -> RunSheet { RunSheet(plan: plan) { plan.items[$0].title ?? "" } }

    func testStartsFollowTheFirstTimeAndTheLengthsBefore() {
        let sheet = sheet(plan(start: "10:05"))
        XCTAssertEqual(sheet.start, 36_300)
        XCTAssertEqual(sheet.rows.map(\.start), [36_300, 36_300, 36_600, 36_600, 36_600])
        XCTAssertEqual(sheet.rows.map(\.title), ["Opening", "Song A", "Talk", "Closing", "Prayer"])
        XCTAssertEqual(sheet.timeText(36_600, language: "es"), "10:10")
    }

    func testWithoutTimesStartsAreElapsedFromZero() {
        let sheet = sheet(plan(start: nil))
        XCTAssertNil(sheet.start)
        XCTAssertEqual(sheet.rows.map(\.start), [0, 0, 300, 300, 300])
        XCTAssertEqual(sheet.timeText(0), "0:00")
        XCTAssertEqual(sheet.timeText(300), "5:00")
    }

    func testHeadersCarryTheirSectionTotal() {
        let sheet = sheet(plan(start: nil))
        XCTAssertEqual(sheet.rows.map(\.sectionLength), [300, nil, nil, 120, nil])
    }

    func testTotalAndEndTime() {
        let timed = sheet(plan(start: "10:05")), untimed = sheet(plan(start: nil))
        XCTAssertEqual(timed.total, 420)
        XCTAssertEqual(timed.end, 36_720)
        XCTAssertEqual(timed.timeText(timed.end, language: "es"), "10:12")
        XCTAssertEqual(untimed.end, 420)
        XCTAssertEqual(untimed.timeText(untimed.end), "7:00")
    }

    func testItemsWithoutLengthCountAsZeroAndAreMarked() {
        let sheet = sheet(plan(start: nil))
        XCTAssertNil(sheet.rows[2].length)
        XCTAssertEqual(RunSheet.lengthText(sheet.rows[2].length), "—")
        XCTAssertEqual(RunSheet.lengthText(sheet.rows[1].length), "5:00")
        XCTAssertEqual(sheet.rows[3].start, sheet.rows[2].start)
    }

    func testStartTimeIsSavedAsTheFirstTimeAndValidated() {
        let state = AppState()
        state.perform(.openPlan(plan(start: nil), songs: []))
        state.perform(.setServiceInfo(title: "Invented", date: "2026-12-24", start: "09:30"))
        XCTAssertEqual(state.program.plan.times, [PlanTime(name: Strings.text("Service"), start: "09:30")])
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        state.perform(.setServiceInfo(title: "Invented", date: "2026-12-24", start: "25:00"))
        XCTAssertEqual(state.program.plan.times?.first?.start, "09:30", "an invalid start time is ignored")
        state.perform(.setServiceInfo(title: "Invented", date: "2026-12-24", start: ""))
        XCTAssertNil(state.program.plan.times, "an empty start time removes it")
        state.perform(.openPlan(plan(start: "18:00"), songs: []))
        state.perform(.setServiceInfo(title: "Invented", date: "2026-12-24", start: "19:15"))
        XCTAssertEqual(state.program.plan.times, [PlanTime(name: "Morning", start: "19:15")], "the first time keeps its name")
    }

    func testShortcutsAddTheOpenSongAfterTheSelectionOrAtTheEndWithoutGoingOnAir() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RunSheetTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let state = AppState()
        state.perform(.chooseLibraryFolder(folder))
        let song = Song(title: "Invented Song", language: "en", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Invented line"])])])
        let url = try Library.open(folder).save(song)
        state.perform(.openPlan(plan(start: nil), songs: []))
        state.perform(.openLibrarySong(url))
        state.perform(.selectPlanItem(1))
        state.addOpenSongToService(atEnd: false)
        let kinds = state.program.plan.items.map(\.kind)
        XCTAssertEqual(kinds, [.header, .item, .song, .item, .header, .item])
        XCTAssertEqual(state.selectedPlanItem, 1)
        state.addOpenSongToService(atEnd: true)
        XCTAssertEqual(state.program.plan.items.last?.kind, .song)
        XCTAssertEqual(state.program.plan.items.count, 7)
        state.perform(.selectPlanItem(nil))
        state.addOpenSongToService(atEnd: false)
        XCTAssertEqual(state.program.plan.items.count, 8)
        XCTAssertEqual(state.program.plan.items.last?.kind, .song, "with no item selected, the song goes at the end")
        XCTAssertFalse(state.isOnAir)
        XCTAssertTrue(state.hasUnsavedServiceChanges)
    }
}
