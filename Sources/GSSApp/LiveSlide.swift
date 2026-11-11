import GSSCore

/// One slide of the current song: up to two lines of one section.
public struct LiveSlide: Equatable, Sendable {
    public let section: String
    public let part, partCount: Int
    public let lines: [String]

    /// Splits a song into slides of two lines, in the order of its default arrangement.
    public static func slides(of song: Song) -> [LiveSlide] {
        let order = song.arrangements?.first { $0.id == song.defaultArrangement }?.sequence ?? song.sections.map(\.id)
        return order.compactMap { id in song.sections.first { $0.id == id } }.flatMap { section -> [LiveSlide] in
            let texts = section.lines.map { $0.text[song.language] ?? "" }
            let parts = stride(from: 0, to: texts.count, by: 2).map { Array(texts[$0..<min($0 + 2, texts.count)]) }
            return parts.enumerated().map { LiveSlide(section: section.label ?? section.kind.rawValue, part: $0.offset + 1, partCount: parts.count, lines: $0.element) }
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
