import AVFoundation
import Combine

/// The position of the full-screen video, published about four times a second for the transport only,
/// so the outputs, which observe the app state, are not redrawn by the clock.
final class VideoClock: ObservableObject {
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
}

/// The player of a full-screen video (ADR 0008): played once with sound on the chosen audio device, over every audience output.
/// It is opened and prepared when the command is applied, and released on stop.
final class FullScreenVideo {
    let url: URL
    let player: AVPlayer
    /// Called on the main thread with the elapsed seconds, about four times a second while it plays.
    var onTime: ((Double) -> Void)?
    /// Called on the main thread when the video plays to its end.
    var onEnd: (() -> Void)?
    private var observation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    /// Opens a playable local file with a video track, as a background video does; nil for anything else.
    /// `audioOutputDeviceUID` is a Core Audio device UID; nil plays on the system default.
    init?(url: URL, audioOutputDeviceUID: String?) {
        guard let asset = BackgroundVideo.playableAsset(at: url) else { return nil }
        self.url = url
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.actionAtItemEnd = .pause
        player.audioOutputDeviceUniqueID = audioOutputDeviceUID
    }

    /// The length in seconds, once the item is ready; 0 before.
    var duration: Double {
        let seconds = player.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    var elapsed: Double { player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0 }

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

    /// Starts playing when the video goes live, with the clock and the end notification.
    func start() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            if time.seconds.isFinite { self?.onTime?(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            self?.onEnd?()
        }
        player.play()
    }

    /// Moves to a position, clamped to the video.
    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: min(max(seconds, 0), duration), preferredTimescale: 600))
    }

    /// Stops playing and lets go of the item, so the decoder is released with the player.
    func stop() {
        observation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        (timeObserver, endObserver, onTime, onEnd) = (nil, nil, nil, nil)
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
