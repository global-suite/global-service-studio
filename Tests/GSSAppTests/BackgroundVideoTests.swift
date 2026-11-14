import AppKit
import AVFoundation
import Combine
import GSSCore
import SwiftUI
import XCTest
@testable import GSSApp

final class BackgroundVideoTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GSSBackgroundVideoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// A 1-second 64 × 36 H.264 clip of gray frames, written with AVAssetWriter.
    private func clip(_ name: String = "loop.mp4") throws -> URL {
        let url = folder.appendingPathComponent(name), size = (width: 64, height: 36)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 10), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 24)))
        }
        input.markAsFinished()
        let finished = expectation(description: "clip written")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 10)
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    /// Waits until the state publishes a background.
    private func waitFor(_ background: Background, in state: AppState) {
        let shown = expectation(description: "background shown")
        let subscription = state.$background.first { $0 == background }.sink { _ in shown.fulfill() }
        wait(for: [shown], timeout: 10)
        subscription.cancel()
    }

    /// Runs the main run loop, so late readiness callbacks can arrive.
    private func spin(_ seconds: TimeInterval = 0.5) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    func testAVideoIsPreparedThenLoopsMutedOnTheAudienceOutputsOnly() throws {
        let state = AppState(), url = try clip()
        state.perform(.setBackground(.video(url)))
        waitFor(.video(url), in: state)
        let video = try XCTUnwrap(state.backgroundVideo)
        XCTAssertEqual(video.player.currentItem?.status, .readyToPlay, "the video is ready before it shows")
        XCTAssertNotNil(video.looper, "the background loops without a gap")
        XCTAssertTrue(video.player.isMuted)
        XCTAssertEqual(video.player.rate, 1, "the video plays once it is live")
        XCTAssertNil(state.backgroundImage)
        XCTAssertEqual(state.mediaFill(for: .audience), .video(video.player))
        XCTAssertNil(state.mediaFill(for: .key), "the key output never shows the media layer")
        XCTAssertNil(state.mediaFill(for: .stage))
        XCTAssertFalse(OutputRole.key.shows(.media))

        let layer = VideoLayerView.PlayerView(player: video.player)
        XCTAssertTrue(layer.playerLayer.player === video.player, "every output shares the one player")
        XCTAssertEqual(layer.playerLayer.videoGravity, .resizeAspectFill)
        for view in [AnyView(AudienceOutputView(state: state)), AnyView(KeyOutputView(state: state)),
                     AnyView(OutputMonitor(output: LiveOutput.samples[0], state: state, width: 320))] {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    func testFilesThatAreNotVideosAreRejectedAndLeaveTheState() throws {
        let state = AppState(), text = folder.appendingPathComponent("notes.mp4")
        try Data("Invented placeholder words".utf8).write(to: text)
        state.perform(.setBackground(.color("#0B1F3A")))
        var published: [Background] = []
        let subscription = state.$background.dropFirst().sink { published.append($0) }
        for invalid in [text, folder.appendingPathComponent("missing.mp4"), folder!, URL(string: "https://example.com/loop.mp4")!] {
            XCTAssertNil(BackgroundVideo(url: invalid), invalid.lastPathComponent)
            state.perform(.setBackground(.video(invalid)))
        }
        spin()
        XCTAssertEqual(state.background, .color("#0B1F3A"))
        XCTAssertNil(state.backgroundVideo)
        XCTAssertEqual(published, [])
        subscription.cancel()
    }

    func testTheSameVideoKeepsItsPlayerAndSlideChangesNeverTouchIt() throws {
        let state = AppState(), url = try clip()
        state.perform(.setBackground(.video(url)))
        waitFor(.video(url), in: state)
        let video = try XCTUnwrap(state.backgroundVideo), player = video.player
        var published = 0
        let subscription = state.$background.dropFirst().sink { _ in published += 1 }
        state.perform(.setBackground(.video(url)))
        state.perform(.nextSlide)
        state.perform(.clearSlide)
        state.perform(.goToSlide(2))
        spin()
        XCTAssertTrue(state.backgroundVideo === video)
        XCTAssertTrue(state.backgroundVideo?.player === player, "setting the same video again never restarts it")
        XCTAssertEqual(player.rate, 1)
        XCTAssertEqual(published, 0)
        subscription.cancel()
    }

    func testAnotherBackgroundOrAClearStopsAndReleasesThePlayer() throws {
        let state = AppState(), url = try clip(), other = try clip("other.mp4")
        for leave in [AppCommand.clearBackground, .clearAll, .setBackground(.color("#000000")), .setBackground(.video(other))] {
            state.perform(.clearBackground)
            state.perform(.setBackground(.video(url)))
            waitFor(.video(url), in: state)
            weak var released = state.backgroundVideo
            let player = try XCTUnwrap(state.backgroundVideo?.player)
            autoreleasepool { state.perform(leave) }
            if case .setBackground(.video) = leave { waitFor(.video(other), in: state) }
            XCTAssertEqual(player.rate, 0, "\(leave) stops the video")
            XCTAssertTrue(player.items().isEmpty)
            XCTAssertNil(released, "\(leave) releases the player")
            XCTAssertNotEqual(state.background, .video(url))
        }
    }

    func testABackgroundChosenWhileAVideoPreparesWins() throws {
        let state = AppState(), url = try clip()
        state.perform(.setBackground(.video(url)))
        state.perform(.setBackground(.color("#2B2B2B")))
        spin(1)
        XCTAssertEqual(state.background, .color("#2B2B2B"))
        XCTAssertNil(state.backgroundVideo)
        state.perform(.setBackground(.video(url)))
        state.perform(.clearBackground)
        spin(1)
        XCTAssertEqual(state.background, .none, "Clear Background cancels a video that is still preparing")
    }

    func testBackgroundMenuChoosesVideos() throws {
        let state = AppState(), url = try clip(), text = folder.appendingPathComponent("notes.txt")
        try Data("Invented placeholder words".utf8).write(to: text)
        var chosen: URL? = text
        let controller = BackgroundMenuController(state: state, chooseImageFile: { nil }, chooseVideoFile: { chosen })
        let item = try XCTUnwrap(controller.menu.items.first { $0.title == Strings.text("Choose Video…") })
        XCTAssertTrue(item.target === controller)
        NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        spin()
        XCTAssertEqual(state.background, .none, "a file that is not a video is ignored")
        chosen = url
        NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        waitFor(.video(url), in: state)
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
        state.perform(.setBackground(.color("#000000")))
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
    }

    func testVideoStringsAreTranslated() {
        XCTAssertEqual(Strings.text("Choose Video…", language: "en"), "Choose Video…")
        XCTAssertEqual(Strings.text("Choose Video…", language: "es"), "Elegir video…")
    }
}
