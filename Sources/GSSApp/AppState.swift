import Combine
import Foundation
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
    case clearSlide, clearAll
    case selectPart(Int)
    case setLines(sectionID: String, lines: [String])
    case showAudienceOutput(Bool)
    case selectOutputScreen(ScreenID?)
    /// Makes a song the current one, from its first slide; a song without slides is ignored.
    case loadSong(Song)
}

/// A display, by its Core Graphics display ID.
public typealias ScreenID = UInt32

/// The state the interface shows, changed only by `perform(_:)`.
public final class AppState: ObservableObject {
    @Published public private(set) var mode: AppMode = .prepare
    @Published public private(set) var liveIndex = 0
    @Published public private(set) var isCleared = false
    @Published public private(set) var song: Song
    @Published public private(set) var parts: [SongPart]
    @Published public private(set) var slides: [LiveSlide]
    /// The part being edited in Prepare mode, as an index into `parts`.
    @Published public private(set) var selectedPart = 0
    /// Whether the audience output covers its display; only with a display chosen.
    @Published public private(set) var isAudienceOutputShown = false
    /// The display chosen for the audience output.
    @Published public private(set) var outputScreen: ScreenID?

    public init() {
        let parts = SongPart.parts(of: SampleSong.song)
        (song, self.parts, slides) = (SampleSong.song, parts, parts.flatMap(\.slides))
        selectedPart = livePart
    }

    /// The part that holds the live slide.
    public var livePart: Int { part(containing: liveIndex) }
    /// The part that holds a slide of the song.
    public func part(containing slide: Int) -> Int { parts.firstIndex { $0.slideRange.contains(slide) } ?? 0 }

    public var liveSlide: LiveSlide { slides[liveIndex] }
    public var nextSlide: LiveSlide? { slides.indices.contains(liveIndex + 1) ? slides[liveIndex + 1] : nil }
    public var previousSlide: LiveSlide? { liveIndex > 0 ? slides[liveIndex - 1] : nil }
    /// The lines the outputs show: none while cleared.
    public var shownLines: [String] { isCleared ? [] : liveSlide.lines }

    /// Applies a command; moves outside the song and words that leave a part empty are ignored, other moves end a clear. Clear All has no background to clear yet.
    /// The audience output shows only with a display chosen, and clearing the display hides it.
    public func perform(_ command: AppCommand) {
        switch command {
        case .setMode(let mode): if mode != self.mode { self.mode = mode }
        case .nextSlide: goToSlide(liveIndex + 1)
        case .previousSlide: goToSlide(liveIndex - 1)
        case .goToSlide(let index): goToSlide(index)
        case .clearSlide, .clearAll: if !isCleared { isCleared = true }
        case .selectPart(let index): if parts.indices.contains(index), index != selectedPart { selectedPart = index }
        case .setLines(let sectionID, let lines): setLines(sectionID, lines)
        case .showAudienceOutput(let shown): if shown != isAudienceOutputShown, !shown || outputScreen != nil { isAudienceOutputShown = shown }
        case .selectOutputScreen(let screen):
            if screen == nil, isAudienceOutputShown { isAudienceOutputShown = false }
            if screen != outputScreen { outputScreen = screen }
        case .loadSong(let song): load(song)
        }
    }

    /// Replaces the primary-language words of a section, keeping each line's other fields, and rebuilds the slides.
    private func setLines(_ sectionID: String, _ lines: [String]) {
        let texts = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !texts.isEmpty, let index = song.sections.firstIndex(where: { $0.id == sectionID }) else { return }
        let old = song.sections[index].lines
        guard texts != old.map({ $0.text[song.language] ?? "" }) else { return }
        var edited = song
        edited.sections[index].lines = texts.enumerated().map { offset, text in
            var line = old.indices.contains(offset) ? old[offset] : SongLine(text: [:])
            line.text[song.language] = text
            return line
        }
        song = edited
        parts = SongPart.parts(of: song)
        slides = parts.flatMap(\.slides)
        if liveIndex >= slides.count { liveIndex = slides.count - 1 }
    }

    private func load(_ song: Song) {
        let parts = SongPart.parts(of: song), slides = parts.flatMap(\.slides)
        guard !slides.isEmpty else { return }
        (self.song, self.parts, self.slides) = (song, parts, slides)
        if liveIndex != 0 { liveIndex = 0 }
        if selectedPart != 0 { selectedPart = 0 }
        if isCleared { isCleared = false }
    }

    private func goToSlide(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        if index != liveIndex { liveIndex = index }
        if isCleared { isCleared = false }
    }
}
