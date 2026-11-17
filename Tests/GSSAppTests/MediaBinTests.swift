import AppKit
import GSSLibrary
import ImageIO
import SwiftUI
import XCTest
@testable import GSSApp

final class MediaBinTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GSSMediaBinTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// A state whose library is a new folder inside the test folder.
    private func state() -> AppState {
        let name = "GSSMediaBinTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: name)!
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

    func testOnScreenTextDescribesEachState() throws {
        let state = state(), part = state.liveSlide.position(language: "en")
        XCTAssertEqual(onScreenText(state, language: "en"), "On screen: Lyrics · \(part) · no background (black behind the lyrics)")
        state.perform(.setBackground(.image(try png("Light.png"))))
        XCTAssertEqual(onScreenText(state, language: "en"), "On screen: Lyrics · \(part) · Background: Light (image)")
        state.perform(.clearSlide)
        XCTAssertEqual(onScreenText(state, language: "en"), "On screen: Background: Light (image) · no lyrics (cleared; Next shows them again)")
        state.perform(.clearBackground)
        XCTAssertEqual(onScreenText(state, language: "en"), "On screen: Nothing · the audience screens are black")
        XCTAssertEqual(onScreenText(state, language: "es"), "En pantalla: Nada · las pantallas del público están en negro")
        state.perform(.goToSlide(0))
        state.perform(.setBackground(.color("#0B1F3A")))
        XCTAssertEqual(onScreenText(state, language: "en"), "On screen: Lyrics · \(part) · Background: #0B1F3A (color)")
        XCTAssertEqual(OnScreenLine.videoBackground("Waves", language: "en"), "Background: Waves (video, muted, looping)")
    }

    func testTabsAndBinContent() {
        XCTAssertEqual(DrawerTab.allCases, [.slides, .media])
        XCTAssertEqual(DrawerTab.default, .slides)
        XCTAssertEqual(DrawerTab.allCases.map { $0.title(language: "es") }, ["Diapositivas", "Imágenes y videos"])
        let image = MediaFile(path: "Media/Sunrise.png", kind: .image, byteCount: 1, modified: Date())
        let video = MediaFile(path: "Media/Waves.mov", kind: .video, byteCount: 1, modified: Date())
        XCTAssertEqual(MediaBinContent(files: [], filter: .all, search: ""), .empty)
        XCTAssertEqual(MediaBinContent(files: [image, video], filter: .all, search: ""), .items([image, video]))
        XCTAssertEqual(MediaBinContent(files: [image, video], filter: .videos, search: ""), .items([video]))
        XCTAssertEqual(MediaBinContent(files: [image, video], filter: .all, search: "sun"), .items([image]))
        XCTAssertEqual(MediaBinContent(files: [image, video], filter: .images, search: "waves"), .noMatches)
        XCTAssertEqual(MediaBin.name(of: video), "Waves")
    }

    func testLiveViewLaysOutWithTheMediaTabAtCompactAndWide() throws {
        let state = state()
        for size in [NSSize(width: 1440, height: 900), NSSize(width: 3440, height: 1440)] {
            let view = NSHostingView(rootView: LiveView(state: state, appearance: .standard, tab: .media))
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(view.fittingSize.height, 0)
        }
    }

    func testMediaBinStringsAreTranslated() {
        let keys = ["Slides", "Images & Videos", "All", "Images", "Search media names", "Import…", "No images or videos yet",
                    "Drag your images and videos here, or click Import…", "On screen", "Image", "No images or videos match your search.",
                    "Some files could not be added.", "Importing…"]
        for key in keys {
            XCTAssertNotEqual(Strings.text(key, language: "es"), key, key)
            XCTAssertEqual(Strings.text(key, language: "en"), key, key)
        }
        XCTAssertEqual(Strings.text("Images & Videos", language: "es"), "Imágenes y videos")
        XCTAssertEqual(Strings.text("No images or videos yet", language: "es"), "Todavía no hay imágenes ni videos")
    }
}
