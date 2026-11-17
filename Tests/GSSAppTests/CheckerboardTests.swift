import AppKit
import AVFoundation
import GSSCore
import SwiftUI
import XCTest
@testable import GSSApp

final class CheckerboardTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GSSCheckerboardTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    /// A 2 × 2 white PNG made with Core Graphics.
    private func png() throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let url = folder.appendingPathComponent("white.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// A one-second 64 × 36 H.264 clip of gray frames, written with AVAssetWriter.
    private func clip() throws -> URL {
        let url = folder.appendingPathComponent("film.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 36])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 36,
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
            memset(CVPixelBufferGetBaseAddress(pixels), 128, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 24)))
        }
        input.markAsFinished()
        let finished = expectation(description: "clip written")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 10)
        return url
    }

    /// The color of the pixel at a point of a view drawn at a size, as 0-255 components.
    private func pixel<V: View>(_ view: V, size: NSSize, at point: NSPoint) throws -> [Int] {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / size.width), y = Int(point.y * CGFloat(bitmap.pixelsHigh) / size.height)
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    private func assertColor(_ actual: [Int], _ hex: Int, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = [hex >> 16 & 0xFF, hex >> 8 & 0xFF, hex & 0xFF]
        XCTAssertTrue(zip(actual, expected).allSatisfy { abs($0 - $1) <= 3 }, "\(message): \(actual) is not \(expected)", file: file, line: line)
    }

    func testTileSizeScalesWithThePreviewAndNeverGoesUnderFourPoints() {
        XCTAssertEqual(Checkerboard.tileSize(forWidth: 220), 8)
        XCTAssertEqual(Checkerboard.tileSize(forWidth: 110), 4)
        XCTAssertEqual(Checkerboard.tileSize(forWidth: 40), 4, "never under 4 px")
        XCTAssertEqual(Checkerboard.tileSize(forWidth: 1000), 8 * 1000 / 220, accuracy: 0.001)
    }

    func testCheckerboardDrawsTheTransparentTokenColors() throws {
        let board = Checkerboard()
        assertColor(try pixel(board, size: NSSize(width: 220, height: 124), at: NSPoint(x: 2, y: 2)), 0x2A2A2C, "the first tile")
        assertColor(try pixel(board, size: NSSize(width: 220, height: 124), at: NSPoint(x: 10, y: 2)), 0x1E1E1E, "the second tile")
        assertColor(try pixel(board, size: NSSize(width: 220, height: 124), at: NSPoint(x: 10, y: 10)), 0x2A2A2C, "the tile under the second")
    }

    func testPreviewBackdropFollowsTheMediaLayerAndTheRole() throws {
        let state = AppState()
        XCTAssertEqual(previewBackdrop(state: state, role: .audience), .checkerboard, "nothing on the media layer")
        XCTAssertEqual(previewBackdrop(state: state, role: .key), .keyColor(KeyColor.green.rgba))
        XCTAssertEqual(previewBackdrop(state: state, role: .stage), .black)
        state.perform(.setBackground(.color("#0B1F3A")))
        XCTAssertEqual(previewBackdrop(state: state, role: .audience), .media(.color(RGBA(hex: 0x0B1F3A))))
        XCTAssertEqual(previewBackdrop(state: state, role: .key), .keyColor(KeyColor.green.rgba), "the key preview keeps its key color")
        XCTAssertEqual(previewBackdrop(state: state, role: .stage), .black)
        state.perform(.setBackground(.image(try png())))
        XCTAssertEqual(previewBackdrop(state: state, role: .audience), .media(.image(try XCTUnwrap(state.backgroundImage))))
        state.perform(.clearBackground)
        XCTAssertEqual(previewBackdrop(state: state, role: .audience), .checkerboard, "clearing the background brings the checkerboard back")

        let film = try clip()
        state.perform(.playFullScreen(film))
        let shown = expectation(description: "full-screen video")
        let subscription = state.$fullScreenVideo.first { $0 == film }.sink { _ in shown.fulfill() }
        wait(for: [shown], timeout: 10)
        subscription.cancel()
        XCTAssertEqual(previewBackdrop(state: state, role: .audience), .media(.fullScreenVideo(try XCTUnwrap(state.fullScreenPlayer?.player))))
        XCTAssertEqual(previewBackdrop(state: state, role: .stage), .black)
        state.perform(.stopVideo)
    }

    func testOnlyOperatorPreviewsShowTheCheckerboard() throws {
        let state = AppState(), size = NSSize(width: 320, height: 180), corner = NSPoint(x: 6, y: 6)
        let monitor = { OutputMonitor(output: LiveOutput.samples[0], state: state, width: 320) }
        state.perform(.clearSlide)
        assertColor(try pixel(AudienceOutputView(state: state), size: size, at: corner), 0x000000, "the real audience output stays black")
        XCTAssertEqual(AudienceOutputView.background, RGBA(hex: 0x000000))
        XCTAssertEqual(OutputThemes.audience.background.kind, .color, "built-in themes keep a valid background")
        assertColor(try pixel(monitor(), size: NSHostingView(rootView: monitor()).fittingSize, at: corner),
                    0x2A2A2C, "the audience monitor shows the checkerboard")
        assertColor(try pixel(SlideFace(lines: [], size: 12), size: size, at: corner), 0x2A2A2C, "a slide preview shows the checkerboard")
        state.perform(.setBackground(.color("#0B1F3A")))
        assertColor(try pixel(monitor(), size: NSHostingView(rootView: monitor()).fittingSize, at: corner),
                    0x0B1F3A, "the audience monitor shows the background on air")
        assertColor(try pixel(SlideFace(lines: [], size: 12).environment(\.previewBackdrop, previewBackdrop(state: state, role: .audience)), size: size, at: corner),
                    0x0B1F3A, "a slide preview shows the background on air")
    }

    func testLiveAndPrepareRenderWithTheCheckerboard() {
        for view in [AnyView(LiveView(state: AppState(), appearance: .standard)), AnyView(PrepareView(state: AppState(), appearance: .standard))] {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }
}
