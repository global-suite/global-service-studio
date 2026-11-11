import Combine
import GSSCore

/// The two modes of the main window.
public enum AppMode: CaseIterable, Sendable {
    case prepare, live
}

/// A change to the app state; every change goes through a command (ADR 0006, rule 1).
public enum AppCommand: Equatable, Sendable {
    case setMode(AppMode)
    case nextSlide, previousSlide
    case goToSlide(Int)
}

/// The state the interface shows, changed only by `perform(_:)`.
public final class AppState: ObservableObject {
    @Published public private(set) var mode: AppMode = .prepare
    @Published public private(set) var liveIndex = 0
    public let song: Song
    public let slides: [LiveSlide]

    public init() {
        song = SampleSong.song
        slides = LiveSlide.slides(of: song)
    }

    public var liveSlide: LiveSlide { slides[liveIndex] }
    public var nextSlide: LiveSlide? { slides.indices.contains(liveIndex + 1) ? slides[liveIndex + 1] : nil }
    public var previousSlide: LiveSlide? { liveIndex > 0 ? slides[liveIndex - 1] : nil }

    /// Applies a command to the state; moves outside the song are ignored.
    public func perform(_ command: AppCommand) {
        switch command {
        case .setMode(let mode): if mode != self.mode { self.mode = mode }
        case .nextSlide: goToSlide(liveIndex + 1)
        case .previousSlide: goToSlide(liveIndex - 1)
        case .goToSlide(let index): goToSlide(index)
        }
    }

    private func goToSlide(_ index: Int) {
        if slides.indices.contains(index), index != liveIndex { liveIndex = index }
    }
}
