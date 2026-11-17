import AppKit
import GSSCore
import GSSLibrary
import XCTest
@testable import GSSApp

/// Keynote, PowerPoint (issue #112) and PDF (issue #123) import with generated PDFs and fake exporters; Keynote and PowerPoint are never used.
final class DeckImportTests: XCTestCase {
    /// Writes a PDF whose pages have these sizes, each painting only an opaque red rectangle over its middle half;
    /// `info` is the PDF context's auxiliary information, such as its passwords.
    static func makePDF(_ sizes: [CGSize], at url: URL, info: [CFString: Any] = [:]) {
        guard let context = CGContext(url as CFURL, mediaBox: nil, info as CFDictionary) else { return }
        for size in sizes {
            var media = CGRect(origin: .zero, size: size)
            context.beginPage(mediaBox: &media)
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: size.width / 4, y: size.height / 4, width: size.width / 2, height: size.height / 2))
            context.endPage()
        }
        context.closePDF()
    }

    /// Writes a three-page PDF after `delay` microseconds, or throws `error`.
    struct FakeExporter: DeckExporter {
        var notes: [String?] = ["Invented reminder", nil, ""], error: Error?, delay: UInt32 = 0
        func exportPDF(of source: URL, to pdf: URL) async throws -> [String?] {
            if let error { throw error }
            usleep(delay)
            DeckImportTests.makePDF(Array(repeating: CGSize(width: 160, height: 90), count: 3), at: pdf)
            return notes
        }
    }

    private func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DeckImportTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func waitForImport(_ state: AppState) {
        for _ in 0..<1000 where state.presentationImport != nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testRendererFitsEachPageInTheTargetAtItsOwnAspectWithATransparentBackground() throws {
        let url = temporaryFolder()
        Self.makePDF([CGSize(width: 160, height: 90), CGSize(width: 400, height: 300)], at: url)
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        func render(_ page: Int, _ size: CGSize) throws -> NSBitmapImageRep {
            try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(DeckRenderer.png(of: try XCTUnwrap(document.page(at: page)), fitting: size))))
        }
        let wide = try render(1, DeckRenderer.hd), square = try render(2, DeckRenderer.hd), ultra = try render(1, DeckRenderer.ultraHD)
        XCTAssertEqual([wide.pixelsWide, wide.pixelsHigh, square.pixelsWide, square.pixelsHigh, ultra.pixelsWide, ultra.pixelsHigh], [1920, 1080, 1440, 1080, 3840, 2160])
        XCTAssertEqual(wide.colorAt(x: 0, y: 0)?.alphaComponent, 0, "a corner the page does not paint is transparent")
        let center = try XCTUnwrap(wide.colorAt(x: 960, y: 540))
        XCTAssertEqual([center.alphaComponent, center.redComponent.rounded()], [1, 1], "the painted middle is opaque red")
    }

    func testImportSavesThePresentationWithItsSlidesNotesAndImages() throws {
        let folder = temporaryFolder(), state = AppState()
        state.perform(.chooseLibraryFolder(folder))
        state.deckExporter = FakeExporter()
        state.perform(.importPresentation(URL(fileURLWithPath: "/Invented/Invented Sermon.key")))
        XCTAssertEqual(state.presentationImport?.title, "Invented Sermon")
        waitForImport(state)
        XCTAssertNil(state.alert)
        let stored = try XCTUnwrap(try Library.open(folder).presentations().presentations.first)
        XCTAssertEqual([state.importedPresentation?.lastPathComponent, stored.presentation.title], [stored.url.lastPathComponent, "Invented Sermon"])
        XCTAssertEqual(stored.presentation.slides.map(\.notes), ["Invented reminder", nil, nil])
        let id = stored.presentation.id.uuidString.lowercased()
        let paths = stored.presentation.slides.compactMap { $0.elements.first?.media?.path }
        XCTAssertEqual(paths, ["001", "002", "003"].map { "Media/Presentations/\(id)/\($0).png" })
        XCTAssertTrue(paths.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) })
        XCTAssertEqual(String(format: Strings.text("Importing slide %ld of %ld", language: "es"), 3, 24), "Importando diapositiva 3 de 24")
    }

    func testFailuresShowTheirMessageAndSaveNothing() throws {
        let folder = temporaryFolder(), state = AppState()
        state.perform(.chooseLibraryFolder(folder))
        state.deckExporter = FakeExporter(error: NSError(domain: NSOSStatusErrorDomain, code: -1743))
        state.perform(.importPresentation(URL(fileURLWithPath: "/Invented/Invented.key")))
        waitForImport(state)
        XCTAssertEqual(state.alert?.title, Strings.text("The presentation could not be imported."))
        XCTAssertEqual(state.alert?.message, DeckImport.message(for: DeckImportError.permissionDenied))
        XCTAssertTrue(DeckImport.message(for: DeckImportError.permissionDenied, language: "es")?.contains("Privacidad y seguridad") == true)
        state.deckExporter = KeynoteExporter(isInstalled: { false })
        state.perform(.importPresentation(URL(fileURLWithPath: "/Invented/Invented.key")))
        waitForImport(state)
        XCTAssertEqual(state.alert?.message, Strings.text("Keynote is needed to import Keynote files. You can also export the presentation as PDF from the app that made it."))
        state.perform(.importPresentation(URL(fileURLWithPath: "/Invented/Invented.pptx")))
        waitForImport(state)
        XCTAssertEqual(state.alert?.message, Strings.text("Keynote is needed to import PowerPoint files. You can also export the presentation as PDF from the app that made it."))
        XCTAssertEqual(try Library.open(folder).presentations().presentations.count, 0)
        state.deckExporter = FakeExporter(delay: 200_000)
        state.perform(.importPresentation(URL(fileURLWithPath: "/Invented/Invented.key")))
        state.perform(.cancelPresentationImport)
        XCTAssertEqual([state.presentationImport == nil, state.alert?.message == Strings.text("Keynote is needed to import PowerPoint files. You can also export the presentation as PDF from the app that made it.")], [true, true], "a cancelled import shows no new alert")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    func testCancellingLeavesNothingBehind() async throws {
        let folder = temporaryFolder(), scratch = temporaryFolder(), library = try Library.open(folder)
        let task = Task { try await DeckImport.run(URL(fileURLWithPath: "/Invented/Invented.key"), into: library, exporter: FakeExporter(delay: 200_000), scratch: scratch) }
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? DeckImportError, .cancelled) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [], "the temporary PDF is removed")
        XCTAssertEqual(try library.presentations().presentations.count, 0)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: folder.path + "/Media/Presentations")) ?? [], [], "no slide images")
    }

    func testPDFPagesBecomeSlidesInOrderWithoutTheExporterOrNotes() async throws {
        let folder = temporaryFolder(), source = temporaryFolder(), library = try Library.open(folder)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let pdf = source.appendingPathComponent("Invented Notices.pdf")
        Self.makePDF([CGSize(width: 160, height: 90), CGSize(width: 90, height: 160), CGSize(width: 400, height: 300)], at: pdf)
        let exporter = FakeExporter(error: DeckImportError.exportFailed)
        let url = try await DeckImport.run(pdf, into: library, exporter: exporter)
        let stored = try XCTUnwrap(try library.presentations().presentations.first)
        XCTAssertEqual([stored.url.lastPathComponent, stored.presentation.title], [url.lastPathComponent, "Invented Notices"])
        XCTAssertEqual(stored.presentation.slides.map(\.notes), [nil, nil, nil])
        let id = stored.presentation.id.uuidString.lowercased()
        let paths = stored.presentation.slides.compactMap { $0.elements.first?.media?.path }
        XCTAssertEqual(paths, ["001", "002", "003"].map { "Media/Presentations/\(id)/\($0).png" })
        let widths = paths.map { NSBitmapImageRep(data: (try? Data(contentsOf: folder.appendingPathComponent($0))) ?? Data())?.pixelsWide }
        XCTAssertEqual(widths, [1920, 608, 1440], "the pages keep their order")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdf.path), "the PDF is read in place")
    }

    func testDamagedOrProtectedPDFsShowTheirMessageAndSaveNothing() async throws {
        let folder = temporaryFolder(), source = temporaryFolder(), library = try Library.open(folder)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let damaged = source.appendingPathComponent("Damaged.pdf"), locked = source.appendingPathComponent("Locked.pdf")
        try Data((0..<512).map { _ in UInt8.random(in: 0...255) }).write(to: damaged)
        let passwords: [CFString: Any] = [kCGPDFContextUserPassword: "invented", kCGPDFContextOwnerPassword: "invented"]
        Self.makePDF([CGSize(width: 160, height: 90)], at: locked, info: passwords)
        let exporter = FakeExporter(error: DeckImportError.exportFailed)
        var errors: [DeckImportError?] = []
        for pdf in [damaged, locked] {
            do { _ = try await DeckImport.run(pdf, into: library, exporter: exporter) } catch { errors.append(error as? DeckImportError) }
        }
        XCTAssertEqual(errors, [.unreadablePDF, .passwordProtected])
        XCTAssertEqual(DeckImport.message(for: DeckImportError.unreadablePDF), Strings.text("This PDF could not be read."))
        XCTAssertEqual(DeckImport.message(for: DeckImportError.passwordProtected, language: "es"), "Este PDF está protegido con contraseña. Quítale la contraseña y vuelve a importarlo.")
        XCTAssertEqual(try library.presentations().presentations.count, 0)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: folder.path + "/Media/Presentations")) ?? [], [], "no slide images")
    }

    func testCancellingAPDFImportLeavesNothingBehind() async throws {
        let folder = temporaryFolder(), source = temporaryFolder(), library = try Library.open(folder)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let pdf = source.appendingPathComponent("Invented.pdf")
        Self.makePDF(Array(repeating: CGSize(width: 160, height: 90), count: 3), at: pdf)
        let task = Task { try await DeckImport.run(pdf, into: library, exporter: FakeExporter()) }
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? DeckImportError, .cancelled) }
        XCTAssertEqual(try library.presentations().presentations.count, 0)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: folder.path + "/Media/Presentations")) ?? [], [], "no slide images")
    }
}
