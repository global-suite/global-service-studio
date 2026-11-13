import GSSCore

/// One slide of the current song: up to two lines of one section.
public struct LiveSlide: Equatable, Sendable {
    public let section: String
    public let part, partCount: Int
    public let lines: [String]

    /// Splits a song into slides of two lines, in the order of its default arrangement.
    public static func slides(of song: Song) -> [LiveSlide] { SongPart.parts(of: song).flatMap(\.slides) }
}

/// One part of the song as sung: a section, its slides and where they start among the song's slides.
public struct SongPart: Equatable, Sendable {
    public let section: SongSection
    public let slides: [LiveSlide]
    public let firstSlide: Int
    public let isRepeat: Bool
    public var name: String { Strings.sectionName(section) }
    public var slideRange: Range<Int> { firstSlide..<firstSlide + slides.count }

    /// The parts in the order of the default arrangement; a part is a repeat when its section was sung before.
    public static func parts(of song: Song) -> [SongPart] {
        let order = song.arrangements?.first { $0.id == song.defaultArrangement }?.sequence ?? song.sections.map(\.id)
        return order.compactMap { id in song.sections.first { $0.id == id } }.reduce(into: []) { parts, section in
            let texts = section.lines.map { $0.text[song.language] ?? "" }
            let groups = stride(from: 0, to: texts.count, by: 2).map { Array(texts[$0..<min($0 + 2, texts.count)]) }
            let name = Strings.sectionName(section)
            let slides = groups.enumerated().map { LiveSlide(section: name, part: $0.offset + 1, partCount: groups.count, lines: $0.element) }
            parts.append(SongPart(section: section, slides: slides, firstSlide: parts.last?.slideRange.upperBound ?? 0, isRepeat: parts.contains { $0.section.id == section.id }))
        }
    }
}

/// A built-in song with invented text, shown until the library exists.
enum SampleSong {
    static let song: Song = {
        func section(_ id: String, _ kind: SongSectionKind, _ label: String, _ lines: [String]) -> SongSection {
            SongSection(id: id, kind: kind, label: label, lines: lines.map { SongLine(text: ["en": $0]) })
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
