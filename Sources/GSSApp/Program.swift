import Foundation
import GSSCore

/// A stop of the program: a slide of a plan item, by the item's index in the plan.
public struct ProgramSlide: Equatable, Sendable {
    public let item: Int
    public let slide: LiveSlide
}

/// Where a song added to the service goes: right after the live item, or at the end.
public enum ServicePosition: Equatable, Sendable { case next, end }

/// What Live can put on air: the slides of the plan's items in order. A song item gives its song's slides, in the item's own sequence or arrangement
/// when it has one; a plain item is one stop with no lines; headers, presentation and media items (until they can be shown) and missing songs give none.
public struct Program: Equatable, Sendable {
    public let plan: Plan, songs: [UUID: Song], slides: [ProgramSlide]

    public init(plan: Plan, songs: [UUID: Song], mode: RepetitionMode = .separateSlides) {
        (self.plan, self.songs) = (plan, songs)
        slides = plan.items.indices.flatMap { index in
            Self.slides(of: plan.items[index], songs: songs, mode: mode).map { ProgramSlide(item: index, slide: $0) }
        }
    }

    /// The program slides of a plan item; empty for an item without slides.
    public func range(of item: Int) -> Range<Int> {
        let start = slides.firstIndex { $0.item >= item } ?? slides.count
        return start..<(slides[start...].firstIndex { $0.item > item } ?? slides.count)
    }

    /// The title of a plan item, or its song's title when it has none.
    public func title(of item: Int) -> String {
        plan.items[item].title ?? plan.items[item].song.flatMap { songs[$0]?.title } ?? ""
    }

    private static func slides(of item: PlanItem, songs: [UUID: Song], mode: RepetitionMode) -> [LiveSlide] {
        if item.kind == .item { return [LiveSlide(section: item.title ?? "", part: 1, partCount: 1, lines: [])] }
        guard item.kind == .song, var song = item.song.flatMap({ songs[$0] }) else { return [] }
        // The order for this service only: a copy of the song whose default arrangement is the item's sequence or arrangement.
        if let sequence = item.sequence {
            (song.arrangements, song.defaultArrangement) = ([SongArrangement(id: "", name: "", sequence: sequence)], "")
        } else if let arrangement = item.arrangement, song.arrangements?.contains(where: { $0.id == arrangement }) == true {
            song.defaultArrangement = arrangement
        }
        return SongPart.parts(of: song, mode: mode).flatMap(\.slides)
    }
}
