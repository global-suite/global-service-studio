import AVFoundation

/// The player of a full-screen video (ADR 0008): played once with sound on the system default output, over every audience output.
/// It is opened and prepared when the command is applied, and released on stop.
final class FullScreenVideo {
    let url: URL
    let player: AVPlayer
    /// Called on the main thread when the video plays to its end.
    var onEnd: (() -> Void)?
    private var observation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    /// Opens a playable local file with a video track, as a background video does; nil for anything else.
    init?(url: URL) {
        guard let asset = BackgroundVideo.playableAsset(at: url) else { return nil }
        self.url = url
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.actionAtItemEnd = .pause
    }

    /// Calls `completion` once on the main thread when the item is ready to play (true) or has failed (false).
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

    /// Starts playing when the video goes live, with the end notification.
    func start() {
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            self?.onEnd?()
        }
        player.play()
    }

    /// Stops playing and lets go of the item, so the decoder is released with the player.
    func stop() {
        observation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        (endObserver, onEnd) = (nil, nil)
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
