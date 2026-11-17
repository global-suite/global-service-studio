import Foundation
import GSSCore

/// A presentation file of the library, with the time it was last modified.
public struct StoredPresentation: Equatable, Sendable {
    public let url: URL
    public let modified: Date
    public let presentation: Presentation
}

/// The presentations of a library: the valid ones in file name order, and the files that could not be read with their error.
public struct PresentationListing: Sendable {
    public let presentations: [StoredPresentation]
    public let problems: [(url: URL, error: Error)]
}

extension Library {
    public var presentationsFolder: URL { folder.appendingPathComponent("Presentations") }

    /// `Media/Presentations/`: one folder of slide images per imported presentation, outside the media bin's top level.
    private var slideImagesFolder: URL { folder.appendingPathComponent("Media/Presentations") }

    /// Writes a valid presentation atomically to the file found to hold its `id`, or else to
    /// `Presentations/<slug>-<8 hex of id>.presentation.json`. An invalid presentation throws and nothing is written.
    @discardableResult
    public func save(_ presentation: Presentation) throws -> URL {
        try presentation.validate()
        let short = presentation.id.uuidString.lowercased().prefix(8)
        let name = "\(Self.slug(presentation.title, fallback: "presentation"))-\(short).presentation.json"
        let found = try file(holding: presentation.id, in: presentationsFolder, kind: "presentation", expected: name,
                             holdsAnotherID: { _ in false }) { (try? Presentation.decode(from: $0))?.id }
        let url = presentationsFolder.appendingPathComponent(found ?? name)
        try presentation.encoded().write(to: url, options: .atomic)
        return url
    }

    /// Reads and validates the presentation file at `url`.
    public func loadPresentation(at url: URL) throws -> Presentation {
        try Presentation.decode(from: Data(contentsOf: url))
    }

    /// Reads every `*.presentation.json` in `Presentations/`, in file name order.
    public func presentations() throws -> PresentationListing {
        let read = try readAll(in: presentationsFolder, kind: "presentation", decode: Presentation.decode)
        let stored = read.items.map { StoredPresentation(url: $0.url, modified: $0.modified, presentation: $0.item) }
        return PresentationListing(presentations: stored, problems: read.problems)
    }

    /// Sets how every image of the presentation file holding `id` fills the screen, saves the file through `save`, and returns the presentation;
    /// nil when no valid file holds it, with nothing written.
    public func setScaling(_ scaling: PresentationImageScaling, ofPresentation id: UUID) throws -> Presentation? {
        guard let stored = try presentations().presentations.first(where: { $0.presentation.id == id }) else { return nil }
        var edited = stored.presentation
        for slide in edited.slides.indices {
            for element in edited.slides[slide].elements.indices where edited.slides[slide].elements[element].kind == .image {
                edited.slides[slide].elements[element].scaling = scaling
            }
        }
        if edited != stored.presentation { try save(edited) }
        return edited
    }

    /// Writes slide images, in order, as `Media/Presentations/<id>/001.png`, `002.png` and so on, and returns each one's
    /// library-relative path and SHA-256. The images go to a hidden folder first, which then replaces the presentation's
    /// folder, so a re-import leaves no old slides and a failed one leaves the previous images in place.
    public func writeSlideImages(_ images: [Data], for presentationID: UUID) throws -> [MediaReference] {
        let files = FileManager.default, id = presentationID.uuidString.lowercased()
        // Same hidden prefix as the media store's temporaries (`LibraryMedia.swift`, private there).
        let staging = slideImagesFolder.appendingPathComponent(".import-\(UUID().uuidString)")
        let target = slideImagesFolder.appendingPathComponent(id)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            var references: [MediaReference] = []
            for (index, image) in images.enumerated() {
                let name = String(format: "%03d.png", index + 1)
                let url = staging.appendingPathComponent(name)
                try image.write(to: url, options: .atomic)
                references.append(MediaReference(path: "Media/Presentations/\(id)/\(name)", sha256: try Self.sha256(of: url)))
            }
            if files.fileExists(atPath: target.path) {
                _ = try files.replaceItemAt(target, withItemAt: staging)
            } else {
                try files.moveItem(at: staging, to: target)
            }
            return references
        } catch {
            try? files.removeItem(at: staging)
            throw error
        }
    }
}

extension Presentation {
    /// An imported deck (ADR 0010): one slide per image in order, each with one full-frame `image` element scaled to
    /// `fit`, and the slide's speaker notes when `notes` has a non-empty one at its index.
    public static func importedDeck(id: UUID = UUID(), title: String, images: [MediaReference],
                                    notes: [String?] = []) -> Presentation {
        let full = ThemeFrame(x: 0, y: 0, width: 1, height: 1)
        let slides = images.enumerated().map { index, image -> PresentationSlide in
            let note = index < notes.count ? notes[index] : nil
            let element = PresentationElement(id: "e1", kind: .image, frame: full, media: image, scaling: .fit)
            return PresentationSlide(id: "s\(index + 1)", elements: [element], notes: note?.isEmpty == false ? note : nil)
        }
        return Presentation(id: id, title: title, slides: slides)
    }
}
