import AppKit
import AVFoundation
import Combine
import GSSCore
import GSSLibrary
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import GSSApp

/// Presentation slides on the audience, key and stage outputs (issue #137); every text and image here is invented.
final class PresentationOutputTests: XCTestCase {
    private let first = MediaReference(path: "Media/Presentations/deck/001.png", sha256: String(repeating: "a", count: 64))
    private let second = MediaReference(path: "Media/Presentations/deck/002.png", sha256: String(repeating: "b", count: 64))
    private let dawn = Song(title: "Dawn Invented", language: "en", sections: [
        SongSection(id: "v1", kind: .verse, number: 1, lines: ["Dawn one", "Dawn two"].map { SongLine(text: ["en": $0]) }),
    ])

    /// Three slides: an image with notes, an image set to stretch with notes, and a text only without notes.
    private var deck: Presentation {
        let frame = ThemeFrame(x: 0, y: 0, width: 1, height: 1)
        let text = PresentationElement(id: "t", kind: .text, slot: "lyrics", text: ["en": "Invented title"])
        return Presentation(title: "Invented Deck", slides: [
            PresentationSlide(id: "s1", elements: [PresentationElement(id: "e", kind: .image, frame: frame, media: first)], notes: "Invented note\nSecond note"),
            PresentationSlide(id: "s2", elements: [PresentationElement(id: "e", kind: .image, frame: frame, media: second, scaling: .stretch)], notes: "Closing note"),
            PresentationSlide(id: "s3", elements: [text]),
        ])
    }
    /// A song with one slide, then the deck: program slides 0 (song), 1, 2 and 3 (deck).
    private func running(library: URL? = nil) -> AppState {
        let deck = deck, state = AppState()
        if let library { state.perform(.chooseLibraryFolder(library)) }
        let items = [PlanItem(id: "dawn", kind: .song, song: dawn.id), PlanItem(id: "deck", kind: .presentation, presentation: deck.id)]
        state.perform(.openPlan(Plan(title: "Invented", items: items), songs: [dawn], presentations: [deck]))
        return state
    }
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PresentationOutputTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    /// A library holding a tiny PNG at the second slide's path.
    private func library() throws -> URL {
        let library = try Library.open(folder()).folder, url = library.appendingPathComponent(second.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return library
    }

    func testScaledRectFitsFillsOrStretchesLandscapeAndPortraitImagesOnA16By9Output() {
        let output = CGSize(width: 1920, height: 1080)
        func rect(_ width: CGFloat, _ height: CGFloat, _ scaling: PresentationImageScaling) -> CGRect {
            PresentationSlideLayer.scaledRect(imageSize: CGSize(width: width, height: height), outputSize: output, scaling: scaling)
        }
        XCTAssertEqual(rect(4000, 2000, .fit), CGRect(x: 0, y: 60, width: 1920, height: 960), "fit leaves bands above and below")
        XCTAssertEqual(rect(4000, 2000, .fill), CGRect(x: -120, y: 0, width: 2160, height: 1080), "fill crops the sides")
        XCTAssertEqual(rect(4000, 2000, .stretch), CGRect(origin: .zero, size: output))
        XCTAssertEqual(rect(1000, 2000, .fit), CGRect(x: 690, y: 0, width: 540, height: 1080), "fit leaves bands at the sides")
        XCTAssertEqual(rect(1000, 2000, .fill), CGRect(x: 0, y: -1380, width: 1920, height: 3840), "fill crops above and below")
        XCTAssertEqual(rect(1000, 2000, .stretch), CGRect(origin: .zero, size: output))
        XCTAssertEqual(rect(3840, 2160, .fit), CGRect(origin: .zero, size: output), "a 16:9 image covers the output")
        XCTAssertEqual(rect(4000, 2000, PresentationImageScaling(rawValue: "blur")), rect(4000, 2000, .fit), "an unknown scaling displays as fit")
    }

    func testAudienceAndKeyDrawTheLinesOfASongAndTheImageOfAPresentationSlide() {
        let state = running()
        state.perform(.goToSlide(0))
        XCTAssertEqual(AudienceOutputView.content(state), .lines(["Dawn one", "Dawn two"]))
        XCTAssertEqual(KeyOutputView.content(state), .lines(["Dawn one", "Dawn two"]))
        state.perform(.nextSlide)
        XCTAssertEqual(AudienceOutputView.content(state), .image(first, .fit), "the audience keeps fit, with transparent bands")
        XCTAssertEqual(KeyOutputView.content(state), .image(first, .fill), "the key shows the slide full frame")
        state.perform(.nextSlide)
        XCTAssertEqual(AudienceOutputView.content(state), .image(second, .stretch))
        XCTAssertEqual(KeyOutputView.content(state), .image(second, .stretch))
        state.perform(.clearSlide)
        XCTAssertEqual(AudienceOutputView.content(state), .lines([]), "Clear Slide hides the image")
        XCTAssertEqual(KeyOutputView.content(state), .lines([]))
        state.perform(.nextSlide)
        XCTAssertEqual(AudienceOutputView.content(state), .lines([]), "a slide without an image draws nothing")
    }

    func testStageShowsTheNotesTheSlideNumberAndTheNextNotes() {
        let state = running()
        state.perform(.goToSlide(0))
        XCTAssertEqual(StageOutputView.next(state), ["Invented note", "Second note"], "a song slide is followed by the next slide's notes")
        XCTAssertNil(StageOutputView.placeholder(state))
        state.perform(.nextSlide)
        XCTAssertEqual(StageOutputView.heading(state), String(format: Strings.text("%1$@ · Slide %2$ld of %3$ld"), "Invented Deck", 1, 3))
        XCTAssertEqual(StageOutputView.lines(state), ["Invented note", "Second note"])
        XCTAssertEqual(StageOutputView.next(state), ["Closing note"])
        XCTAssertNil(StageOutputView.placeholder(state))
        state.perform(.nextSlide)
        XCTAssertEqual(StageOutputView.next(state), ["Invented Deck"], "a next slide without notes shows its title")
        state.perform(.nextSlide)
        XCTAssertEqual(StageOutputView.lines(state), [])
        XCTAssertEqual(StageOutputView.placeholder(state), ["Invented Deck", String(format: Strings.text("Slide %1$ld of %2$ld"), 3, 3), Strings.text("No notes")])
        XCTAssertEqual(StageOutputView.next(state), [Strings.text("End of service")])
        state.perform(.previousSlide)
        state.perform(.clearSlide)
        XCTAssertEqual([StageOutputView.heading(state)], [""])
        XCTAssertEqual(StageOutputView.lines(state), [])
        XCTAssertEqual(StageOutputView.next(state), [])
        XCTAssertNil(StageOutputView.placeholder(state))
    }

    func testAFullScreenVideoHidesTheNotes() throws {
        let state = running(), video = try clip(in: folder())
        state.perform(.goToSlide(1))
        state.perform(.playFullScreen(video))
        let shown = expectation(description: "full-screen video")
        let subscription = state.$fullScreenVideo.first { $0 == video }.sink { _ in shown.fulfill() }
        wait(for: [shown], timeout: 10)
        subscription.cancel()
        XCTAssertEqual(AudienceOutputView.content(state), .lines([]))
        XCTAssertEqual(KeyOutputView.content(state), .lines([]))
        XCTAssertEqual(StageOutputView.heading(state), "")
        XCTAssertEqual(StageOutputView.lines(state), [])
        XCTAssertEqual(StageOutputView.next(state), [])
        XCTAssertNil(StageOutputView.placeholder(state))
        state.perform(.stopVideo)
        XCTAssertEqual(StageOutputView.lines(state), ["Invented note", "Second note"])
    }

    func testTheNextSlidesImageIsPreloadedAtFullSize() throws {
        let library = try library(), state = running(library: library), cache = SlideImageCache()
        state.perform(.goToSlide(1))
        XCTAssertEqual(state.nextProgramSlide?.image, second)
        let controller = AudienceOutputController(state: state, operatorWindow: nil, screens: { [] }, imageCache: cache)
        let decoded = expectation(description: "next image preloaded")
        Task {
            while await cache.decodeCount == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
            let image = await cache.image(for: second, libraryFolder: library)
            XCTAssertEqual(image?.width, 32, "full size")
            let count = await cache.decodeCount
            XCTAssertEqual(count, 1, "the image was decoded once, by the preload")
            decoded.fulfill()
        }
        wait(for: [decoded], timeout: 10)
        withExtendedLifetime(controller) {}
    }

    func testOutputsAndPreviewsLayOutAPresentationSlideAt1920By1080() throws {
        let state = running(library: try library())
        state.perform(.goToSlide(2))
        let views: [AnyView] = [AnyView(AudienceOutputView(state: state)), AnyView(KeyOutputView(state: state)), AnyView(StageOutputView(state: state))]
        for view in views {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertEqual(bitmap.size, NSSize(width: 1920, height: 1080))
        }
        for output in LiveOutput.samples {
            let preview = NSHostingView(rootView: OutputMonitor(output: output, state: state, width: 320))
            preview.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
            preview.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(preview.fittingSize.height, 0)
        }
    }

    func testPresentationStageStringsAreTranslated() {
        let strings = ["%1$@ · Slide %2$ld of %3$ld": "%1$@ · Diapositiva %2$ld de %3$ld", "Slide %1$ld of %2$ld": "Diapositiva %1$ld de %2$ld", "No notes": "Sin notas"]
        for (key, spanish) in strings {
            XCTAssertEqual(Strings.text(key, language: "es"), spanish, key)
            XCTAssertEqual(Strings.text(key, language: "en"), key, key)
        }
    }

    /// A one-second 16 × 16 H.264 clip of gray frames.
    private func clip(in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("film.mp4"), writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            XCTAssertTrue(adaptor.append(try XCTUnwrap(buffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 24)))
        }
        input.markAsFinished()
        let finished = expectation(description: "clip written")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 10)
        return url
    }
}
