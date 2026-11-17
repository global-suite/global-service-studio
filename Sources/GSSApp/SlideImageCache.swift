import CoreGraphics
import Foundation
import GSSCore
import ImageIO

/// Decodes slide images off the render path, before they go live, and keeps them by path, hash and size.
/// Concurrent requests for the same image share one decode. The least recently used images leave first once the
/// decoded pixels pass the budget; an image larger than the whole budget is returned but never kept.
actor SlideImageCache {
    static let shared = SlideImageCache()
    /// About 400 million pixels, roughly 1.6 GB as BGRA: some 48 full 4K slides, or several presentations at 1080p.
    static let defaultPixelBudget = 400_000_000

    private struct Key: Hashable {
        let path, sha256: String
        let maxPixelSize: Int?
    }

    private struct Entry {
        let image: CGImage
        var lastUse: UInt64
        var pixels: Int { image.width * image.height }
    }

    private let pixelBudget: Int
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<CGImage?, Never>] = [:]
    private var totalPixels = 0, useClock: UInt64 = 0
    /// How many decodes have started; for tests.
    private(set) var decodeCount = 0

    init(pixelBudget: Int = SlideImageCache.defaultPixelBudget) { self.pixelBudget = pixelBudget }

    /// The decoded image of a library file, scaled so its longest side is at most `maxPixelSize` when given;
    /// nil when the path leaves the library, or the file is missing or not an image.
    func image(for reference: MediaReference, libraryFolder: URL, maxPixelSize: Int? = nil) async -> CGImage? {
        let key = Key(path: reference.path, sha256: reference.sha256, maxPixelSize: maxPixelSize)
        if let cached = touch(key) { return cached }
        return await load(key, reference: reference, libraryFolder: libraryFolder)?.value
    }

    /// Starts decoding an image, such as the next slide's, without waiting for it.
    func preload(_ reference: MediaReference, libraryFolder: URL, maxPixelSize: Int? = nil) {
        let key = Key(path: reference.path, sha256: reference.sha256, maxPixelSize: maxPixelSize)
        if touch(key) == nil { _ = load(key, reference: reference, libraryFolder: libraryFolder) }
    }

    /// The cached image for a key, marked as just used.
    private func touch(_ key: Key) -> CGImage? {
        guard var entry = entries[key] else { return nil }
        useClock += 1
        entry.lastUse = useClock
        entries[key] = entry
        return entry.image
    }

    /// The decode in flight for a key, started now when there is none; nil when the path leaves the library.
    private func load(_ key: Key, reference: MediaReference, libraryFolder: URL) -> Task<CGImage?, Never>? {
        if let running = inFlight[key] { return running }
        guard let url = Self.fileURL(of: reference, in: libraryFolder) else { return nil }
        decodeCount += 1
        let task = Task {
            let image = await Task.detached(priority: .userInitiated) { Self.decode(url, maxPixelSize: key.maxPixelSize) }.value
            self.finish(key, image)
            return image
        }
        inFlight[key] = task
        return task
    }

    /// Keeps a decoded image, then evicts the least recently used ones until the budget holds.
    private func finish(_ key: Key, _ image: CGImage?) {
        inFlight[key] = nil
        guard let image, image.width * image.height <= pixelBudget else { return }
        useClock += 1
        entries[key] = Entry(image: image, lastUse: useClock)
        totalPixels += image.width * image.height
        while totalPixels > pixelBudget, let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            entries[oldest.key] = nil
            totalPixels -= oldest.value.pixels
        }
    }

    /// The file of a reference inside the library folder, symbolic links resolved; nil when it would leave the folder.
    static func fileURL(of reference: MediaReference, in libraryFolder: URL) -> URL? {
        guard reference.hasLibraryRelativePath else { return nil }
        let root = libraryFolder.standardizedFileURL.resolvingSymlinksInPath().path
        let url = libraryFolder.appendingPathComponent(reference.path).standardizedFileURL.resolvingSymlinksInPath()
        return url.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") ? url : nil
    }

    /// Decodes an image file with ImageIO: a thumbnail with orientation applied when `maxPixelSize` is given, else the full image.
    static func decode(_ url: URL, maxPixelSize: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0 else { return nil }
        guard let maxPixelSize else {
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize, kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
