import GSSCore

/// One slide of the current song: up to two lines of one section.
public struct LiveSlide: Equatable, Sendable {
    public let section: String
    public let part, partCount: Int
    public let lines: [String]
    /// Which time of its run of repeats the slide's part is, and how many times the run sings it; 1 and 1 when not repeated.
    public var repetition = 1, repetitionCount = 1

    /// Splits a song into slides of two lines, in the order of its default arrangement.
    public static func slides(of song: Song) -> [LiveSlide] { SongPart.parts(of: song).flatMap(\.slides) }
}

/// One part of the song as sung: a section, its slides and where they start among the song's slides.
public struct SongPart: Equatable, Sendable {
    public let section: SongSection
    public let slides: [LiveSlide]
    public let firstSlide: Int
    public let isRepeat: Bool
    /// Which time of its run of consecutive repeats this part is, from 1, and the length of the run.
    public let repetition, repetitionCount: Int
    public var name: String { Strings.sectionName(section) }
    public var slideRange: Range<Int> { firstSlide..<firstSlide + slides.count }

    /// The parts in the order of the default arrangement; a part is a repeat when its section was sung before.
    /// Shown once per run, a run's first part takes the slides, named "Chorus ×3", and the others have none.
    /// Lines are grouped into slides of up to `maxLines` by `SlideBreaks`; the defaults give slides of two lines.
    public static func parts(of song: Song, mode: RepetitionMode = .separateSlides, maxLines: Int = 2, wrap: ThemeWrap = .natural) -> [SongPart] {
        let order = song.arrangements?.first { $0.id == song.defaultArrangement }?.sequence ?? song.sections.map(\.id)
        let sections = order.compactMap { id in song.sections.first { $0.id == id } }
        let runs = repetitions(of: sections.map(\.id))
        return zip(sections, runs).reduce(into: []) { parts, item in
            let (section, run) = item
            let texts = section.lines.map { $0.text[song.language] ?? "" }
            let groups = SlideBreaks.ranges(of: section.lines, maxLines: maxLines, wrap: wrap).map { Array(texts[$0]) }
            let once = mode == .oncePerRun, base = Strings.sectionName(section)
            let name = once && run.count > 1 ? String(format: Strings.text("%1$@ ×%2$ld"), base, run.count) : base
            let slides = once && run.repetition > 1 ? [] : groups.enumerated().map {
                LiveSlide(section: name, part: $0.offset + 1, partCount: groups.count, lines: $0.element, repetition: once ? 1 : run.repetition, repetitionCount: once ? 1 : run.count)
            }
            parts.append(SongPart(section: section, slides: slides, firstSlide: parts.last?.slideRange.upperBound ?? 0, isRepeat: parts.contains { $0.section.id == section.id },
                                  repetition: run.repetition, repetitionCount: run.count))
        }
    }

    /// For each entry of a song order, its place in its run (consecutive entries of the same section) and the run's length.
    /// A section sung again after another part starts a new run.
    static func repetitions(of order: [String]) -> [(repetition: Int, count: Int)] {
        var result: [(repetition: Int, count: Int)] = []
        var start = 0
        while start < order.count {
            let end = order[start...].firstIndex { $0 != order[start] } ?? order.count
            result += (1...(end - start)).map { ($0, end - start) }
            start = end
        }
        return result
    }
}

/// A built-in song with invented text, shown until the library exists.
enum SampleSong {
    static let song: Song = {
        func section(_ id: String, _ kind: SongSectionKind, _ label: String, _ lines: [String]) -> SongSection {
            SongSection(id: id, kind: kind, number: Int(label.filter(\.isNumber)), label: label, lines: lines.map { SongLine(text: ["en": $0]) })
        }
        var song = Song(title: "Morning Light", language: "en", sections: [
            section("v1", .verse, "Verse 1", ["Morning light is rising", "Over all the earth", "Every shadow fading", "Hope is being born"]),
            section("c", .chorus, "Chorus", ["We lift our voice", "We lift our eyes", "You are the light", "That never dies"]),
            section("v2", .verse, "Verse 2", ["Mercy like a river", "Running through the night", "Every heart awakened", "Every wrong made right"]),
            section("b", .bridge, "Bridge", ["Shine on us", "Shine through us"]),
        ])
        (song.key, song.tempo, song.defaultArrangement) = ("G", 72, "default")
        song.arrangements = [SongArrangement(id: "default", name: "Default", sequence: ["v1", "c", "v2", "c", "b", "c"])]
        return song
    }()
}
