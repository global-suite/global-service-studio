import Combine
import GSSLibrary
import ImageIO
import XCTest
@testable import GSSApp

final class MediaLibraryStateTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GSSMediaLibraryStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// A state whose library is a new folder inside the test folder.
    private func state() -> AppState {
        let name = "GSSMediaLibraryStateTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.libraryFolder = folder.appendingPathComponent("Library")
        return AppState(settings: settings)
    }

    /// A 4 × 2 red PNG made with Core Graphics.
    private func png(_ name: String, in directory: URL? = nil) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        let url = (directory ?? folder).appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// Waits until the state publishes media files that pass a test.
    private func waitForMedia(_ state: AppState, _ test: @escaping ([MediaFile]) -> Bool) {
        let loaded = expectation(description: "media listed")
        let subscription = state.$mediaFiles.first(where: test).sink { _ in loaded.fulfill() }
        wait(for: [loaded], timeout: 10)
        subscription.cancel()
    }

    func testMediaFilesLoadFromTheLibraryAndAMissingLibraryListsNothing() throws {
        let state = state()
        state.perform(.loadMedia)
        waitForMedia(state) { $0.isEmpty }
        let library = try Library.open(state.libraryFolder)
        let media = library.folder.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        _ = try png("Sunrise.png", in: media)
        try Data([0, 0, 0, 1]).write(to: media.appendingPathComponent("Waves.mov"))
        state.perform(.loadMedia)
        waitForMedia(state) { !$0.isEmpty }
        XCTAssertEqual(state.mediaFiles.map(\.path), ["Media/Sunrise.png", "Media/Waves.mov"])
        XCTAssertEqual(state.mediaFiles.map(\.kind), [.image, .video])
    }

    func testImportAddsGoodFilesAndOneAlertNamesTheRefusedOnes() throws {
        let state = state()
        let good = try png("Light.png"), refused = folder.appendingPathComponent("notes.txt")
        try Data("not media".utf8).write(to: refused)
        state.perform(.importMedia([refused, good]))
        waitForMedia(state) { !$0.isEmpty }
        XCTAssertEqual(state.mediaFiles.map(\.path), ["Media/Light.png"])
        XCTAssertEqual(state.alert?.title, Strings.text("Some files could not be added."))
        XCTAssertTrue(state.alert?.message.contains("notes.txt") == true)
        XCTAssertFalse(state.alert?.message.contains("Light.png") == true)
        XCTAssertFalse(state.isImportingMedia)
    }

    func testChoosingAnItemSetsTheBackgroundWithTheLibraryFile() throws {
        let state = state()
        state.perform(.importMedia([try png("Light.png")]))
        waitForMedia(state) { !$0.isEmpty }
        let file = try XCTUnwrap(state.mediaFiles.first)
        let url = state.libraryFolder.appendingPathComponent("Media/Light.png")
        XCTAssertEqual(state.background(for: file), .image(url))
        XCTAssertFalse(state.isOnAir(file))
        state.perform(.setBackground(state.background(for: file)))
        XCTAssertEqual(state.background, .image(url))
        XCTAssertNotNil(state.backgroundImage)
        XCTAssertTrue(state.isOnAir(file))
        let video = MediaFile(path: "Media/Waves.mov", kind: .video, byteCount: 1, modified: Date())
        XCTAssertEqual(state.background(for: video), .video(state.libraryFolder.appendingPathComponent("Media/Waves.mov")))
    }

    func testThumbnailsReadSizeOffTheMainThread() async throws {
        let url = try png("Light.png")
        let preview = await MediaThumbnails.shared.preview(of: url, kind: .image, modified: Date())
        XCTAssertEqual(preview.pixelSize, CGSize(width: 4, height: 2))
        XCTAssertNotNil(preview.image)
        XCTAssertEqual(MediaThumbnails.caption(kind: .video, preview: MediaPreview(image: nil, pixelSize: CGSize(width: 1920, height: 1080), duration: 42), language: "en"),
                       "Video · 0:42 · 1920 × 1080")
        XCTAssertEqual(MediaThumbnails.caption(kind: .image, preview: nil, language: "es"), "Imagen")
    }

    func testMediaLibraryStringsAreTranslated() {
        for key in ["Some files could not be added.", "Image"] {
            XCTAssertNotEqual(Strings.text(key, language: "es"), key, key)
            XCTAssertEqual(Strings.text(key, language: "en"), key, key)
        }
    }
}
