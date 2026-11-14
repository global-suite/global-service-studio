import GSSCore
import GSSLibrary
import XCTest

final class LibraryTests: XCTestCase {
    private let files = FileManager.default

    private func temporaryFolder() -> URL {
        let url = files.temporaryDirectory.appendingPathComponent("GSSLibraryTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Every file and folder under `url`, with the bytes of each file.
    private func snapshot(_ url: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        for case let item as URL in files.enumerator(at: url, includingPropertiesForKeys: nil)! { result[item.path] = (try? Data(contentsOf: item)) ?? Data() }
        return result
    }

    private func song(_ title: String, id: UUID = UUID()) -> Song {
        Song(id: id, title: title, language: "en", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Invented line"])])])
    }

    func testOpeningAnEmptyFolderCreatesTheLayoutAndReopeningKeepsTheID() throws {
        let folder = temporaryFolder().appendingPathComponent("Placeholder Library")
        let library = try Library.open(folder)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("library.json"))) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "gss.library")
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["id"] as? String, library.id.uuidString.lowercased())
        XCTAssertEqual(json["name"] as? String, "Placeholder Library")
        XCTAssertEqual(try files.contentsOfDirectory(atPath: folder.path).sorted(), ["Media", "Plans", "Presentations", "Songs", "Themes", "library.json"])
        XCTAssertEqual(try Library.open(folder), library)
        XCTAssertEqual(library.name, "Placeholder Library")
    }

    func testAnotherFormatANewerVersionOrANonEmptyFolderIsRefusedAndLeftUnchanged() throws {
        let cases: [(String?, Error)] = [
            (#"{"format": "other.app", "version": 1, "id": "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10", "name": "X"}"#, FormatError.wrongFormat(expected: "gss.library", found: "other.app")),
            (#"{"format": "gss.library", "version": 2, "id": "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10", "name": "X"}"#, FormatError.unsupportedVersion(found: 2, supported: 1)),
            (nil, LibraryError.folderNotEmpty),
        ]
        for (manifest, expected) in cases {
            let folder = temporaryFolder()
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("Invented notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
            try manifest.map { try Data($0.utf8).write(to: folder.appendingPathComponent("library.json")) }
            let before = snapshot(folder)
            XCTAssertThrowsError(try Library.open(folder)) { XCTAssertEqual("\($0)", "\(expected)") }
            XCTAssertEqual(snapshot(folder), before)
        }
    }

    func testSavingWritesASlugAndShortIDFileThatReadsBackEqual() throws {
        let library = try Library.open(temporaryFolder())
        let song = song("Luz de la Mañana", id: UUID(uuidString: "6F1C2B9E-0D0A-4A37-9B1E-2F6D1C3A7E10")!)
        let url = try library.save(song)
        XCTAssertEqual(url, library.songsFolder.appendingPathComponent("luz-de-la-manana-6f1c2b9e.song.json"))
        XCTAssertEqual(try Data(contentsOf: url), try song.encoded())
        XCTAssertEqual(try Song.decode(from: Data(contentsOf: url)), song)
    }

    func testSlugsAreLowercaseASCIIWordsJoinedByHyphens() {
        let titles = ["Canción del Señor", "  Hello,  World!! ", "Ñandú 2", "", "¡¿?!", String(repeating: "word ", count: 20)]
        XCTAssertEqual(titles.map(Library.slug), ["cancion-del-senor", "hello-world", "nandu-2", "song", "song", "word-word-word-word-word-word-word-word-word-word-word-word"])
    }

    func testSavingTheSameIDAfterATitleChangeOverwritesItsFile() throws {
        let library = try Library.open(temporaryFolder())
        var edited = song("First Title")
        let url = try library.save(edited)
        edited.title = "Second Title"
        XCTAssertEqual(try library.save(edited), url)
        XCTAssertEqual(try files.contentsOfDirectory(atPath: library.songsFolder.path), [url.lastPathComponent])
        XCTAssertEqual(try Song.decode(from: Data(contentsOf: url)), edited)
    }

    func testSavingToAKnownFileOrToAFileRenamedOutsideTheAppKeepsThatFile() throws {
        let library = try Library.open(temporaryFolder())
        var edited = song("First Title")
        let original = try library.save(edited)
        let renamed = library.songsFolder.appendingPathComponent("renamed-by-hand.song.json")
        try files.moveItem(at: original, to: renamed)
        let other = try library.save(song("Other Title"))
        edited.title = "Second Title"
        XCTAssertEqual(try library.save(edited), renamed)
        edited.title = "Third Title"
        XCTAssertEqual(try library.save(edited, existingFile: renamed), renamed)
        let names = try files.contentsOfDirectory(atPath: library.songsFolder.path).sorted()
        XCTAssertEqual(names, [other.lastPathComponent, "renamed-by-hand.song.json"].sorted())
        XCTAssertEqual(try Song.decode(from: Data(contentsOf: renamed)), edited)
    }

    func testListingReturnsValidSongsAndReportsInvalidFiles() throws {
        let library = try Library.open(temporaryFolder())
        let (a, b) = (song("Alpha"), song("Beta"))
        _ = try (library.save(b), library.save(a))
        try Data("{".utf8).write(to: library.songsFolder.appendingPathComponent("broken.song.json"))
        try Data("Invented".utf8).write(to: library.songsFolder.appendingPathComponent("notes.txt"))
        let listing = try library.songs()
        XCTAssertEqual(listing.songs.map(\.song), [a, b])
        XCTAssertEqual(listing.problems.map(\.url.lastPathComponent), ["broken.song.json"])
        XCTAssertEqual(listing.problems.first?.error as? FormatError, .invalidJSON)
    }

    func testMostRecentSongIsTheLastModifiedFile() throws {
        let library = try Library.open(temporaryFolder())
        XCTAssertNil(try library.songs().mostRecent)
        let (a, b) = (song("Alpha"), song("Beta"))
        let (urlA, urlB) = try (library.save(a), library.save(b))
        try files.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: urlB.path)
        XCTAssertEqual(try library.songs().mostRecent?.song, a)
        try files.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: urlB.path)
        XCTAssertEqual(try library.songs().mostRecent?.song, b)
        XCTAssertNotEqual(urlA, urlB)
    }
}
