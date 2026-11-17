import CryptoKit
import GSSCore
import GSSLibrary
import XCTest

final class LibraryMediaTests: XCTestCase {
    private let files = FileManager.default

    private func temporaryFolder(_ label: String = "Library") -> URL {
        let url = files.temporaryDirectory.appendingPathComponent("GSSLibraryMediaTests-\(label)-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A small file outside the library with `contents`, named `name`.
    private func source(_ name: String, _ contents: String) throws -> URL {
        let folder = temporaryFolder("Source")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func hex(_ contents: String) -> String {
        SHA256.hash(data: Data(contents.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func mediaNames(_ library: Library) throws -> [String] {
        try files.contentsOfDirectory(atPath: library.folder.appendingPathComponent("Media").path).sorted()
    }

    func testImportCopiesTheFileIntoMediaAndReturnsItsPathAndHash() throws {
        let library = try Library.open(temporaryFolder())
        let reference = try library.importMedia(source("Sunrise.png", "placeholder image bytes"))
        XCTAssertEqual(reference, MediaReference(path: "Media/Sunrise.png", sha256: hex("placeholder image bytes")))
        XCTAssertTrue(reference.hasLibraryRelativePath)
        let copied = library.folder.appendingPathComponent("Media/Sunrise.png")
        XCTAssertEqual(try Data(contentsOf: copied), Data("placeholder image bytes".utf8))
        XCTAssertEqual(try mediaNames(library), ["Sunrise.png"])
    }

    func testImportingTheSameContentTwiceCopiesItOnce() throws {
        let library = try Library.open(temporaryFolder())
        let first = try library.importMedia(source("Loop.mov", "same video bytes"))
        let second = try library.importMedia(source("Other name.mov", "same video bytes"))
        XCTAssertEqual(second, first)
        XCTAssertEqual(try mediaNames(library), ["Loop.mov"])
    }

    func testDifferentContentWithATakenNameGetsANumberedName() throws {
        let library = try Library.open(temporaryFolder())
        _ = try library.importMedia(source("Clip.mp4", "first clip"))
        let second = try library.importMedia(source("Clip.mp4", "second clip"))
        let third = try library.importMedia(source("Clip.mp4", "third clip"))
        XCTAssertEqual(second, MediaReference(path: "Media/Clip 2.mp4", sha256: hex("second clip")))
        XCTAssertEqual(third.path, "Media/Clip 3.mp4")
        XCTAssertEqual(try Data(contentsOf: library.folder.appendingPathComponent("Media/Clip 2.mp4")), Data("second clip".utf8))
        XCTAssertEqual(try mediaNames(library), ["Clip 2.mp4", "Clip 3.mp4", "Clip.mp4"])
    }

    func testAFileThatIsNotAnImageOrVideoIsRefusedAndMediaStaysUnchanged() throws {
        let library = try Library.open(temporaryFolder())
        _ = try library.importMedia(source("Kept.png", "kept"))
        for name in ["Notes.txt", "Song.mp3", "NoExtension"] {
            XCTAssertThrowsError(try library.importMedia(source(name, "not media"))) {
                XCTAssertEqual($0 as? LibraryMediaError, .notMedia)
            }
        }
        XCTAssertEqual(try mediaNames(library), ["Kept.png"])
    }

    func testAnUnreadableFileThrowsAndLeavesNoPartialFile() throws {
        let library = try Library.open(temporaryFolder())
        let missing = temporaryFolder("Missing").appendingPathComponent("Gone.png")
        XCTAssertThrowsError(try library.importMedia(missing)) { XCTAssertEqual($0 as? LibraryMediaError, .unreadable) }
        XCTAssertEqual(try mediaNames(library), [])
    }

    func testMediaListsImagesAndVideosByNameWithKindSizeAndDate() throws {
        let library = try Library.open(temporaryFolder())
        _ = try library.importMedia(source("item 10.png", "ten"))
        _ = try library.importMedia(source("item 2.mov", "two!"))
        _ = try library.importMedia(source("Alpha.jpg", "a"))
        let media = library.folder.appendingPathComponent("Media")
        try Data("hidden".utf8).write(to: media.appendingPathComponent(".hidden.png"))
        try Data("temp".utf8).write(to: media.appendingPathComponent(".import-123.tmp"))
        try Data("text".utf8).write(to: media.appendingPathComponent("Readme.txt"))
        try files.createDirectory(at: media.appendingPathComponent("Folder.mov"), withIntermediateDirectories: true)

        let listed = try library.media()
        XCTAssertEqual(listed.map(\.path), ["Media/Alpha.jpg", "Media/item 2.mov", "Media/item 10.png"])
        XCTAssertEqual(listed.map(\.kind), [.image, .video, .image])
        XCTAssertEqual(listed.map(\.byteCount), [1, 4, 3])
        let modified = try media.appendingPathComponent("item 2.mov").resourceValues(forKeys: [.contentModificationDateKey])
        XCTAssertEqual(listed[1].modified, modified.contentModificationDate)
    }

    func testAnEmptyMediaFolderListsNothing() throws {
        XCTAssertEqual(try Library.open(temporaryFolder()).media(), [])
    }
}
