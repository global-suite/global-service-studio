import CoreGraphics
import GSSCore
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import GSSApp

final class SlideImageCacheTests: XCTestCase {
    private var root: URL!
    private var library: URL { root.appendingPathComponent("Library") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GSSSlideImageCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    /// Writes a tiny PNG of the given size at a path inside the test folder and returns its reference.
    @discardableResult
    private func png(_ path: String, width: Int, height: Int, in folder: URL? = nil) throws -> MediaReference {
        let url = (folder ?? library).appendingPathComponent(path)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return MediaReference(path: path, sha256: "hash-\(path)")
    }

    func testDecodesTheFullImage() async throws {
        let reference = try png("slide.png", width: 40, height: 20)
        let image = await SlideImageCache().image(for: reference, libraryFolder: library)
        XCTAssertEqual(image?.width, 40)
        XCTAssertEqual(image?.height, 20)
    }

    func testDecodesAThumbnailKeepingTheAspectRatio() async throws {
        let reference = try png("slide.png", width: 40, height: 20)
        let image = await SlideImageCache().image(for: reference, libraryFolder: library, maxPixelSize: 10)
        XCTAssertEqual(image?.width, 10)
        XCTAssertEqual(image?.height, 5)
    }

    func testASecondRequestIsACacheHit() async throws {
        let cache = SlideImageCache(), reference = try png("slide.png", width: 8, height: 8)
        let first = await cache.image(for: reference, libraryFolder: library)
        let second = await cache.image(for: reference, libraryFolder: library)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        let count = await cache.decodeCount
        XCTAssertEqual(count, 1)
    }

    func testAnotherHashOrSizeIsAnotherEntry() async throws {
        let cache = SlideImageCache(), reference = try png("slide.png", width: 8, height: 8)
        _ = await cache.image(for: reference, libraryFolder: library)
        let rehashed = await cache.image(for: MediaReference(path: reference.path, sha256: "other"), libraryFolder: library)
        let small = await cache.image(for: reference, libraryFolder: library, maxPixelSize: 4)
        XCTAssertNotNil(rehashed)
        XCTAssertEqual(small?.width, 4)
        let count = await cache.decodeCount
        XCTAssertEqual(count, 3)
    }

    func testEvictsTheLeastRecentlyUsedImageOverTheBudget() async throws {
        let cache = SlideImageCache(pixelBudget: 1_000)
        let a = try png("a.png", width: 20, height: 20), b = try png("b.png", width: 20, height: 20)
        let c = try png("c.png", width: 20, height: 20), huge = try png("huge.png", width: 40, height: 40)
        for reference in [a, b, c, b] { _ = await cache.image(for: reference, libraryFolder: library) }
        var count = await cache.decodeCount
        XCTAssertEqual(count, 3, "a, b and c fit only two at a time; b is still cached")
        _ = await cache.image(for: a, libraryFolder: library)
        _ = await cache.image(for: b, libraryFolder: library)
        count = await cache.decodeCount
        XCTAssertEqual(count, 4, "a was evicted and decoded again, which evicts c and keeps b")
        let first = await cache.image(for: huge, libraryFolder: library)
        let second = await cache.image(for: huge, libraryFolder: library)
        XCTAssertEqual(first?.width, 40)
        XCTAssertNotNil(second)
        count = await cache.decodeCount
        XCTAssertEqual(count, 6, "an image larger than the budget is returned but not cached")
    }

    func testReturnsNilForFilesItCannotUse() async throws {
        let cache = SlideImageCache()
        try png("outside.png", width: 8, height: 8, in: root)
        let inside = try png("inside.png", width: 8, height: 8)
        try Data("not an image".utf8).write(to: library.appendingPathComponent("notes.png"))
        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("link.png"),
                                                   withDestinationURL: root.appendingPathComponent("outside.png"))
        let absolute = library.appendingPathComponent(inside.path).path
        for path in ["missing.png", "../outside.png", "sub/../../outside.png", absolute, "notes.png", "link.png"] {
            let image = await cache.image(for: MediaReference(path: path, sha256: "x"), libraryFolder: library)
            XCTAssertNil(image, path)
        }
    }

    func testConcurrentRequestsShareOneDecode() async throws {
        let cache = SlideImageCache(), reference = try png("slide.png", width: 16, height: 16), library = library
        let images = await withTaskGroup(of: CGImage?.self) { group in
            for _ in 0..<10 { group.addTask { await cache.image(for: reference, libraryFolder: library) } }
            return await group.reduce(into: [CGImage?]()) { $0.append($1) }
        }
        XCTAssertEqual(images.compactMap { $0 }.count, 10)
        let count = await cache.decodeCount
        XCTAssertEqual(count, 1)
    }

    func testPreloadWarmsTheCache() async throws {
        let cache = SlideImageCache(), reference = try png("next.png", width: 8, height: 8)
        await cache.preload(reference, libraryFolder: library, maxPixelSize: 4)
        var count = await cache.decodeCount
        XCTAssertEqual(count, 1, "preload starts the decode")
        let image = await cache.image(for: reference, libraryFolder: library, maxPixelSize: 4)
        XCTAssertEqual(image?.width, 4)
        count = await cache.decodeCount
        XCTAssertEqual(count, 1)
    }
}
