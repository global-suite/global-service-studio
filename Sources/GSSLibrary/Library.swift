import Foundation
import GSSCore

/// Why a folder cannot be used as a library, besides a `FormatError` in its `library.json`.
public enum LibraryError: Error, Equatable, Sendable {
    /// The folder has files but no `library.json`; it is not made into a library.
    case folderNotEmpty
}

/// A song file of the library, with the time it was last modified.
public struct StoredSong: Equatable, Sendable {
    public let url: URL
    public let modified: Date
    public let song: Song
}

/// The songs of a library: the valid ones, and the files that could not be read with their error.
public struct SongListing: Sendable {
    public let songs: [StoredSong]
    public let problems: [(url: URL, error: Error)]
    /// The most recently modified song, if any.
    public var mostRecent: StoredSong? { songs.max { $0.modified < $1.modified } }
}

/// A library folder (ADR 0007): `library.json` and one folder per kind of item. Files are the source of truth.
public struct Library: Equatable, Sendable {
    public static let format = "gss.library"
    public static let supportedVersion = 1
    public static let folders = ["Songs", "Themes", "Presentations", "Plans", "Media"]

    public let folder: URL
    public let id: UUID
    public let name: String
    public var songsFolder: URL { folder.appendingPathComponent("Songs") }

    /// Whether `folder` has a `library.json`; reads nothing else and creates nothing.
    public static func exists(at folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("library.json").path)
    }

    /// Opens a library, creating `library.json` and the item folders in a missing or empty folder.
    /// A `library.json` of another format or a newer version, or a non-empty folder without one, throws and nothing is written.
    public static func open(_ folder: URL) throws -> Library {
        let files = FileManager.default, manifest = folder.appendingPathComponent("library.json")
        let library: Library
        if files.fileExists(atPath: manifest.path) {
            var (id, reader) = try Envelope.open(Data(contentsOf: manifest), format: format, supportedVersion: supportedVersion)
            library = Library(folder: folder, id: id, name: try reader.required("name"))
        } else {
            if files.fileExists(atPath: folder.path), try !files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).isEmpty {
                throw LibraryError.folderNotEmpty
            }
            library = Library(folder: folder, id: UUID(), name: folder.lastPathComponent)
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let fields = Envelope.fields(format: format, version: supportedVersion, id: library.id).merging(["name": .string(library.name)]) { $1 }
            try JSONValue.object(fields, unknown: [:]).canonicalData().write(to: manifest, options: .atomic)
        }
        for name in folders { try files.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true) }
        return library
    }

    /// Writes a valid song atomically: to `existingFile` when the caller knows the file that holds its `id`, else to the file
    /// found to hold its `id`, or else to `Songs/<slug>-<8 hex of id>.song.json`.
    @discardableResult
    public func save(_ song: Song, existingFile: URL? = nil) throws -> URL {
        try save(song, existingFile: existingFile) { _ in false }
    }

    /// `save(_:existingFile:)`; when searching, files whose name `holdsAnotherID` accepts are not read.
    func save(_ song: Song, existingFile: URL?, holdsAnotherID: (String) -> Bool) throws -> URL {
        try song.validate()
        let name = "\(Self.slug(song.title))-\(song.id.uuidString.lowercased().prefix(8)).song.json"
        let found = existingFile == nil ? try file(holding: song.id, in: songsFolder, kind: "song", expected: name,
                                                   holdsAnotherID: holdsAnotherID) { (try? Song.decode(from: $0))?.id } : nil
        let url = existingFile ?? songsFolder.appendingPathComponent(found ?? name)
        try song.encoded().write(to: url, options: .atomic)
        return url
    }

    /// The name of the file in `folder` ending in `.<kind>.json` whose `read` gives `id`. Reads first the expected name, then
    /// names ending in the same short id, and only then every other file in name order, so a file renamed outside the app is found.
    func file(holding id: UUID, in folder: URL, kind: String, expected: String, holdsAnotherID: (String) -> Bool,
              read: (Data) -> UUID?) throws -> String? {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { !$0.hasPrefix(".") && $0.hasSuffix(".\(kind).json") }.sorted()
        let suffix = "-\(id.uuidString.lowercased().prefix(8)).\(kind).json"
        let likely = names.filter { $0 == expected } + names.filter { $0 != expected && $0.hasSuffix(suffix) }
        let rest = names.filter { !$0.hasSuffix(suffix) && !holdsAnotherID($0) }
        for name in likely + rest {
            let data = try? Data(contentsOf: folder.appendingPathComponent(name))
            if let data, read(data) == id { return name }
        }
        return nil
    }

    /// Every `*.<kind>.json` in `folder`, in file name order, decoded with its modification time, and the files that failed.
    func readAll<Item>(in folder: URL, kind: String, decode: (Data) throws -> Item)
        throws -> (items: [(url: URL, modified: Date, item: Item)], problems: [(url: URL, error: Error)]) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
            .filter { $0.lastPathComponent.hasSuffix(".\(kind).json") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var items: [(url: URL, modified: Date, item: Item)] = [], problems: [(url: URL, error: Error)] = []
        for url in urls {
            do {
                let modified = try url.resourceValues(forKeys: Set(keys)).contentModificationDate ?? .distantPast
                items.append((url, modified, try decode(Data(contentsOf: url))))
            } catch { problems.append((url, error)) }
        }
        return (items, problems)
    }

    /// Reads every `*.song.json` in `Songs/`, in file name order.
    public func songs() throws -> SongListing {
        let read = try readAll(in: songsFolder, kind: "song", decode: Song.decode)
        return SongListing(songs: read.items.map { StoredSong(url: $0.url, modified: $0.modified, song: $0.item) }, problems: read.problems)
    }

    /// A file name part for a title: lowercase ASCII letters and digits, accents removed, words joined by `-`,
    /// at most 60 characters, or `song` when nothing is left.
    public static func slug(_ title: String) -> String { slug(title, fallback: "song") }

    /// `slug(_:)` with another word for a title with no letters or digits.
    static func slug(_ title: String, fallback: String) -> String {
        let words = title.folding(options: .diacriticInsensitive, locale: nil).lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        var slug = String(words.joined(separator: "-").prefix(60))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? fallback : slug
    }
}
