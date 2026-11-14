import AppKit
import Combine
import GSSCore
import ImageIO
import SwiftUI
import XCTest
@testable import GSSApp

final class BackgroundTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GSSBackgroundTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// A 4 × 2 red PNG made with Core Graphics.
    private func png(_ name: String = "light.png") throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        let url = folder.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testColorBackgroundIsSetByCommandAndInvalidColorsAreIgnored() {
        let state = AppState()
        var published: [Background] = []
        let subscription = state.$background.dropFirst().sink { published.append($0) }
        XCTAssertEqual(state.background, .none)
        for invalid in ["#12345", "blue", "#GGGGGG", "0B1F3A", ""] { state.perform(.setBackground(.color(invalid))) }
        XCTAssertEqual(state.background, .none)
        XCTAssertEqual(published, [])
        state.perform(.setBackground(.color("#0b1f3a")))
        XCTAssertEqual(state.background, .color("#0B1F3A"))
        state.perform(.setBackground(.color("#0B1F3A")))
        state.perform(.setBackground(.color("nope")))
        XCTAssertEqual(state.background, .color("#0B1F3A"))
        XCTAssertNil(state.backgroundImage)
        XCTAssertEqual(published, [.color("#0B1F3A")])
        XCTAssertEqual(state.liveIndex, 0)
        XCTAssertFalse(state.isCleared)
        subscription.cancel()
    }

    func testClearCommandsClearOnlyTheirLayers() {
        let state = AppState()
        state.perform(.setBackground(.color("#2B2B2B")))
        state.perform(.clearSlide)
        XCTAssertTrue(state.isCleared)
        XCTAssertEqual(state.background, .color("#2B2B2B"), "Clear Slide leaves the background")
        state.perform(.goToSlide(2))
        XCTAssertEqual(state.liveIndex, 2)
        XCTAssertFalse(state.isCleared)
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .color("#2B2B2B"), "going to a slide leaves the background")
        var cleared: [Bool] = []
        let subscription = state.$isCleared.dropFirst().sink { cleared.append($0) }
        state.perform(.clearBackground)
        XCTAssertEqual(state.background, .none)
        XCTAssertEqual(state.liveIndex, 3, "Clear Background leaves the slide")
        XCTAssertFalse(state.isCleared)
        state.perform(.setBackground(.color("#000000")))
        state.perform(.clearSlide)
        state.perform(.clearBackground)
        XCTAssertTrue(state.isCleared, "Clear Background never ends a clear")
        XCTAssertEqual(cleared, [true])
        subscription.cancel()

        state.perform(.goToSlide(0))
        state.perform(.setBackground(.color("#000000")))
        state.perform(.clearAll)
        XCTAssertEqual(state.background, .none, "Clear All clears the slide and the background")
        XCTAssertTrue(state.isCleared)
        XCTAssertEqual(state.liveIndex, 0)
    }

    func testClearingWithoutABackgroundPublishesNothing() {
        let state = AppState()
        var published = 0
        let subscription = state.$background.dropFirst().sink { _ in published += 1 }
        state.perform(.clearBackground)
        state.perform(.setBackground(.none))
        XCTAssertEqual(published, 0)
        XCTAssertFalse(state.isCleared)
        subscription.cancel()
    }

    func testImageBackgroundIsDecodedWhenSetAndNonImagesAreIgnored() throws {
        let state = AppState()
        let text = folder.appendingPathComponent("notes.png")
        try Data("Invented placeholder words".utf8).write(to: text)
        state.perform(.setBackground(.color("#0B1F3A")))
        for invalid in [text, folder.appendingPathComponent("missing.png"), folder!] { state.perform(.setBackground(.image(invalid))) }
        XCTAssertEqual(state.background, .color("#0B1F3A"), "a file that is not a readable image is ignored")
        XCTAssertNil(state.backgroundImage)

        let image = try png()
        XCTAssertNil(BackgroundImageLoader.image(at: text))
        XCTAssertEqual(BackgroundImageLoader.image(at: image).map { [$0.width, $0.height] }, [4, 2])
        state.perform(.setBackground(.image(image)))
        XCTAssertEqual(state.background, .image(image))
        XCTAssertEqual(state.backgroundImage.map { [$0.width, $0.height] }, [4, 2], "the image is decoded when the command is applied")
        state.perform(.setBackground(.image(text)))
        XCTAssertEqual(state.background, .image(image))
        state.perform(.setBackground(.color("#000000")))
        XCTAssertNil(state.backgroundImage)
        state.perform(.setBackground(.image(image)))
        state.perform(.clearBackground)
        XCTAssertEqual(state.background, .none)
        XCTAssertNil(state.backgroundImage)
    }

    func testAudienceOutputsShowTheBackgroundAndTheKeyOutputNever() throws {
        let state = AppState()
        for role in OutputRole.allCases { XCTAssertNil(state.mediaFill(for: role)) }
        state.perform(.setBackground(.color("#0B1F3A")))
        XCTAssertEqual(state.mediaFill(for: .audience), .color(RGBA(hex: 0x0B1F3A)))
        XCTAssertNil(state.mediaFill(for: .key), "the key output never shows the media layer")
        XCTAssertNil(state.mediaFill(for: .stage))
        state.perform(.setBackground(.image(try png())))
        let image = try XCTUnwrap(state.backgroundImage)
        XCTAssertEqual(state.mediaFill(for: .audience), .image(image))
        XCTAssertNil(state.mediaFill(for: .key))
        state.perform(.clearSlide)
        XCTAssertEqual(state.mediaFill(for: .audience), .image(image), "the background stays while the slide is cleared")
        XCTAssertEqual(AudienceOutputView.lines(state), [])

        for view in [AnyView(AudienceOutputView(state: state)), AnyView(KeyOutputView(state: state)),
                     AnyView(OutputMonitor(output: LiveOutput.samples[0], state: state, width: 320)), AnyView(ClearActions(state: state, stacked: false))] {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    func testBackgroundMenuChoosesImagesPresetsAndClears() throws {
        let state = AppState(), image = try png(), text = folder.appendingPathComponent("notes.txt")
        try Data("Invented placeholder words".utf8).write(to: text)
        var chosen: URL? = image
        let controller = BackgroundMenuController(state: state, chooseImageFile: { chosen })
        let menu = controller.menu
        XCTAssertEqual(menu.title, Strings.text("Background"))
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, ["Choose Image…", "Choose Video…", "Black", "Dark Blue", "Dark Gray", "Clear Background"].map { Strings.text($0) })
        func item(_ title: String) throws -> NSMenuItem { try XCTUnwrap(menu.items.first { $0.title == Strings.text(title) }) }
        func click(_ title: String) throws {
            let item = try item(title)
            XCTAssertTrue(item.target === controller)
            NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        }

        XCTAssertFalse(controller.validateMenuItem(try item("Clear Background")), "Clear Background needs a background")
        try click("Dark Blue")
        XCTAssertEqual(state.background, .color("#0B1F3A"))
        XCTAssertTrue(controller.validateMenuItem(try item("Dark Blue")))
        XCTAssertEqual(try item("Dark Blue").state, .on)
        XCTAssertTrue(controller.validateMenuItem(try item("Black")))
        XCTAssertEqual(try item("Black").state, .off)
        try click("Choose Image…")
        XCTAssertEqual(state.background, .image(image))
        chosen = text
        try click("Choose Image…")
        XCTAssertEqual(state.background, .image(image), "a file that is not an image is ignored")
        chosen = nil
        try click("Choose Image…")
        XCTAssertEqual(state.background, .image(image), "cancelling the panel keeps the background")
        XCTAssertTrue(controller.validateMenuItem(try item("Clear Background")))
        try click("Clear Background")
        XCTAssertEqual(state.background, .none)
        XCTAssertFalse(state.isCleared)

        let audience = NSMenu(title: "A"), key = NSMenu(title: "K")
        let output = OutputMenu.make(audience: audience, key: key, background: menu)
        XCTAssertEqual(output.items.compactMap(\.submenu), [audience, key, menu])
        XCTAssertEqual(output.items.last?.title, menu.title)
    }

    func testBackgroundStringsAreTranslated() {
        for key in ["Background", "Choose Image…", "Black", "Dark Blue", "Dark Gray", "Clear Background"] {
            XCTAssertNotEqual(Strings.text(key, language: "es"), key, key)
            XCTAssertEqual(Strings.text(key, language: "en"), key, key)
        }
        XCTAssertEqual(["Background", "Choose Image…", "Black", "Dark Blue", "Dark Gray"].map { Strings.text($0, language: "es") },
                       ["Fondo", "Elegir imagen…", "Negro", "Azul oscuro", "Gris oscuro"])
    }
}
