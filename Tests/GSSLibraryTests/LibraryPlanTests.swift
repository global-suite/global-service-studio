import GSSCore
import GSSLibrary
import XCTest

final class LibraryPlanTests: XCTestCase {
    private let files = FileManager.default

    private func temporaryFolder() -> URL {
        let url = files.temporaryDirectory.appendingPathComponent("GSSLibraryPlanTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func plan(_ title: String, date: String? = nil, id: UUID = UUID(), items: [PlanItem] = []) -> Plan {
        Plan(id: id, title: title, date: date, items: items)
    }

    private func names(_ library: Library) throws -> [String] {
        try files.contentsOfDirectory(atPath: library.folder.appendingPathComponent("Plans").path).sorted()
    }

    func testSavingAPlanWritesASlugAndShortIDFileThatLoadsBackEqual() throws {
        let library = try Library.open(temporaryFolder())
        let id = try XCTUnwrap(UUID(uuidString: "D51B0C3E-1A2B-4C3D-8E4F-5A6B7C8D9E0F"))
        let saved = plan("Reunión del Domingo", date: "2026-11-15", id: id, items: [PlanItem(id: "h1", kind: .header, title: "Welcome")])
        let url = try library.save(saved)
        XCTAssertEqual(url, library.plansFolder.appendingPathComponent("reunion-del-domingo-d51b0c3e.plan.json"))
        XCTAssertEqual(try Data(contentsOf: url), try saved.encoded())
        XCTAssertEqual(try library.loadPlan(at: url), saved)
    }

    func testAPlanTitleWithoutLettersOrDigitsGetsThePlanSlug() throws {
        let library = try Library.open(temporaryFolder())
        let id = try XCTUnwrap(UUID(uuidString: "0A1B2C3D-1A2B-4C3D-8E4F-5A6B7C8D9E0F"))
        let url = try library.save(plan("¡¿?!", id: id))
        XCTAssertEqual(url.lastPathComponent, "plan-0a1b2c3d.plan.json")
    }

    func testSavingTheSameIDAfterATitleChangeOverwritesItsFileUnderItsName() throws {
        let library = try Library.open(temporaryFolder())
        var edited = plan("First Service")
        let url = try library.save(edited)
        edited.title = "Second Service"
        XCTAssertEqual(try library.save(edited), url)
        XCTAssertEqual(try names(library), [url.lastPathComponent])
        XCTAssertEqual(try library.loadPlan(at: url), edited)
    }

    func testSavingAPlanRenamedOutsideTheAppKeepsThatFile() throws {
        let library = try Library.open(temporaryFolder())
        var edited = plan("First Service")
        let renamed = library.plansFolder.appendingPathComponent("renamed-by-hand.plan.json")
        try files.moveItem(at: try library.save(edited), to: renamed)
        let other = try library.save(plan("Other Service"))
        edited.title = "Second Service"
        XCTAssertEqual(try library.save(edited), renamed)
        XCTAssertEqual(try names(library), [other.lastPathComponent, "renamed-by-hand.plan.json"].sorted())
    }

    func testAnInvalidPlanIsNotWritten() throws {
        let library = try Library.open(temporaryFolder())
        let items = [PlanItem(id: "a", kind: .header), PlanItem(id: "a", kind: .header)]
        XCTAssertThrowsError(try library.save(plan("Invalid", items: items))) { error in
            XCTAssertEqual(error as? FormatError, .validation(reason: "duplicateItemId", at: "items[1].id"))
        }
        XCTAssertEqual(try names(library), [])
    }

    func testLoadingAnInvalidFileThrowsItsError() throws {
        let library = try Library.open(temporaryFolder())
        let url = library.plansFolder.appendingPathComponent("broken.plan.json")
        try Data("{".utf8).write(to: url)
        XCTAssertThrowsError(try library.loadPlan(at: url)) { XCTAssertEqual($0 as? FormatError, .invalidJSON) }
    }

    func testListingReturnsValidPlansAndReportsInvalidFiles() throws {
        let library = try Library.open(temporaryFolder())
        let (a, b) = (plan("Alpha"), plan("Beta", date: "2026-11-15"))
        _ = try (library.save(b), library.save(a))
        try Data("{".utf8).write(to: library.plansFolder.appendingPathComponent("broken.plan.json"))
        try Data("Invented".utf8).write(to: library.plansFolder.appendingPathComponent("notes.txt"))
        let listing = try library.plans()
        XCTAssertEqual(listing.plans.map(\.plan), [a, b])
        XCTAssertEqual(listing.problems.map(\.url.lastPathComponent), ["broken.plan.json"])
        XCTAssertEqual(listing.problems.first?.error as? FormatError, .invalidJSON)
    }

    func testListingOrdersDatedServicesNewestFirstAndTemplatesByTitle() throws {
        let library = try Library.open(temporaryFolder())
        let plans = [plan("Older", date: "2026-11-08"), plan("zeta template"), plan("Newest", date: "2026-11-22"),
                     plan("Álamo template"), plan("Middle", date: "2026-11-15"), plan("beta template")]
        for plan in plans { try library.save(plan) }
        let listing = try library.plans()
        XCTAssertEqual(listing.services.map(\.plan.title), ["Newest", "Middle", "Older"])
        XCTAssertEqual(listing.templates.map(\.plan.title), ["Álamo template", "beta template", "zeta template"])
    }

    /// A plan with a header, a found song with its arrangement, a missing arrangement and a missing song.
    private func resolutionFixture(_ library: Library, index: LibraryIndex?) throws -> (Plan, Song, UUID) {
        var song = Song(title: "Invented Song", language: "en", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Invented line"])])])
        song.arrangements = [SongArrangement(id: "short", name: "Short", sequence: ["v1"])]
        if let index { try index.save(song) } else { try library.save(song) }
        let missing = UUID()
        var found = PlanItem(id: "s1", kind: .song, song: song.id)
        found.arrangement = "short"
        var noArrangement = PlanItem(id: "s2", kind: .song, song: song.id)
        noArrangement.arrangement = "long"
        let items = [PlanItem(id: "h1", kind: .header, title: "Welcome"), found, noArrangement, PlanItem(id: "s3", kind: .song, song: missing)]
        return (plan("Resolved", items: items), song, missing)
    }

    private func assertResolution(_ resolution: PlanResolution, song: Song, missing: UUID) {
        XCTAssertEqual(resolution.items.map(\.item.id), ["h1", "s1", "s2", "s3"])
        XCTAssertEqual(resolution.items.map(\.song?.song), [nil, song, song, nil])
        XCTAssertEqual(resolution.items.map(\.problem), [nil, nil, .missingArrangement("long"), .missingSong(missing)])
    }

    func testResolvingByScanningSongsReportsMissingSongsAndArrangementsPerItem() throws {
        let library = try Library.open(temporaryFolder())
        let (plan, song, missing) = try resolutionFixture(library, index: nil)
        assertResolution(try library.resolve(plan), song: song, missing: missing)
    }

    func testResolvingWithTheIndexFindsIndexedSongsAndFallsBackToTheFiles() throws {
        let library = try Library.open(temporaryFolder())
        let index = try LibraryIndex(library: library, at: temporaryFolder().appendingPathComponent("index.sqlite"))
        let (plan, song, missing) = try resolutionFixture(library, index: index)
        assertResolution(try library.resolve(plan, index: index), song: song, missing: missing)
        let unindexed = Song(title: "Saved Without Index", language: "en", sections: song.sections)
        try library.save(unindexed)
        let resolved = try library.resolve(Plan(title: "Fallback", items: [PlanItem(id: "s1", kind: .song, song: unindexed.id)]), index: index)
        XCTAssertEqual(resolved.items.map(\.song?.song), [unindexed])
    }
}
