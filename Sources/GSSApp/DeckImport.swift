import AppKit
import Combine
import GSSCore
import GSSLibrary
import UniformTypeIdentifiers

/// Why a presentation could not be imported, localized by `DeckImport.message(for:)`; `noApplication` names the kind of file.
enum DeckImportError: Error, Equatable {
    enum Kind: Equatable, Sendable { case keynote, powerPoint }
    case noApplication(Kind), permissionDenied, cannotOpen, exportFailed, cancelled, passwordProtected, unreadablePDF
}

/// Exports a deck to a PDF without its skipped slides and returns the speaker notes of each exported slide, in order.
protocol DeckExporter: Sendable {
    func exportPDF(of source: URL, to pdf: URL) async throws -> [String?]
}

/// Exports Keynote and PowerPoint files with Keynote through Apple Events (ADR 0010), one script at a time off the main thread;
/// a failure throws its Apple Events number in `NSOSStatusErrorDomain`.
struct KeynoteExporter: DeckExporter {
    static let bundleID = "com.apple.iWork.Keynote"
    var isInstalled: @Sendable () -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: KeynoteExporter.bundleID) != nil }
    private static let queue = DispatchQueue(label: "GSS deck export")

    func exportPDF(of source: URL, to pdf: URL) async throws -> [String?] {
        guard isInstalled() else { throw DeckImportError.noApplication(source.pathExtension.lowercased() == "key" ? .keynote : .powerPoint) }
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                var info: NSDictionary?
                let result = NSAppleScript(source: Self.script(source: source, pdf: pdf))?.executeAndReturnError(&info)
                guard info == nil, let result else {
                    let code = info?[NSAppleScript.errorNumber] as? Int ?? -1
                    return continuation.resume(throwing: NSError(domain: NSOSStatusErrorDomain, code: code))
                }
                continuation.resume(returning: (0..<result.numberOfItems).map { result.atIndex($0 + 1)?.stringValue })
            }
        }
    }

    /// Opens the deck (failing with -43), exports it without skipped slides, reads their notes and closes it unless it was open.
    static func script(source: URL, pdf: URL) -> String {
        let quoted = { (url: URL) in "\"" + url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return """
            set deck to POSIX file \(quoted(source))
            set target to POSIX file \(quoted(pdf))
            set notesList to {}
            tell application id "\(bundleID)"
            set openBefore to count of documents
            try
            set doc to open deck
            on error
            error number -43
            end try
            set opened to (count of documents) > openBefore
            try
            export doc to target as PDF with properties {skipped slides:false, PDF image quality:Best}
            repeat with aSlide in (get every slide of doc whose skipped is false)
            set end of notesList to (presenter notes of aSlide) as text
            end repeat
            on error message number code
            if opened then close doc saving no
            error message number code
            end try
            if opened then close doc saving no
            end tell
            return notesList
            """
    }
}

/// Imports a deck: exported to a temporary PDF, rendered page by page, written as slide images and saved as a presentation.
/// A PDF file skips the exporter: it is rendered in place and its presentation has no notes.
enum DeckImport {
    /// Runs off the main thread, reporting `progress(slide, count)`, and returns the saved file; a failed or cancelled import
    /// leaves no temporary PDF, slide images or presentation file.
    static func run(_ source: URL, into library: Library, exporter: DeckExporter, size: CGSize = DeckRenderer.hd,
                    scratch: URL = FileManager.default.temporaryDirectory, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> URL {
        let files = FileManager.default, folder = scratch.appendingPathComponent("GSSDeckImport-\(UUID().uuidString)"), id = UUID()
        let images = library.folder.appendingPathComponent("Media/Presentations/\(id.uuidString.lowercased())")
        var saved: URL?
        defer { try? files.removeItem(at: folder) }
        do {
            let isPDF = source.pathExtension.lowercased() == "pdf", failure = isPDF ? DeckImportError.unreadablePDF : .exportFailed
            var pdf = source, notes: [String?] = []
            if !isPDF {
                try files.createDirectory(at: folder, withIntermediateDirectories: true)
                pdf = folder.appendingPathComponent("deck.pdf")
                notes = try await exporter.exportPDF(of: source, to: pdf)
            }
            guard let document = CGPDFDocument(pdf as CFURL) else { throw failure }
            if document.isEncrypted, !document.isUnlocked, !document.unlockWithPassword("") { throw DeckImportError.passwordProtected }
            guard document.numberOfPages > 0 else { throw failure }
            let pages = try (1...document.numberOfPages).map { number -> Data in
                try Task.checkCancellation()
                progress(number, document.numberOfPages)
                guard let png = document.page(at: number).flatMap({ DeckRenderer.png(of: $0, fitting: size) }) else { throw failure }
                return png
            }
            try Task.checkCancellation()
            let references = try library.writeSlideImages(pages, for: id)
            let url = try library.save(.importedDeck(id: id, title: source.deletingPathExtension().lastPathComponent, images: references, notes: notes))
            saved = url
            try Task.checkCancellation()
            return url
        } catch {
            for url in [saved, images].compactMap({ $0 }) { try? files.removeItem(at: url) }
            throw importError(error)
        }
    }

    /// Maps cancellation and Apple Events numbers to `DeckImportError`; library errors pass through.
    static func importError(_ error: Error) -> Error {
        let codes: [Int: DeckImportError] = [-1743: .permissionDenied, -128: .cancelled, -43: .cannotOpen], code = (error as NSError).code
        if error is CancellationError { return DeckImportError.cancelled }
        return error is DeckImportError || (error as NSError).domain != NSOSStatusErrorDomain ? error : codes[code] ?? DeckImportError.exportFailed
    }

    /// The localized reason an import failed; nil for a cancelled import, which shows nothing.
    static func message(for error: Error, language: String = Strings.language) -> String? {
        let key: String
        switch error {
        case DeckImportError.cancelled: return nil
        case DeckImportError.noApplication(.keynote): key = "Keynote is needed to import Keynote files. You can also export the presentation as PDF from the app that made it."
        case DeckImportError.noApplication(.powerPoint): key = "Keynote is needed to import PowerPoint files. You can also export the presentation as PDF from the app that made it."
        case DeckImportError.permissionDenied: key = "Global Service Studio is not allowed to control Keynote or PowerPoint. Allow it in System Settings → Privacy & Security → Automation, then import again."
        case DeckImportError.cannotOpen: key = "The file could not be opened. Check that it opens in Keynote or PowerPoint."
        case DeckImportError.exportFailed: key = "The slides could not be exported. You can also export the presentation as PDF from the app that made it."
        case DeckImportError.passwordProtected: key = "This PDF is protected with a password. Remove the password and import it again."
        case DeckImportError.unreadablePDF: key = "This PDF could not be read."
        default: return Strings.libraryMessage(for: error, language: language)
        }
        return Strings.text(key, language: language)
    }
}

/// The progress of an import: the deck's title and the slide being rendered, 0 while the deck is exported.
public struct PresentationImport: Equatable, Sendable {
    public var title: String, slide = 0, count = 0
}

/// A weak reference a background task carries back to the main thread.
final class WeakReference<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?
    init(_ value: Value) { self.value = value }
}

extension MainWindowController {
    /// File > Import Presentation…: chooses a Keynote, PowerPoint or PDF file, then shows the progress with Cancel.
    @objc func importPresentation(_ sender: Any?) {
        guard let window, state.presentationImport == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["key", "pptx", "ppt", "pdf"].compactMap { UTType(filenameExtension: $0) }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let state = self?.state else { return }
            state.perform(.importPresentation(url))
            if state.presentationImport != nil { PresentationImportSheet().show(state, on: window) }
        }
    }
}

/// The progress sheet of an import; it keeps itself alive until the import ends or is cancelled.
private final class PresentationImportSheet {
    private let alert = NSAlert(), bar = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 320, height: 20))
    private var observer: AnyCancellable?

    func show(_ state: AppState, on window: NSWindow) {
        alert.addButton(withTitle: Strings.text("Cancel")).keyEquivalent = "\u{1b}"
        (alert.informativeText, alert.accessoryView) = (Strings.text("Exporting the slides…"), bar)
        bar.startAnimation(nil)
        alert.beginSheetModal(for: window) { _ in state.perform(.cancelPresentationImport) }
        observer = state.$presentationImport.sink { [self] progress in
            guard let progress else { window.endSheet(alert.window); observer = nil; return }
            alert.messageText = String(format: Strings.text("Importing “%@”"), progress.title)
            guard progress.count > 0 else { return }
            (bar.isIndeterminate, bar.maxValue, bar.doubleValue) = (false, Double(progress.count), Double(progress.slide))
            alert.informativeText = String(format: Strings.text("Importing slide %ld of %ld"), locale: Locale(identifier: Strings.language), progress.slide, progress.count)
        }
    }
}
