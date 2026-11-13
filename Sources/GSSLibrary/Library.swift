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

    /// Writes a valid song atomically: to the file that already holds its `id`, or else to `Songs/<slug>-<8 hex of id>.song.json`.
    @discardableResult
    public func save(_ song: Song) throws -> URL {
        try song.validate()
        let name = "\(Self.slug(song.title))-\(song.id.uuidString.lowercased().prefix(8)).song.json"
        let existing = try songs().songs.first { $0.song.id == song.id }?.url.lastPathComponent
        let url = songsFolder.appendingPathComponent(existing ?? name)
        try song.encoded().write(to: url, options: .atomic)
        return url
    }

    /// Reads every `*.song.json` in `Songs/`, in file name order.
    public func songs() throws -> SongListing {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: songsFolder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
            .filter { $0.lastPathComponent.hasSuffix(".song.json") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var songs: [StoredSong] = [], problems: [(url: URL, error: Error)] = []
        for url in urls {
            do {
                let modified = try url.resourceValues(forKeys: Set(keys)).contentModificationDate ?? .distantPast
                songs.append(StoredSong(url: url, modified: modified, song: try Song.decode(from: Data(contentsOf: url))))
            } catch { problems.append((url, error)) }
        }
        return SongListing(songs: songs, problems: problems)
    }

    /// A file name part for a title: lowercase ASCII letters and digits, accents removed, words joined by `-`,
    /// at most 60 characters, or `song` when nothing is left.
    public static func slug(_ title: String) -> String {
        let words = title.folding(options: .diacriticInsensitive, locale: nil).lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        var slug = String(words.joined(separator: "-").prefix(60))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "song" : slug
    }
}
