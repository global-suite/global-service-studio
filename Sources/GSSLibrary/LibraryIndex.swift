import CryptoKit
import Foundation
import GRDB
import GSSCore

/// A song found by a search.
public struct SongMatch: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let url: URL
}

/// What a reconcile did: the files it read, the entries it removed, and the files it could not read with their error.
public struct ReconcileReport: Sendable {
    public let read: Int
    public let removed: Int
    public let problems: [(url: URL, error: Error)]
}

/// The search index of a library (ADR 0007): a SQLite cache of its song files, kept outside the library folder.
/// It is never migrated: an index of another schema version, or one that is unreadable or corrupted, is deleted and rebuilt from the files.
public final class LibraryIndex: Sendable {
    /// Stored as `PRAGMA user_version`; change it whenever the tables below change.
    public static let schemaVersion = 1
    public let library: Library
    public let url: URL
    private let database: DatabaseQueue

    /// `~/Library/Application Support/GlobalServiceStudio/Index/<library id>.sqlite`.
    public static func defaultURL(for library: Library) throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("GlobalServiceStudio/Index/\(library.id.uuidString.lowercased()).sqlite")
    }

    /// Opens the index of `library` at `url`, or at `defaultURL(for:)`. A new or rebuilt index is empty until `reconcile()`.
    public init(library: Library, at url: URL? = nil) throws {
        let url = try url ?? Self.defaultURL(for: library), files = FileManager.default
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: url.path), !Self.isUsable(url) {
            for suffix in ["", "-wal", "-shm", "-journal"] where files.fileExists(atPath: url.path + suffix) { try files.removeItem(atPath: url.path + suffix) }
        }
        (self.library, self.url, database) = (library, url, try DatabaseQueue(path: url.path))
        // `song` is also the change journal of ADR 0007: content hash, base server version, dirty flag and deleted-at time.
        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS song(file TEXT PRIMARY KEY, id TEXT NOT NULL, title TEXT NOT NULL, size INTEGER NOT NULL,
                  modified DOUBLE NOT NULL, contentHash TEXT NOT NULL, baseServerVersion INTEGER, dirty BOOLEAN NOT NULL DEFAULT 1, deletedAt DOUBLE);
                CREATE VIRTUAL TABLE IF NOT EXISTS songText USING fts5(title, lyrics, authors, ccli,
                  tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3');
                PRAGMA user_version = \(Self.schemaVersion);
                """)
        }
    }

    /// Whether the index at `url` has the current schema version, passes `quick_check` and can open its full-text table.
    private static func isUsable(_ url: URL) -> Bool {
        guard let queue = try? DatabaseQueue(path: url.path) else { return false }
        defer { try? queue.close() }
        return (try? queue.read { db in
            _ = try Row.fetchAll(db, sql: "SELECT rowid FROM songText LIMIT 1")
            return try Int.fetchOne(db, sql: "PRAGMA user_version") == schemaVersion && String.fetchOne(db, sql: "PRAGMA quick_check(1)") == "ok"
        }) ?? false
    }

    /// Brings the index in line with `Songs/`. A file is read only when its size or modification time changed, and re-indexed
    /// only when its content hash changed. Entries of deleted or invalid files leave the search and stay in the journal as deleted.
    @discardableResult
    public func reconcile() throws -> ReconcileReport {
        let urls = try FileManager.default.contentsOfDirectory(at: library.songsFolder, includingPropertiesForKeys: Array(Self.stampKeys), options: .skipsHiddenFiles)
            .filter { $0.lastPathComponent.hasSuffix(".song.json") }
        return try database.write { db in
            var known: [String: Stamp] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT file, size, modified FROM song WHERE deletedAt IS NULL") {
                known[row["file"]] = Stamp(size: row["size"], modified: row["modified"])
            }
            var read = 0, problems: [(url: URL, error: Error)] = []
            for url in urls {
                let stamp = try Self.stamp(of: url)
                if known.removeValue(forKey: url.lastPathComponent) == stamp { continue }
                read += 1
                do { try Self.index(url, stamp: stamp, in: db) } catch {
                    problems.append((url, error))
                    try Self.remove(url.lastPathComponent, in: db)
                }
            }
            for file in known.keys { try Self.remove(file, in: db) }
            return ReconcileReport(read: read, removed: known.count, problems: problems)
        }
    }

    /// Saves a song with `Library.save(_:)` and updates its index entry at once.
    @discardableResult
    public func save(_ song: Song) throws -> URL {
        let url = try library.save(song)
        try database.write { try Self.index(url, stamp: Self.stamp(of: url), in: $0) }
        return url
    }

    /// Songs containing every word of `text` as a word prefix in any field, ignoring case and accents, best first,
    /// with title matches above lyrics, author and CCLI matches. Anything but letters and digits only separates words.
    public func search(_ text: String, limit: Int = 50) throws -> [SongMatch] {
        let terms = text.split { !($0.isLetter || $0.isNumber) }.map { "\"\($0)\"*" }
        guard !terms.isEmpty else { return [] }
        return try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT song.id, song.title, song.file FROM songText JOIN song ON song.rowid = songText.rowid
                WHERE songText MATCH ? ORDER BY bm25(songText, 10.0, 1.0, 2.0, 2.0), song.title LIMIT ?
                """, arguments: [terms.joined(separator: " "), limit]).compactMap { row in
                let id: String = row["id"], file: String = row["file"]
                return UUID(uuidString: id).map { SongMatch(id: $0, title: row["title"], url: library.songsFolder.appendingPathComponent(file)) }
            }
        }
    }

    private struct Stamp: Equatable { let size: Int, modified: Double }
    private static let stampKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]

    private static func stamp(of url: URL) throws -> Stamp {
        let values = try url.resourceValues(forKeys: stampKeys)
        return Stamp(size: values.fileSize ?? 0, modified: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)
    }

    private static func index(_ url: URL, stamp: Stamp, in db: Database) throws {
        let data = try Data(contentsOf: url), file = url.lastPathComponent
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if try String.fetchOne(db, sql: "SELECT contentHash FROM song WHERE file = ? AND deletedAt IS NULL", arguments: [file]) == hash {
            try db.execute(sql: "UPDATE song SET size = ?, modified = ? WHERE file = ?", arguments: [stamp.size, stamp.modified, file])
            return
        }
        let song = try Song.decode(from: data)
        let rowID = try Int64.fetchOne(db, sql: """
            INSERT INTO song(file, id, title, size, modified, contentHash) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(file) DO UPDATE SET id = excluded.id, title = excluded.title, size = excluded.size,
              modified = excluded.modified, contentHash = excluded.contentHash, dirty = 1, deletedAt = NULL
            RETURNING rowid
            """, arguments: [file, song.id.uuidString.lowercased(), song.title, stamp.size, stamp.modified, hash])
        let titles = [song.title] + (song.titles ?? [:]).sorted { $0.key < $1.key }.map(\.value)
        let lyrics = song.sections.flatMap(\.lines).flatMap { $0.text.sorted { $0.key < $1.key }.map(\.value) }
        try db.execute(sql: "DELETE FROM songText WHERE rowid = ?", arguments: [rowID])
        try db.execute(sql: "INSERT INTO songText(rowid, title, lyrics, authors, ccli) VALUES (?, ?, ?, ?, ?)", arguments: [
            rowID, titles.joined(separator: "\n"), lyrics.joined(separator: "\n"),
            (song.authors ?? []).map(\.name).joined(separator: "\n"), song.ccliNumber ?? "",
        ])
    }

    /// Takes a deleted or no longer valid file out of the search; it stays in the journal with its deleted-at time.
    private static func remove(_ file: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM songText WHERE rowid = (SELECT rowid FROM song WHERE file = ?)", arguments: [file])
        try db.execute(sql: "UPDATE song SET deletedAt = ?, dirty = 1 WHERE file = ?", arguments: [Date().timeIntervalSinceReferenceDate, file])
    }
}
