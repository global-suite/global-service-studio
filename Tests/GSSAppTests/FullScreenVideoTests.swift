import AppKit
import AVFoundation
import Combine
import SwiftUI
import XCTest
@testable import GSSApp

final class FullScreenVideoTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GSSFullScreenVideoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    /// A 64 × 36 H.264 clip of gray frames, 24 frames per second, written with AVAssetWriter; an existing one is reused.
    private func clip(_ name: String = "film.mp4", frames: Int = 24) throws -> URL {
        let url = folder.appendingPathComponent(name), size = (width: 64, height: 36)
        if FileManager.default.fileExists(atPath: url.path) { return url }
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
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 10 % 255), CVPixelBufferGetDataSize(pixels))
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

    /// Waits until the state publishes a full-screen video, or none.
    private func waitFor(_ video: URL?, in state: AppState, timeout: TimeInterval = 10) {
        let shown = expectation(description: "full-screen video \(video?.lastPathComponent ?? "none")")
        let subscription = state.$fullScreenVideo.first { $0 == video }.sink { _ in shown.fulfill() }
        wait(for: [shown], timeout: timeout)
        subscription.cancel()
    }

    private func spin(_ seconds: TimeInterval = 0.5) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// A state with a long clip playing full screen over a video background.
    private func playing(frames: Int = 24 * 30) throws -> (AppState, URL, URL) {
        let state = AppState(), background = try clip("loop.mp4"), film = try clip(frames: frames)
        state.perform(.setBackground(.video(background)))
        let shown = expectation(description: "background")
        let subscription = state.$background.first { $0 == .video(background) }.sink { _ in shown.fulfill() }
        wait(for: [shown], timeout: 10)
        subscription.cancel()
        state.perform(.playFullScreen(film))
        waitFor(film, in: state)
        return (state, background, film)
    }

    func testPlayingHidesTheLyricsPausesTheBackgroundAndStopBringsThemBack() throws {
        let (state, background, film) = try playing()
        let lines = state.liveSlide.lines, backgroundPlayer = try XCTUnwrap(state.backgroundVideo?.player)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertEqual(state.shownLines, [], "the lyrics hide while the video plays")
        XCTAssertFalse(state.isCleared, "playing a video is not a clear")
        XCTAssertEqual(state.programIndex, 0)
        XCTAssertEqual(backgroundPlayer.rate, 0, "the background waits, paused")
        let player = try XCTUnwrap(state.fullScreenPlayer?.player)
        XCTAssertFalse(player.isMuted, "a full-screen video plays with sound")
        XCTAssertEqual(player.rate, 1)
        XCTAssertEqual(state.mediaFill(for: .audience), .fullScreenVideo(player))
        XCTAssertNil(state.mediaFill(for: .key), "the key output never shows the video")
        XCTAssertNil(state.mediaFill(for: .stage))
        XCTAssertEqual(VideoLayerView.PlayerView(player: player, gravity: .resizeAspect).playerLayer.videoGravity, .resizeAspect)

        weak var released = state.fullScreenPlayer
        autoreleasepool { state.perform(.stopVideo) }
        XCTAssertNil(state.fullScreenVideo)
        XCTAssertNil(released, "stop releases the player")
        XCTAssertEqual(state.shownLines, lines, "the lyrics come back")
        XCTAssertEqual(state.background, .video(background), "the background comes back")
        XCTAssertEqual(backgroundPlayer.rate, 1, "the background resumes")
        XCTAssertEqual(state.mediaFill(for: .audience), .video(backgroundPlayer))
        XCTAssertNotEqual(film, background)
    }

    func testTheNaturalEndRestoresTheLyricsAndTheBackground() throws {
        let (state, background, _) = try playing(frames: 12)
        waitFor(nil, in: state)
        XCTAssertFalse(state.shownLines.isEmpty)
        XCTAssertEqual(state.background, .video(background))
        XCTAssertEqual(state.backgroundVideo?.player.rate, 1)
        XCTAssertNil(state.fullScreenPlayer)
    }

    func testClearSlideDuringTheVideoKeepsTheLyricsClearedAfterIt() throws {
        let (state, _, _) = try playing()
        state.perform(.clearSlide)
        XCTAssertNotNil(state.fullScreenVideo, "Clear Slide leaves the video playing")
        state.perform(.stopVideo)
        XCTAssertTrue(state.isCleared)
        XCTAssertEqual(state.shownLines, [])
    }

    func testClearAllClearBackgroundAndNextStopTheVideo() throws {
        for command in [AppCommand.clearAll, .clearBackground, .nextSlide] {
            let (state, _, _) = try playing()
            state.perform(command)
            XCTAssertNil(state.fullScreenVideo, "\(command) stops the video")
            XCTAssertNil(state.fullScreenPlayer)
            XCTAssertEqual(state.isCleared, command == .clearAll)
            XCTAssertEqual(state.background == .none, command != .nextSlide)
            if command == .nextSlide { XCTAssertEqual(state.programIndex, 1); XCTAssertFalse(state.shownLines.isEmpty) }
        }
    }

    func testAnotherVideoReplacesTheFirst() throws {
        let (state, _, _) = try playing()
        let first = try XCTUnwrap(state.fullScreenPlayer?.player), second = try clip("second.mp4", frames: 24 * 30)
        state.perform(.playFullScreen(second))
        waitFor(second, in: state)
        XCTAssertEqual(first.rate, 0)
        XCTAssertNil(first.currentItem)
        XCTAssertEqual(state.shownLines, [])
    }

    func testFilesThatAreNotVideosAreRejected() throws {
        let state = AppState(), text = folder.appendingPathComponent("notes.mp4")
        try Data("Invented placeholder words".utf8).write(to: text)
        for invalid in [text, folder.appendingPathComponent("missing.mp4"), URL(string: "https://example.com/film.mp4")!] {
            state.perform(.playFullScreen(invalid))
        }
        spin()
        XCTAssertNil(state.fullScreenVideo)
        XCTAssertNil(state.fullScreenPlayer)
        XCTAssertFalse(state.shownLines.isEmpty)
    }

    func testOnScreenTextNamesTheVideo() throws {
        let (state, _, _) = try playing()
        XCTAssertEqual(onScreenText(state, language: "en"), "On screen: Full-screen video: film · lyrics hidden until it ends")
        XCTAssertEqual(onScreenText(state, language: "es"), "En pantalla: Video a pantalla completa: film · letra oculta hasta que termine")
    }
}
