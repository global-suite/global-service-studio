import GSSCore
import GSSLibrary
import XCTest
@testable import GSSApp

/// New, open and save services (issue #89); every text here is invented.
final class ServiceFileTests: XCTestCase {
    private let hymn = Song(title: "Invented Hymn", language: "en", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Invented line"])])])
    /// A state whose library is a new temporary folder.
    private func stateWithLibrary() throws -> (AppState, Library) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ServiceFileTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let state = AppState()
        state.perform(.chooseLibraryFolder(folder))
        return (state, try Library.open(folder))
    }
    private func saved(_ plan: Plan, in library: Library, modified: Date) throws -> URL {
        let url = try library.save(plan)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }
    func testNewServiceIsEmptyDatedTodayAndSaved() throws {
        let (state, library) = try stateWithLibrary()
        state.perform(.newService)
        XCTAssertEqual(state.program.plan.title, Strings.text("Service"))
        XCTAssertEqual(state.program.plan.date, ServiceDate.string(from: Date()))
        XCTAssertEqual(state.program.plan.items, [])
        XCTAssertFalse(state.hasUnsavedServiceChanges)
        XCTAssertNil(state.serviceFile)
        XCTAssertEqual(try library.plans().plans.count, 0, "a new service is not saved until the user saves")
    }

    func testSaveThenOpenRoundTripsAndTracksUnsavedChanges() throws {
        let (state, library) = try stateWithLibrary()
        let songURL = try library.save(hymn)
        state.perform(.newService)
        state.perform(.addToService(songURL, position: .end))
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        state.perform(.saveService)
        XCTAssertFalse(state.hasUnsavedServiceChanges)
        let file = try XCTUnwrap(state.serviceFile)
        state.perform(.setServiceInfo(title: "Invented Evening", date: "2026-12-24"))
        XCTAssertTrue(state.hasUnsavedServiceChanges)
        state.perform(.setServiceInfo(title: "Ignored", date: "2026-13-40"))
        XCTAssertEqual(state.program.plan.title, "Invented Evening", "an invalid date is ignored")
        state.perform(.saveService)
        let plan = state.program.plan
        state.perform(.newService)
        state.perform(.openService(file))
        XCTAssertEqual(state.program.plan, plan)
        XCTAssertEqual(state.program.plan.date, "2026-12-24")
        XCTAssertEqual(state.program.slides.map(\.slide.lines), [["Invented line"]])
        XCTAssertEqual(state.serviceFile, file)
        XCTAssertFalse(state.hasUnsavedServiceChanges)
        XCTAssertEqual(try library.plans().plans.count, 1)
    }

    func testNewServiceFromTemplateCopiesItemsIntoANewDatedPlan() throws {
        let (state, library) = try stateWithLibrary()
        let template = Plan(title: "Invented Template", items: [PlanItem(id: "welcome", kind: .item, title: "Welcome")])
        let url = try library.save(template)
        let bytes = try Data(contentsOf: url)
        state.perform(.newServiceFromTemplate(url))
        let plan = state.program.plan
        XCTAssertNotEqual(plan.id, template.id)
        XCTAssertEqual(plan.date, ServiceDate.string(from: Date()))
        XCTAssertEqual(plan.items, template.items)
        XCTAssertEqual(plan.title, "Invented Template")
        XCTAssertTrue(state.hasUnsavedServiceChanges, "a service from a template is new work")
        state.perform(.saveService)
        XCTAssertFalse(state.hasUnsavedServiceChanges)
        XCTAssertEqual(try Data(contentsOf: url), bytes, "the template is unchanged on disk")
        XCTAssertEqual(try library.plans().services.map(\.plan.id), [plan.id])
    }

    func testOpeningAServiceWithAMissingSongReportsTheItemAndStillOpens() throws {
        let (state, library) = try stateWithLibrary()
        try library.save(hymn)
        let plan = Plan(title: "Invented", date: "2026-11-15", items: [PlanItem(id: "a", kind: .song, title: "Lost Song", song: UUID()),
                                                                       PlanItem(id: "b", kind: .song, song: hymn.id)])
        state.perform(.openService(try library.save(plan)))
        XCTAssertEqual(state.program.plan, plan)
        XCTAssertEqual(state.program.slides.map(\.item), [1])
        XCTAssertEqual(state.alert?.title, Strings.text("Some items of the service could not be found."))
        XCTAssertEqual(state.alert?.message, String(format: Strings.text("“%@” is not in the library."), "Lost Song"))
        state.perform(.openService(library.plansFolder.appendingPathComponent("missing.plan.json")))
        XCTAssertEqual(state.alert?.title, Strings.text("The service could not be opened."))
        XCTAssertEqual(state.program.plan, plan)
    }

    func testLaunchOpensTheLatestChangedServiceIgnoringTemplates() throws {
        let (state, library) = try stateWithLibrary()
        let old = Plan(title: "Old Invented", date: "2027-01-01", items: []), latest = Plan(title: "Latest Invented", date: "2026-01-01", items: [])
        _ = try saved(old, in: library, modified: Date(timeIntervalSince1970: 1_000))
        _ = try saved(latest, in: library, modified: Date(timeIntervalSince1970: 2_000))
        _ = try saved(Plan(title: "Template", items: []), in: library, modified: Date(timeIntervalSince1970: 3_000))
        state.perform(.openLaunchService)
        XCTAssertEqual(state.program.plan, latest)
        let (empty, emptyLibrary) = try stateWithLibrary()
        empty.perform(.openLaunchService)
        XCTAssertEqual(empty.program.plan.date, ServiceDate.string(from: Date()))
        XCTAssertEqual(try emptyLibrary.plans().plans.count, 0)
    }

    func testQuestionsBeforeReplacingTheService() {
        XCTAssertEqual(ServiceFile.questions(unsaved: false, onAir: false, quitting: false), [])
        XCTAssertEqual(ServiceFile.questions(unsaved: true, onAir: false, quitting: false), [.saveChanges])
        XCTAssertEqual(ServiceFile.questions(unsaved: true, onAir: true, quitting: false), [.saveChanges, .endAir])
        XCTAssertEqual(ServiceFile.questions(unsaved: false, onAir: true, quitting: false), [.endAir])
        XCTAssertEqual(ServiceFile.questions(unsaved: false, onAir: true, quitting: true), [])
        XCTAssertEqual(ServiceFile.questions(unsaved: true, onAir: true, quitting: true), [.saveChanges])
        XCTAssertEqual(Strings.text("Unsaved", language: "es"), "Sin guardar")
        XCTAssertEqual(ServiceDate.string(from: ServiceDate.date(from: "2026-03-07")!), "2026-03-07")
    }
}
