import AVFoundation
import SwiftUI

/// The player of a video background (ADR 0008): one muted, gapless loop that every audience output shares.
/// It is opened and prepared when the command is applied, plays once it is live, and is stopped when another background replaces it.
final class BackgroundVideo {
    let url: URL
    let player = AVQueuePlayer()
    private(set) var looper: AVPlayerLooper?
    private var observation: NSKeyValueObservation?

    /// Opens a playable file with a video track; nil for anything else, such as a missing file or a text file.
    init?(url: URL) {
        guard let asset = Self.playableAsset(at: url) else { return nil }
        self.url = url
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
    }

    /// The asset of a local file AVFoundation can play and that has a video track. Waits for the file to be opened, which
    /// for a local file is quick; it runs when a command is applied, never on the render path.
    static func playableAsset(at url: URL, timeout: TimeInterval = 5) -> AVURLAsset? {
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url), done = DispatchSemaphore(value: 0), result = Result()
        Task.detached {
            if (try? await asset.load(.isPlayable)) == true, let tracks = try? await asset.loadTracks(withMediaType: .video) {
                result.isVideo = !tracks.isEmpty
            }
            done.signal()
        }
        return done.wait(timeout: .now() + timeout) == .success && result.isVideo ? asset : nil
    }

    private final class Result: @unchecked Sendable { var isVideo = false }

    /// Calls `completion` once on the main thread when the first item is ready to play (true) or has failed (false).
    func prepare(_ completion: @escaping (Bool) -> Void) {
        observation = player.observe(\.currentItem?.status, options: [.initial, .new]) { [weak self] player, _ in
            guard let status = player.currentItem?.status, status != .unknown else { return }
            DispatchQueue.main.async {
                guard let self, self.observation != nil else { return }
                self.observation = nil
                completion(status == .readyToPlay)
            }
        }
    }

    /// Starts the loop when the background goes live.
    func start() { player.play() }

    /// Stops the loop and lets go of its items, so the decoder is released with the player.
    func stop() {
        observation = nil
        player.pause()
        looper?.disableLooping()
        player.removeAllItems()
        looper = nil
    }
}

/// Draws a shared player into an output, filling it (aspect fill). The video is decoded once, however many outputs show it.
struct VideoLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerView { PlayerView(player: player) }
    func updateNSView(_ view: PlayerView, context: Context) { if view.playerLayer.player !== player { view.playerLayer.player = player } }

    /// A view backed by an AVPlayerLayer.
    final class PlayerView: NSView {
        let playerLayer = AVPlayerLayer()

        init(player: AVPlayer) {
            super.init(frame: .zero)
            (playerLayer.player, playerLayer.videoGravity) = (player, .resizeAspectFill)
            layer = playerLayer
            wantsLayer = true
        }

        required init?(coder: NSCoder) { nil }
    }
}
