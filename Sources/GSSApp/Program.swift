import Foundation
import GSSCore

/// A stop of the program: a slide of a plan item, by the item's index in the plan.
public struct ProgramSlide: Equatable, Sendable {
    public let item: Int
    public let slide: LiveSlide
    /// A presentation slide's image (its first image element) and how it fills the screen; nil and `fit` for other slides.
    public var image: MediaReference?
    public var scaling: PresentationImageScaling = .fit
    /// A presentation slide's speaker notes.
    public var notes: String?
    /// A song slide's part, as an index into the item's parts in the order Program builds them, and that part's section id; nil for other slides.
    public var partIndex: Int?
    public var sectionID: String?
}

/// Where a song added to the service goes: right after the live item, or at the end.
public enum ServicePosition: Equatable, Sendable { case next, end }

/// What Live can put on air: the slides of the plan's items in order. A song item gives its song's slides, in the item's own sequence or arrangement
/// when it has one; a presentation item one slide per presentation slide; a plain item is one stop with no lines; headers, media items (until they
/// can be shown), missing songs and missing presentations give none.
public struct Program: Equatable, Sendable {
    public let plan: Plan, songs: [UUID: Song], presentations: [UUID: Presentation], slides: [ProgramSlide]

    public init(plan: Plan, songs: [UUID: Song], presentations: [UUID: Presentation] = [:], mode: RepetitionMode = .separateSlides) {
        (self.plan, self.songs, self.presentations) = (plan, songs, presentations)
        slides = plan.items.indices.flatMap { Self.slides(of: plan.items[$0], at: $0, songs: songs, presentations: presentations, mode: mode) }
    }

    /// The program slides of a plan item; empty for an item without slides.
    public func range(of item: Int) -> Range<Int> {
        let start = slides.firstIndex { $0.item >= item } ?? slides.count
        return start..<(slides[start...].firstIndex { $0.item > item } ?? slides.count)
    }

    /// The title of a plan item, or its song's title when it has none.
    public func title(of item: Int) -> String {
        plan.items[item].title ?? plan.items[item].song.flatMap { songs[$0]?.title } ?? plan.items[item].presentation.flatMap { presentations[$0]?.title } ?? ""
    }

    private static func slides(of item: PlanItem, at index: Int, songs: [UUID: Song], presentations: [UUID: Presentation], mode: RepetitionMode) -> [ProgramSlide] {
        if item.kind == .item { return [ProgramSlide(item: index, slide: LiveSlide(section: item.title ?? "", part: 1, partCount: 1, lines: []))] }
        if item.kind == .presentation, let deck = item.presentation.flatMap({ presentations[$0] }) {
            return deck.slides.enumerated().map { number, slide in
                let image = slide.elements.first { $0.kind == .image && $0.media != nil }
                let live = LiveSlide(section: deck.title, part: number + 1, partCount: deck.slides.count, lines: [])
                return ProgramSlide(item: index, slide: live, image: image?.media, scaling: image?.effectiveScaling ?? .fit, notes: slide.notes)
            }
        }
        guard item.kind == .song, var song = item.song.flatMap({ songs[$0] }) else { return [] }
        // The order for this service only: a copy of the song whose default arrangement is the item's sequence or arrangement.
        if let sequence = item.sequence {
            (song.arrangements, song.defaultArrangement) = ([SongArrangement(id: "", name: "", sequence: sequence)], "")
        } else if let arrangement = item.arrangement, song.arrangements?.contains(where: { $0.id == arrangement }) == true {
            song.defaultArrangement = arrangement
        }
        return SongPart.parts(of: song, mode: mode).enumerated().flatMap { part, songPart in
            songPart.slides.map { ProgramSlide(item: index, slide: $0, partIndex: part, sectionID: songPart.section.id) }
        }
    }
}
