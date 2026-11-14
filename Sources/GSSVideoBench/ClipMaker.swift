import AppKit
import AVFoundation
import CoreText

/// An error with a plain message for the console.
struct BenchError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One synthetic clip to generate.
struct ClipSpec {
    let codec: AVVideoCodecType
    let width: Int, height: Int, fps: Int

    var name: String { "\(codec == .hevc ? "hevc" : "h264")-\(height)p\(fps).mp4" }
    /// Bits per second, high on purpose, like the videos churches project:
    /// 20 Mbit/s for 1080p30 up to 80 Mbit/s for 4K60.
    var bitrate: Int { (height >= 2160 ? 50_000_000 : 20_000_000) * (fps >= 60 ? 8 : 5) / 5 }
}

/// Writes test clips with AVAssetWriter: a moving gradient, noise, a moving square and a
/// frame counter, plus a 440 Hz tone in AAC so audio decoding is exercised too.
/// Everything is drawn here, so the repository holds no third-party media.
enum ClipMaker {
    static let specs: [ClipSpec] = [AVVideoCodecType.h264, .hevc].flatMap { codec in
        [(1920, 1080), (3840, 2160)].flatMap { size in
            [30, 60].map { ClipSpec(codec: codec, width: size.0, height: size.1, fps: $0) }
        }
    }
    static let sampleRate = 48_000

    static func makeAll(in dir: URL, seconds: Int) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for spec in specs {
            let start = Date()
            do {
                try make(spec, at: dir.appendingPathComponent(spec.name), seconds: seconds)
                print(String(format: "made %@ in %.0f s", spec.name, -start.timeIntervalSinceNow))
            } catch {
                // HEVC encoding is missing on some machines; the other clips are still useful.
                print("skipped \(spec.name): \(error.localizedDescription)")
            }
        }
    }

    static func make(_ spec: ClipSpec, at url: URL, seconds: Int) throws {
        try? FileManager.default.removeItem(at: url) // AVAssetWriter refuses an existing file
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: spec.codec, AVVideoWidthKey: spec.width, AVVideoHeightKey: spec.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: spec.bitrate,
                AVVideoExpectedSourceFrameRateKey: spec.fps,
                AVVideoMaxKeyFrameIntervalKey: spec.fps * 2,
            ],
        ]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw BenchError("this Mac cannot encode \(spec.codec.rawValue) at \(spec.width)x\(spec.height)")
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: spec.width, kCVPixelBufferHeightKey as String: spec.height,
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
        ])
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else { throw writer.error ?? BenchError("cannot start writing") }
        writer.startSession(atSourceTime: .zero)

        // Feed both inputs in turn until each has its full duration; the writer interleaves them.
        let frameCount = seconds * spec.fps, audioFrames = seconds * sampleRate
        var frame = 0, audioFrame = 0
        while frame < frameCount || audioFrame < audioFrames {
            if writer.status == .failed { throw writer.error ?? BenchError("writing failed") }
            var progressed = false
            if frame < frameCount, video.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool {
                let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(spec.fps))
                adaptor.append(try drawFrame(frame, spec: spec, pool: pool), withPresentationTime: time)
                frame += 1
                progressed = true
                if frame == frameCount { video.markAsFinished() }
            }
            if audioFrame < audioFrames, audio.isReadyForMoreMediaData {
                let count = min(1024, audioFrames - audioFrame)
                audio.append(try toneBuffer(start: audioFrame, count: count))
                audioFrame += count
                progressed = true
                if audioFrame == audioFrames { audio.markAsFinished() }
            }
            if !progressed { usleep(1_000) }
        }
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw writer.error ?? BenchError("finishing failed") }
    }

    /// Draws one frame with CoreGraphics straight into a pixel buffer from the writer's pool.
    static func drawFrame(_ frame: Int, spec: ClipSpec, pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let buffer = out else { throw BenchError("no pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: spec.width, height: spec.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw BenchError("no drawing context") }

        let t = Double(frame) / Double(spec.fps), w = Double(spec.width), h = Double(spec.height)
        // A gradient whose colors and angle change every frame.
        func hue(_ x: Double) -> CGColor {
            NSColor(hue: x.truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.8, alpha: 1).cgColor
        }
        let gradient = CGGradient(colorsSpace: nil, colors: [hue(t * 0.1), hue(t * 0.1 + 0.5)] as CFArray, locations: nil)!
        let dx = cos(t) * w / 2, dy = sin(t) * h / 2
        context.drawLinearGradient(
            gradient, start: CGPoint(x: w / 2 - dx, y: h / 2 - dy), end: CGPoint(x: w / 2 + dx, y: h / 2 + dy),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        // New random noise every frame, in 8x8 blocks, so the encoder really uses the high
        // bitrate and the decoder gets a heavy stream, like real camera footage.
        let nw = spec.width / 8, nh = spec.height / 8
        var noise = Data(count: nw * nh)
        noise.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, nw * nh) }
        if let provider = CGDataProvider(data: noise as CFData),
           let image = CGImage(width: nw, height: nh, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: nw,
                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                               decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            context.interpolationQuality = .none
            context.setAlpha(0.2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            context.setAlpha(1)
        }

        // A moving square and the frame number make dropped or repeated frames visible by eye.
        let white = CGColor(gray: 1, alpha: 1), side = h / 8
        context.setFillColor(white)
        context.fill(CGRect(x: (w - side) * (0.5 + 0.5 * sin(t * 2)), y: h / 8, width: side, height: side))
        let label = NSAttributedString(string: "\(spec.name)  frame \(frame)", attributes: [
            .font: CTFontCreateWithName("Menlo" as CFString, h / 14, nil), .foregroundColor: white,
        ])
        context.textPosition = CGPoint(x: w / 20, y: h * 0.8)
        CTLineDraw(CTLineCreateWithAttributedString(label), context)
        return buffer
    }

    /// A chunk of a 440 Hz tone as 16-bit stereo PCM; the writer encodes it to AAC.
    static func toneBuffer(start: Int, count: Int) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
            mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        var samples = [Int16](repeating: 0, count: count * 2)
        for i in 0..<count {
            let value = Int16(sin(2 * .pi * 440 * Double(start + i) / Double(sampleRate)) * 6_000)
            samples[2 * i] = value
            samples[2 * i + 1] = value
        }
        let bytes = count * 4
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let block, let format else { throw BenchError("cannot create an audio buffer") }
        samples.withUnsafeBytes {
            _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                              offsetIntoDestination: 0, dataLength: bytes)
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw BenchError("cannot create an audio sample") }
        return sample
    }
}
