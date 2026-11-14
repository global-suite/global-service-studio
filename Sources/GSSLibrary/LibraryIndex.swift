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
        if files.fileExists(atPath: url.path), try !Self.isUsable(url) {
            for suffix in ["", "-wal", "-shm", "-journal"] where files.fileExists(atPath: url.path + suffix) { try files.removeItem(atPath: url.path + suffix) }
        }
        (self.library, self.url, database) = (library, url, try DatabaseQueue(path: url.path, configuration: Self.configuration))
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

    /// Another connection that holds the index locked is waited for, up to 5 seconds, instead of failing at once.
    private static let configuration = { var configuration = Configuration(); configuration.busyMode = .timeout(5); return configuration }()

    /// Whether the index at `url` has the current schema version, passes `quick_check` and can open its full-text table.
    /// An index still locked by another connection throws instead, so it is never deleted for being busy.
    private static func isUsable(_ url: URL) throws -> Bool {
        do {
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            defer { try? queue.close() }
            return try queue.read { db in
                _ = try Row.fetchAll(db, sql: "SELECT rowid FROM songText LIMIT 1")
                return try Int.fetchOne(db, sql: "PRAGMA user_version") == schemaVersion && String.fetchOne(db, sql: "PRAGMA quick_check(1)") == "ok"
            }
        } catch let error as DatabaseError where [.SQLITE_BUSY, .SQLITE_LOCKED].contains(error.resultCode) {
            throw error
        } catch { return false }
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

    /// Saves a song with `Library.save(_:existingFile:)` and updates its index entry at once. The file that holds the song's
    /// `id` is taken from the index when it still exists; otherwise files the index knows unchanged with another `id` are not read.
    @discardableResult
    public func save(_ song: Song) throws -> URL {
        let id = song.id.uuidString.lowercased()
        let known = try database.read { db in
            try String.fetchAll(db, sql: "SELECT file FROM song WHERE id = ? AND deletedAt IS NULL ORDER BY file", arguments: [id])
        }
        let existing = known.map { library.songsFolder.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        var others: [String: Stamp] = [:]
        if existing == nil {
            others = try database.read { db in
                let rows = try Row.fetchCursor(db, sql: "SELECT file, size, modified FROM song WHERE id != ? AND deletedAt IS NULL", arguments: [id])
                var stamps: [String: Stamp] = [:]
                while let row = try rows.next() { stamps[row[0]] = Stamp(size: row[1], modified: row[2]) }
                return stamps
            }
        }
        let folder = library.songsFolder.path + "/"
        let url = try library.save(song, existingFile: existing) { name in
            guard let stamp = others[name], let now = Self.quickStamp(of: folder + name) else { return false }
            return now.size == stamp.size && abs(now.modified - stamp.modified) < 0.000_001
        }
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
                """, arguments: [terms.joined(separator: " "), limit]).compactMap(match)
        }
    }

    /// Every indexed song, sorted by title ignoring case and accents.
    public func allSongs() throws -> [SongMatch] {
        let songs = try database.read { try Row.fetchAll($0, sql: "SELECT id, title, file FROM song WHERE deletedAt IS NULL") }.compactMap(match)
        return songs.sorted { first, second in
            let order = first.title.compare(second.title, options: [.caseInsensitive, .diacriticInsensitive])
            return order == .orderedSame ? first.url.lastPathComponent < second.url.lastPathComponent : order == .orderedAscending
        }
    }

    /// The indexed files that held the song `id` when they were indexed, in file name order.
    func files(holding id: UUID) throws -> [URL] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT file FROM song WHERE id = ? AND deletedAt IS NULL ORDER BY file",
                                arguments: [id.uuidString.lowercased()])
        }.map { library.songsFolder.appendingPathComponent($0) }
    }

    /// The indexed files whose song `id` another indexed file also holds, in file name order.
    public func filesWithDuplicateIDs() throws -> [URL] {
        try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT file FROM song WHERE deletedAt IS NULL AND id IN
                  (SELECT id FROM song WHERE deletedAt IS NULL GROUP BY id HAVING count(*) > 1) ORDER BY file
                """)
        }.map { library.songsFolder.appendingPathComponent($0) }
    }

    private func match(_ row: Row) -> SongMatch? {
        let id: String = row["id"], file: String = row["file"]
        return UUID(uuidString: id).map { SongMatch(id: $0, title: row["title"], url: library.songsFolder.appendingPathComponent(file)) }
    }

    private struct Stamp: Equatable { let size: Int, modified: Double }
    private static let stampKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]

    private static func stamp(of url: URL) throws -> Stamp {
        let values = try url.resourceValues(forKeys: stampKeys)
        return Stamp(size: values.fileSize ?? 0, modified: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)
    }

    /// Size and modification time from `stat`: much cheaper than `stamp(of:)` when many files are checked.
    private static func quickStamp(of path: String) -> Stamp? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let time = info.st_mtimespec
        let seconds = Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000 - Date.timeIntervalBetween1970AndReferenceDate
        return Stamp(size: Int(info.st_size), modified: seconds)
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
