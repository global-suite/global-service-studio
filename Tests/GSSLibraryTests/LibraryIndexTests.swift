import GSSCore
import GSSLibrary
import SQLite3
import XCTest

final class LibraryIndexTests: XCTestCase {
    private let files = FileManager.default

    private func temporaryFolder() -> URL {
        let url = files.temporaryDirectory.appendingPathComponent("GSSLibraryIndexTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func song(_ title: String, lyrics: [String] = ["Invented line"], author: String? = nil, ccli: String? = nil) -> Song {
        var song = Song(title: title, language: "es", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: lyrics.map { SongLine(text: ["es": $0]) })])
        song.authors = author.map { [SongAuthor(name: $0)] }
        song.ccliNumber = ccli
        return song
    }

    /// A new library and its index, both in temporary folders that are removed after the test.
    private func makeIndex() throws -> (Library, LibraryIndex, URL) {
        let library = try Library.open(temporaryFolder())
        let url = temporaryFolder().appendingPathComponent("index.sqlite")
        return (library, try LibraryIndex(library: library, at: url), url)
    }

    private func titles(_ index: LibraryIndex, _ query: String) throws -> [String] { try index.search(query).map(\.title) }

    func testSearchIgnoresAccentsAndCaseAndMatchesPrefixesOfEveryField() throws {
        let (_, index, _) = try makeIndex()
        let songs = [song("Canción del Alba"), song("Amanecer Nuevo", lyrics: ["Una luz inventada brilla"]),
                     song("Placeholder", author: "Invented Writer", ccli: "7654321")]
        for song in songs { try index.save(song) }
        XCTAssertEqual(try titles(index, "cancion"), ["Canción del Alba"])
        XCTAssertEqual(try titles(index, "CANCIÓN alb"), ["Canción del Alba"])
        XCTAssertEqual(try titles(index, "amane"), ["Amanecer Nuevo"])
        XCTAssertEqual(try titles(index, "brill"), ["Amanecer Nuevo"])
        XCTAssertEqual(try titles(index, "writ"), ["Placeholder"])
        XCTAssertEqual(try titles(index, "76543"), ["Placeholder"])
        XCTAssertEqual(try titles(index, "luz alba"), [])
        XCTAssertEqual(try index.search("cancion").first?.url.deletingLastPathComponent().lastPathComponent, "Songs")
    }

    func testATitleMatchRanksAboveALyricsMatch() throws {
        let (_, index, _) = try makeIndex()
        try index.save(song("Other Words", lyrics: ["Invented river", "river of placeholder river"]))
        try index.save(song("River Song"))
        XCTAssertEqual(try titles(index, "river"), ["River Song", "Other Words"])
    }

    func testOddInputNeverFailsAndOnlyItsWordsAreSearched() throws {
        let (_, index, _) = try makeIndex()
        try index.save(song("Canción del Alba"))
        for query in ["", "   ", "\"", "*", "\"*", "(", "AND", "OR NOT", "NEAR(a b)", "-", "^", ":", "title:", "'", "🙂"] {
            XCTAssertEqual(try titles(index, query), [], query)
        }
        XCTAssertEqual(try titles(index, "\"cancion\" *alba*"), ["Canción del Alba"])
    }

    func testReconcileReadsOnlyChangedFilesAndFollowsChangesMadeOutsideTheApp() throws {
        let (library, index, _) = try makeIndex()
        var (a, b) = (song("Alpha Title"), song("Beta Title"))
        let urlA = try library.save(a)
        let urlB = try library.save(b)
        XCTAssertEqual(try index.reconcile().read, 2)
        XCTAssertEqual(try titles(index, "title"), ["Alpha Title", "Beta Title"])
        let warm = try index.reconcile()
        XCTAssertEqual([warm.read, warm.removed, warm.problems.count], [0, 0, 0])

        a.title = "Gamma Changed"
        XCTAssertEqual(try library.save(a), urlA)
        try files.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: urlA.path)
        try files.removeItem(at: urlB)
        try library.save(song("Delta Added"))
        try Data("{".utf8).write(to: library.songsFolder.appendingPathComponent("broken.song.json"))
        let report = try index.reconcile()
        XCTAssertEqual([report.read, report.removed], [3, 1])
        XCTAssertEqual(report.problems.map(\.url.lastPathComponent), ["broken.song.json"])
        XCTAssertEqual(try titles(index, "alpha beta"), [])
        XCTAssertEqual(try titles(index, "gamma"), ["Gamma Changed"])
        XCTAssertEqual(try titles(index, "delta"), ["Delta Added"])

        try files.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 120)], ofItemAtPath: urlA.path)
        XCTAssertEqual(try index.reconcile().read, 2)
        XCTAssertEqual(try titles(index, "gamma"), ["Gamma Changed"])
        b.title = "Beta Back"
        try library.save(b)
        XCTAssertEqual(try titles(index, "beta"), [])
        try index.reconcile()
        XCTAssertEqual(try titles(index, "beta"), ["Beta Back"])
    }

    func testAnIndexOfAnotherSchemaVersionOrUnreadableIsRebuilt() throws {
        let (library, index, url) = try makeIndex()
        try index.save(song("Alpha Title"))
        try library.save(song("Beta Title"))
        XCTAssertEqual(try index.reconcile().read, 1)
        XCTAssertEqual(try LibraryIndex(library: library, at: url).reconcile().read, 0)

        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(connection, "PRAGMA user_version = \(LibraryIndex.schemaVersion + 1)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(connection)
        let rebuilt = try LibraryIndex(library: library, at: url)
        XCTAssertEqual(try titles(rebuilt, "title"), [])
        XCTAssertEqual(try rebuilt.reconcile().read, 2)
        XCTAssertEqual(try titles(rebuilt, "title"), ["Alpha Title", "Beta Title"])

        try Data("Invented, not a database".utf8).write(to: url)
        XCTAssertEqual(try LibraryIndex(library: library, at: url).reconcile().read, 2)
    }

    func testACorruptedIndexWithAValidHeaderIsRebuilt() throws {
        let (library, index, url) = try makeIndex()
        for n in 0..<300 { try index.save(song("Invented \(n)")) }
        let handle = try FileHandle(forWritingTo: url)
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 4096)
        try handle.write(contentsOf: Data(repeating: 0xA5, count: Int(size) - 4096))
        try handle.close()
        let rebuilt = try LibraryIndex(library: library, at: url)
        XCTAssertEqual(try rebuilt.reconcile().read, 300)
        XCTAssertTrue(try titles(rebuilt, "Invented 7").contains("Invented 7"))
    }

    func testSavingThroughTheIndexWritesTheFileAndUpdatesItsEntryAtOnce() throws {
        let (library, index, _) = try makeIndex()
        var song = self.song("Alpha Title")
        let url = try index.save(song)
        XCTAssertEqual(try Song.decode(from: Data(contentsOf: url)), song)
        XCTAssertEqual(try titles(index, "alpha"), ["Alpha Title"])
        song.title = "Beta Title"
        XCTAssertEqual(try index.save(song), url)
        XCTAssertEqual(try titles(index, "alpha"), [])
        XCTAssertEqual(try index.search("beta").map(\.id), [song.id])
        XCTAssertEqual(try index.reconcile().read, 0)
        XCTAssertEqual(try files.contentsOfDirectory(atPath: library.songsFolder.path), [url.lastPathComponent])
    }

    func testTheDefaultLocationIsInApplicationSupportOutsideTheLibrary() throws {
        let library = try Library.open(temporaryFolder())
        let url = try LibraryIndex.defaultURL(for: library)
        XCTAssertTrue(url.path.hasSuffix("/Library/Application Support/GlobalServiceStudio/Index/\(library.id.uuidString.lowercased()).sqlite"))
        XCTAssertFalse(url.path.hasPrefix(library.folder.path))
    }

    /// Run with `GSS_PERF=1 swift test --filter testMeasureFiveThousandSongs` and read the printed timings.
    func testMeasureFiveThousandSongs() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GSS_PERF"] == "1", "Set GSS_PERF=1 to measure.")
        let (library, _, url) = try makeIndex()
        let words = ["luz", "canción", "río", "amanecer", "placeholder", "invented", "montaña", "corazón", "alba", "camino", "estrella", "voz"]
        for n in 0..<5_000 {
            var lyrics: [String] = []
            for i in 0..<24 {
                let picked: [String] = (0..<6).map { (k: Int) -> String in words[(n * 7 + i * 3 + k * 5) % words.count] }
                lyrics.append(picked.joined(separator: " "))
            }
            let title = "\(words[n % words.count].capitalized) \(words[(n / 12) % words.count]) \(n)"
            var song = self.song(title, lyrics: lyrics, author: "Invented Writer \(n % 50)")
            song.ccliNumber = String(1_000_000 + n)
            try song.encoded().write(to: library.songsFolder.appendingPathComponent("song-\(n).song.json"))
        }
        func time(_ work: () throws -> Void) rethrows -> String {
            let start = Date(); try work(); return String(format: "%.1f ms", Date().timeIntervalSince(start) * 1000)
        }
        var index: LibraryIndex?
        let cold = try time { index = try LibraryIndex(library: library, at: url); XCTAssertEqual(try index?.reconcile().read, 5_000) }
        index = nil
        let warm = try time { index = try LibraryIndex(library: library, at: url); XCTAssertEqual(try index?.reconcile().read, 0) }
        let search = try time { for query in ["cora", "canción río", "montana alba 49", "inven"] { _ = try index?.search(query) } }
        let save = try time { try index?.save(song("Invented Extra")) }
        print("GSS_PERF 5000 songs: cold rebuild \(cold), warm open and reconcile \(warm), 4 searches \(search), save one song \(save)")
    }
}
