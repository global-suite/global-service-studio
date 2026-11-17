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

    private func data(_ contents: String) -> Data { Data(contents.utf8) }

    private func contents(_ library: Library, _ path: String) throws -> Data {
        try Data(contentsOf: library.folder.appendingPathComponent(path))
    }

    func testImportingDataWritesItIntoMediaAndReturnsItsPathAndHash() throws {
        let library = try Library.open(temporaryFolder())
        let reference = try library.importMedia(data: data("slide bytes"), fileExtension: "png", suggestedName: "Slide 1")
        XCTAssertEqual(reference, MediaReference(path: "Media/Slide 1.png", sha256: hex("slide bytes")))
        XCTAssertEqual(try contents(library, "Media/Slide 1.png"), data("slide bytes"))
        XCTAssertEqual(try mediaNames(library), ["Slide 1.png"])
    }

    func testImportingTheSameDataTwiceWritesItOnce() throws {
        let library = try Library.open(temporaryFolder())
        let first = try library.importMedia(data: data("same"), fileExtension: "png", suggestedName: "One")
        let second = try library.importMedia(data: data("same"), fileExtension: "png", suggestedName: "Two")
        XCTAssertEqual(second, first)
        XCTAssertEqual(try mediaNames(library), ["One.png"])
    }

    func testDataWithATakenNameAndDifferentContentGetsANumberedName() throws {
        let library = try Library.open(temporaryFolder())
        _ = try library.importMedia(data: data("first"), fileExtension: "jpg", suggestedName: "Slide")
        let second = try library.importMedia(data: data("second"), fileExtension: "jpg", suggestedName: "Slide")
        XCTAssertEqual(second, MediaReference(path: "Media/Slide 2.jpg", sha256: hex("second")))
        XCTAssertEqual(try contents(library, "Media/Slide 2.jpg"), data("second"))
    }

    func testDataNamesLoseLeadingDotsAndSlashes() throws {
        let library = try Library.open(temporaryFolder())
        let hidden = try library.importMedia(data: data("a"), fileExtension: "png", suggestedName: "..Hidden")
        let slashed = try library.importMedia(data: data("b"), fileExtension: "png", suggestedName: "a/b")
        XCTAssertEqual([hidden.path, slashed.path], ["Media/Hidden.png", "Media/a-b.png"])
    }

    func testDataIntoASubfolderCreatesItAndReturnsTheNestedPath() throws {
        let library = try Library.open(temporaryFolder())
        let reference = try library.importMedia(data: data("slide"), fileExtension: "png", suggestedName: "Slide 1",
                                                in: "Presentations/abc")
        XCTAssertEqual(reference, MediaReference(path: "Media/Presentations/abc/Slide 1.png", sha256: hex("slide")))
        XCTAssertTrue(reference.hasLibraryRelativePath)
        XCTAssertEqual(try contents(library, reference.path), data("slide"))
    }

    func testDedupeLooksOnlyInsideTheTargetFolder() throws {
        let library = try Library.open(temporaryFolder())
        let top = try library.importMedia(data: data("same"), fileExtension: "png", suggestedName: "Slide")
        let nested = try library.importMedia(data: data("same"), fileExtension: "png", suggestedName: "Slide", in: "Sub")
        XCTAssertEqual([top.path, nested.path], ["Media/Slide.png", "Media/Sub/Slide.png"])
        XCTAssertEqual(try contents(library, nested.path), data("same"))
    }

    func testAnInvalidFolderThrowsAndLeavesTheDiskUnchanged() throws {
        let library = try Library.open(temporaryFolder())
        _ = try library.importMedia(data: data("kept"), fileExtension: "png", suggestedName: "Kept")
        let before = try files.subpathsOfDirectory(atPath: library.folder.path)
        for folder in ["../x", "/abs", "a//b", ".", "", "a/./b", "a/"] {
            XCTAssertThrowsError(try library.importMedia(data: data("new"), fileExtension: "png", suggestedName: "New",
                                                         in: folder), folder) {
                XCTAssertEqual($0 as? LibraryMediaError, .invalidFolder, folder)
            }
            XCTAssertThrowsError(try library.importMedia(source("New.png", "new"), in: folder), folder) {
                XCTAssertEqual($0 as? LibraryMediaError, .invalidFolder, folder)
            }
        }
        XCTAssertEqual(try files.subpathsOfDirectory(atPath: library.folder.path), before)
    }

    func testDataWithARefusedExtensionThrowsAndWritesNothing() throws {
        let library = try Library.open(temporaryFolder())
        for ext in ["txt", "mp3", "", "a/png"] {
            XCTAssertThrowsError(try library.importMedia(data: data("x"), fileExtension: ext, suggestedName: "X")) {
                XCTAssertEqual($0 as? LibraryMediaError, .notMedia)
            }
        }
        XCTAssertEqual(try mediaNames(library), [])
    }

    func testAFileImportsIntoASubfolder() throws {
        let library = try Library.open(temporaryFolder())
        let reference = try library.importMedia(source("Sunrise.png", "sun"), in: "Presentations/abc")
        XCTAssertEqual(reference, MediaReference(path: "Media/Presentations/abc/Sunrise.png", sha256: hex("sun")))
        XCTAssertEqual(try contents(library, reference.path), data("sun"))
    }

    func testMediaDoesNotListFilesInSubfolders() throws {
        let library = try Library.open(temporaryFolder())
        _ = try library.importMedia(data: data("top"), fileExtension: "png", suggestedName: "Top")
        _ = try library.importMedia(data: data("nested"), fileExtension: "png", suggestedName: "Nested", in: "Presentations/abc")
        XCTAssertEqual(try library.media().map(\.path), ["Media/Top.png"])
    }
}
