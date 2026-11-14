import AppKit
import AVFoundation
import MetalKit

/// What one playback measured.
struct PlayResult {
    let file: String
    let outputs: Int
    let seconds: Double
    let presented: Int // new video frames put on screen
    let late: Int // display ticks where a frame was due but no new one was ready
    let dropped: Int // video frames skipped entirely
    let avgIntervalMs: Double, worstIntervalMs: Double // time between new frames on screen
    let cpuPercent: Double // this process, 100 = one full core

    static let header = "file                   out   secs  shown   late dropped  avg ms worst ms  cpu %"
    var row: String {
        file.padding(toLength: 22, withPad: " ", startingAt: 0) + String(
            format: " %3d %6.1f %6d %6d %7d %7.2f %8.2f %6.1f",
            outputs, seconds, presented, late, dropped, avgIntervalMs, worstIntervalMs, cpuPercent)
    }
    var json: String {
        let values: [String: Any] = [
            "file": file, "outputs": outputs, "seconds": seconds, "presented": presented, "late": late,
            "dropped": dropped, "avgIntervalMs": avgIntervalMs, "worstIntervalMs": worstIntervalMs,
            "cpuPercent": cpuPercent,
        ]
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// Plays one file the way ADR 0008 plans it: AVPlayer decodes once (hardware, through
/// VideoToolbox), AVPlayerItemVideoOutput hands out BGRA pixel buffers, CVMetalTextureCache turns
/// them into Metal textures without a CPU copy, and every output window draws that same texture.
/// The first window's display tick is the clock that pulls frames and counts them.
@MainActor
final class PlaybackBench: NSObject, MTKViewDelegate {
    private let url: URL, outputs: Int, seconds: Double, fullscreen: Bool
    private let completion: (PlayResult) -> Void
    private let device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private let player = AVPlayer()
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ])
    private var windows: [NSWindow] = []
    private var current: CVMetalTexture? // keeps the frame alive while the windows draw it
    private var fps = 30.0
    private var presented = 0, late = 0, dropped = 0
    private var lastIndex = -1, lastHost = 0.0, intervalSum = 0.0, worstInterval = 0.0
    private var firstHost = 0.0, startHost = 0.0, startCPU = 0.0, finished = false
    private var keepAlive: PlaybackBench? // the playback owns itself until it finishes

    /// Draws a texture over the whole drawable with one triangle that covers it.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position [[position]]; float2 uv; };
    vertex V vmain(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        V v; v.position = float4(p * 2 - 1, 0, 1); v.uv = float2(p.x, 1 - p.y); return v;
    }
    fragment float4 fmain(V v [[stage_in]], texture2d<float> t [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        return t.sample(s, v.uv);
    }
    """

    init(url: URL, outputs: Int, seconds: Double, fullscreen: Bool,
         completion: @escaping (PlayResult) -> Void) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw BenchError("no Metal device")
        }
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vmain")
        descriptor.fragmentFunction = library.makeFunction(name: "fmain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        (self.url, self.outputs, self.seconds, self.fullscreen) = (url, outputs, seconds, fullscreen)
        (self.device, self.queue, self.completion) = (device, queue, completion)
        super.init()
    }

    func start() {
        keepAlive = self
        let item = AVPlayerItem(url: url)
        item.add(output)
        player.replaceCurrentItem(with: item)
        NotificationCenter.default.addObserver(
            self, selector: #selector(loop), name: .AVPlayerItemDidPlayToEndTime, object: item)
        Task { @MainActor in
            if let track = try? await item.asset.loadTracks(withMediaType: .video).first,
               let rate = try? await track.load(.nominalFrameRate), rate > 0 {
                fps = Double(rate)
            }
            openWindows()
            player.play()
        }
        // A safety net: a file that never plays still ends the run.
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 15) { [weak self] in self?.finish() }
    }

    @objc private func loop() {
        player.seek(to: .zero)
        player.play()
    }

    /// One window per output, on its own screen when there are enough screens.
    private func openWindows() {
        let screens = NSScreen.screens
        for i in 0..<outputs {
            guard let screen = screens.isEmpty ? nil : screens[i % screens.count] else { break }
            let area = screen.visibleFrame
            let frame = fullscreen ? screen.frame
                : NSRect(x: area.minX + CGFloat(40 + i * 80), y: area.minY + CGFloat(40 + i * 80), width: 960, height: 540)
            let window = NSWindow(contentRect: frame, styleMask: fullscreen ? [.borderless] : [.titled],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Output \(i + 1): \(url.lastPathComponent)"
            let view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
            view.colorPixelFormat = .bgra8Unorm
            view.preferredFramesPerSecond = screen.maximumFramesPerSecond // the display refresh
            view.delegate = self
            window.contentView = view
            window.setFrame(frame, display: true)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { drawOnMain(view) }
    }

    private func drawOnMain(_ view: MTKView) {
        if view === windows.first?.contentView { pullFrame() }
        guard let frame = current, let texture = CVMetalTextureGetTexture(frame),
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// Takes the newest decoded frame, if any, and updates the counters.
    private func pullFrame() {
        let now = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: now)
        guard player.currentItem?.status == .readyToPlay, itemTime.isValid else { return }
        let due = Int(itemTime.seconds * fps + 0.001) // the frame that should be on screen now
        if due < lastIndex { lastIndex = -1 } // the file looped
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else {
            if startHost > 0, lastIndex >= 0, due > lastIndex { late += 1 }
            return
        }
        var shownTime = CMTime.invalid
        guard let pixels = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &shownTime),
              let cache = textureCache else { return }
        var texture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixels, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), 0, &texture)
        guard let texture else { return }
        current = texture

        let index = Int((shownTime.seconds * fps).rounded())
        if firstHost == 0 { firstHost = now }
        if now - firstHost < 1 {
            // Warm-up: the first second, while windows open and the decoder settles, is not counted.
        } else if startHost == 0 {
            startHost = now
            startCPU = cpuSeconds()
        } else {
            if lastIndex >= 0, index > lastIndex + 1 { dropped += index - lastIndex - 1 }
            let interval = (now - lastHost) * 1000
            intervalSum += interval
            worstInterval = max(worstInterval, interval)
        }
        if startHost > 0 { presented += 1 }
        lastIndex = index
        lastHost = now
        if startHost > 0, now - startHost >= seconds { DispatchQueue.main.async { self.finish() } }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if let error = player.currentItem?.error { print("\(url.lastPathComponent): \(error.localizedDescription)") }
        let elapsed = startHost > 0 ? CACurrentMediaTime() - startHost : 0
        let cpu = elapsed > 0 ? (cpuSeconds() - startCPU) / elapsed * 100 : 0
        player.pause()
        player.replaceCurrentItem(with: nil)
        NotificationCenter.default.removeObserver(self)
        for window in windows {
            (window.contentView as? MTKView)?.isPaused = true
            window.close()
        }
        windows = []
        keepAlive = nil
        completion(PlayResult(
            file: url.lastPathComponent, outputs: outputs, seconds: elapsed, presented: presented, late: late,
            dropped: dropped, avgIntervalMs: presented > 1 ? intervalSum / Double(presented - 1) : 0,
            worstIntervalMs: worstInterval, cpuPercent: cpu))
    }

    /// User plus system CPU time of this process, in seconds.
    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}
