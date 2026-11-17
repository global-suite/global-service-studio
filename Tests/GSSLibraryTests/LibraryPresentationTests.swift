import CryptoKit
import GSSCore
import GSSLibrary
import XCTest

final class LibraryPresentationTests: XCTestCase {
    private let files = FileManager.default

    private func temporaryFolder() -> URL {
        let url = files.temporaryDirectory.appendingPathComponent("GSSLibraryPresentationTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func names(_ folder: URL) throws -> [String] {
        try files.contentsOfDirectory(atPath: folder.path).sorted()
    }

    private func deck(_ title: String, id: UUID = UUID()) -> Presentation {
        let text = PresentationElement(id: "e1", kind: .text, slot: "lyrics", text: ["en": "Invented welcome"])
        return Presentation(id: id, title: title, slides: [PresentationSlide(id: "s1", elements: [text])])
    }

    func testSavingWritesASlugAndShortIDFileThatLoadsBackEqual() throws {
        let library = try Library.open(temporaryFolder())
        let id = try XCTUnwrap(UUID(uuidString: "0A9D3F77-41C2-4B0E-9D6A-3C5F2E8B7A19"))
        let saved = deck("Anuncios del Día", id: id)
        let url = try library.save(saved)
        XCTAssertEqual(url, library.presentationsFolder.appendingPathComponent("anuncios-del-dia-0a9d3f77.presentation.json"))
        XCTAssertEqual(try Data(contentsOf: url), try saved.encoded())
        XCTAssertEqual(try library.loadPresentation(at: url), saved)
    }

    func testATitleWithoutLettersOrDigitsGetsThePresentationSlug() throws {
        let library = try Library.open(temporaryFolder())
        let id = try XCTUnwrap(UUID(uuidString: "0A1B2C3D-1A2B-4C3D-8E4F-5A6B7C8D9E0F"))
        XCTAssertEqual(try library.save(deck("¡¿?!", id: id)).lastPathComponent, "presentation-0a1b2c3d.presentation.json")
    }

    func testSavingTheSameIDAfterATitleChangeOverwritesItsFileUnderItsName() throws {
        let library = try Library.open(temporaryFolder())
        var edited = deck("First Deck")
        let url = try library.save(edited)
        edited.title = "Second Deck"
        XCTAssertEqual(try library.save(edited), url)
        XCTAssertEqual(try names(library.presentationsFolder), [url.lastPathComponent])
        XCTAssertEqual(try library.loadPresentation(at: url), edited)
    }

    func testAnInvalidPresentationIsNotWritten() throws {
        let library = try Library.open(temporaryFolder())
        var invalid = deck("Invalid")
        invalid.slides.append(PresentationSlide(id: "s1", elements: []))
        XCTAssertThrowsError(try library.save(invalid)) { error in
            XCTAssertEqual(error as? FormatError, .validation(reason: "duplicateSlideId", at: "slides[1].id"))
        }
        XCTAssertEqual(try names(library.presentationsFolder), [])
    }

    func testListingReturnsValidPresentationsAndReportsInvalidFiles() throws {
        let library = try Library.open(temporaryFolder())
        let alpha = deck("Alpha"), beta = deck("Beta")
        try library.save(beta)
        try library.save(alpha)
        let broken = library.presentationsFolder.appendingPathComponent("broken.presentation.json")
        try Data("{".utf8).write(to: broken)
        try Data("Invented".utf8).write(to: library.presentationsFolder.appendingPathComponent("notes.txt"))
        let listing = try library.presentations()
        XCTAssertEqual(listing.presentations.map(\.presentation), [alpha, beta])
        XCTAssertEqual(listing.problems.map(\.url.lastPathComponent), ["broken.presentation.json"])
        XCTAssertEqual(listing.problems.first?.error as? FormatError, .invalidJSON)
        XCTAssertThrowsError(try library.loadPresentation(at: broken)) { XCTAssertEqual($0 as? FormatError, .invalidJSON) }
    }

    func testSlideImagesAreWrittenToTheirOwnFolderWithPathsAndHashes() throws {
        let library = try Library.open(temporaryFolder())
        let id = try XCTUnwrap(UUID(uuidString: "0A9D3F77-41C2-4B0E-9D6A-3C5F2E8B7A19"))
        let images = [Data("invented slide one".utf8), Data("invented slide two".utf8)]
        let references = try library.writeSlideImages(images, for: id)
        let base = "Media/Presentations/0a9d3f77-41c2-4b0e-9d6a-3c5f2e8b7a19"
        XCTAssertEqual(references, [
            MediaReference(path: "\(base)/001.png", sha256: hex(images[0])),
            MediaReference(path: "\(base)/002.png", sha256: hex(images[1])),
        ])
        for (reference, image) in zip(references, images) {
            XCTAssertEqual(try Data(contentsOf: library.folder.appendingPathComponent(reference.path)), image)
        }
        XCTAssertEqual(try names(library.folder.appendingPathComponent(base)), ["001.png", "002.png"])
    }

    func testReimportReplacesOnlyThatPresentationsImages() throws {
        let library = try Library.open(temporaryFolder())
        let media = library.folder.appendingPathComponent("Media")
        try Data("invented photo".utf8).write(to: media.appendingPathComponent("Photo.png"))
        let (id, other) = (UUID(), UUID())
        let kept = try library.writeSlideImages([Data("other deck".utf8)], for: other)
        try library.writeSlideImages([Data("old one".utf8), Data("old two".utf8), Data("old three".utf8)], for: id)
        let references = try library.writeSlideImages([Data("new one".utf8)], for: id)
        let folder = media.appendingPathComponent("Presentations/\(id.uuidString.lowercased())")
        XCTAssertEqual(references.map(\.sha256), [hex(Data("new one".utf8))])
        XCTAssertEqual(try names(folder), ["001.png"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("001.png")), Data("new one".utf8))
        XCTAssertEqual(try Data(contentsOf: library.folder.appendingPathComponent(kept[0].path)), Data("other deck".utf8))
        XCTAssertEqual(try names(media), ["Photo.png", "Presentations"])
        XCTAssertEqual(try names(media.appendingPathComponent("Presentations")),
                       [id.uuidString.lowercased(), other.uuidString.lowercased()].sorted())
        XCTAssertEqual(try library.media().map(\.path), ["Media/Photo.png"])
    }

    func testImportedDeckHasOneFullFrameFitImagePerSlideWithNotes() throws {
        let library = try Library.open(temporaryFolder())
        let id = UUID()
        let references = try library.writeSlideImages([Data("a".utf8), Data("b".utf8), Data("c".utf8)], for: id)
        let presentation = Presentation.importedDeck(id: id, title: "Invented Deck", images: references,
                                                     notes: ["Invented reminder", nil])
        XCTAssertEqual(presentation.id, id)
        XCTAssertEqual(presentation.title, "Invented Deck")
        XCTAssertEqual(presentation.slides.map(\.id), ["s1", "s2", "s3"])
        XCTAssertEqual(presentation.slides.map(\.notes), ["Invented reminder", nil, nil])
        let full = ThemeFrame(x: 0, y: 0, width: 1, height: 1)
        for (slide, reference) in zip(presentation.slides, references) {
            let image = PresentationElement(id: "e1", kind: .image, frame: full, media: reference, scaling: .fit)
            XCTAssertEqual(slide.elements, [image])
        }
        XCTAssertNoThrow(try presentation.validate())
        XCTAssertEqual(try Presentation.decode(from: presentation.encoded()), presentation)
        let url = try library.save(presentation)
        XCTAssertEqual(try library.loadPresentation(at: url), presentation)
    }
}
