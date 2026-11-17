import CryptoKit
import Foundation
import GSSCore
import UniformTypeIdentifiers

/// Why a file cannot be imported into the library's `Media/` folder.
public enum LibraryMediaError: Error, Equatable, Sendable {
    /// The file's type, judged by its extension, is not an image or a video.
    case notMedia
    /// The file could not be opened or read.
    case unreadable
}

/// An image or video in the library's `Media/` folder.
public struct MediaFile: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case image, video }

    /// Library-relative path, such as `Media/Sunrise.png`.
    public let path: String
    public let kind: Kind
    public let byteCount: Int
    public let modified: Date

    public init(path: String, kind: Kind, byteCount: Int, modified: Date) {
        (self.path, self.kind, self.byteCount, self.modified) = (path, kind, byteCount, modified)
    }

    /// The kind of a file name by its extension, or nil when it is neither an image nor a video.
    static func kind(ofName name: String) -> Kind? {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        return nil
    }
}

extension Library {
    private static let mediaFolderName = "Media"
    private static let temporaryPrefix = ".import-"
    private static let hashChunkSize = 1 << 20

    private var mediaDirectory: URL { folder.appendingPathComponent(Self.mediaFolderName) }

    /// Copies an image or video into `Media/` and returns its library-relative path and SHA-256.
    /// A file in `Media/` with the same content is returned instead of copying again. A name taken by different content
    /// gets " 2", " 3" and so on before the extension. The copy goes to a hidden temporary name first and is then renamed,
    /// so a failed import leaves no partial file.
    public func importMedia(_ file: URL) throws -> MediaReference {
        guard MediaFile.kind(ofName: file.lastPathComponent) != nil else { throw LibraryMediaError.notMedia }
        let files = FileManager.default
        let (hash, size): (String, Int)
        do {
            size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            hash = try Self.sha256(of: file)
        } catch { throw LibraryMediaError.unreadable }

        try files.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        if let existing = try existingMedia(size: size, sha256: hash) {
            return MediaReference(path: "\(Self.mediaFolderName)/\(existing)", sha256: hash)
        }

        let temporary = mediaDirectory.appendingPathComponent("\(Self.temporaryPrefix)\(UUID().uuidString).tmp")
        do { try files.copyItem(at: file, to: temporary) } catch {
            try? files.removeItem(at: temporary)
            throw LibraryMediaError.unreadable
        }
        do {
            let name = try moveToFreeName(temporary, preferred: Self.importName(file.lastPathComponent))
            return MediaReference(path: "\(Self.mediaFolderName)/\(name)", sha256: hash)
        } catch {
            try? files.removeItem(at: temporary)
            throw error
        }
    }

    /// The images and videos in `Media/`, sorted by name as Finder does. Hidden files, temporaries, folders and other
    /// files are left out. Hashes are not computed here.
    public func media() throws -> [MediaFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard FileManager.default.fileExists(atPath: mediaDirectory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: keys,
                                                               options: .skipsHiddenFiles)
        var listed: [MediaFile] = []
        for url in urls {
            let name = url.lastPathComponent
            guard !name.hasPrefix("."), let kind = MediaFile.kind(ofName: name) else { continue }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            listed.append(MediaFile(path: "\(Self.mediaFolderName)/\(name)", kind: kind, byteCount: values.fileSize ?? 0,
                                    modified: values.contentModificationDate ?? .distantPast))
        }
        return listed.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The name of a media file with `size` bytes whose SHA-256 is `sha256`, if any. Only files of the same size are hashed.
    private func existingMedia(size: Int, sha256: String) throws -> String? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: keys,
                                                               options: .skipsHiddenFiles)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urls where MediaFile.kind(ofName: url.lastPathComponent) != nil {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  values.fileSize == size, (try? Self.sha256(of: url)) == sha256 else { continue }
            return url.lastPathComponent
        }
        return nil
    }

    /// Renames `temporary` to `preferred`, or to "<stem> 2.<ext>", "<stem> 3.<ext>" and so on, never replacing a file.
    private func moveToFreeName(_ temporary: URL, preferred: String) throws -> String {
        let files = FileManager.default
        let stem = (preferred as NSString).deletingPathExtension, ext = (preferred as NSString).pathExtension
        var number = 1
        while true {
            let name = number == 1 ? preferred : (ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
            let target = mediaDirectory.appendingPathComponent(name)
            if !files.fileExists(atPath: target.path) {
                do {
                    try files.moveItem(at: temporary, to: target)
                    return name
                } catch CocoaError.fileWriteFileExists {
                    // Taken between the check and the move; try the next number.
                }
            }
            number += 1
        }
    }

    /// The source name without leading dots, so the copy is not hidden.
    private static func importName(_ name: String) -> String {
        let trimmed = String(name.drop { $0 == "." })
        return trimmed.isEmpty ? "media" : trimmed
    }

    /// The lowercase hex SHA-256 of a file, read in chunks so large videos are not loaded whole.
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: hashChunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
