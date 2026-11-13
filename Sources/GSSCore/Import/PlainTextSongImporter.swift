import Foundation

/// Reads a song from plain text. Blocks separated by blank lines are sections; a block may start with a label such as
/// "Verse 2", "Coro" or "Bridge:", and a block with only a label already used repeats that section. A block without a
/// label is the next verse. An optional first line "Title: …" or "Título: …" sets the title.
public enum PlainTextSongImporter {
    /// Why a text could not become a song.
    public enum ImportError: Error, Equatable, Sendable {
        /// The text has no lyric lines.
        case noLyrics
    }

    /// Label words in English and Spanish, lowercased, with their kind and the prefix of their section ids.
    private static let kinds: [String: (kind: SongSectionKind, prefix: String)] = [
        "verse": (.verse, "v"), "verso": (.verse, "v"), "chorus": (.chorus, "c"), "coro": (.chorus, "c"),
        "pre-chorus": (.prechorus, "p"), "prechorus": (.prechorus, "p"), "pre chorus": (.prechorus, "p"),
        "precoro": (.prechorus, "p"), "pre-coro": (.prechorus, "p"), "bridge": (.bridge, "b"), "puente": (.bridge, "b"),
        "intro": (.intro, "i"), "outro": (.outro, "o"), "tag": (.tag, "t"), "interlude": (.interlude, "n"),
        "interludio": (.interlude, "n"), "ending": (.ending, "e"), "final": (.ending, "e"),
    ]

    /// Builds a valid song whose default arrangement follows the order of the blocks.
    public static func song(from text: String, fallbackTitle: String, language: String = "en") throws -> Song {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var title = fallbackTitle
        if let first = lines.firstIndex(where: { !$0.isEmpty }), let value = titleValue(lines[first]) {
            if !value.isEmpty { title = value }
            lines[first] = ""
        }
        var sections: [SongSection] = [], sequence: [String] = []
        for block in lines.split(whereSeparator: \.isEmpty) {
            var body = Array(block)
            let found = label(body[0])
            if found != nil { body.removeFirst() }
            guard !body.isEmpty else {
                let repeated = sections.first { $0.kind == found?.kind && ($0.number ?? 1) == (found?.number ?? 1) }
                if let repeated { sequence.append(repeated.id) }
                continue
            }
            let prefix = found?.prefix ?? "v"
            let number = found.map { $0.number }
                ?? (sections.filter { $0.kind == .verse }.map { $0.number ?? 1 }.max() ?? 0) + 1
            var n = number ?? 1
            while sections.contains(where: { $0.id == "\(prefix)\(n)" }) { n += 1 }
            sections.append(SongSection(id: "\(prefix)\(n)", kind: found?.kind ?? .verse, number: number, label: found?.label,
                                        lines: body.map { SongLine(text: [language: $0]) }))
            sequence.append(sections[sections.count - 1].id)
        }
        guard !sections.isEmpty else { throw ImportError.noLyrics }
        var song = Song(title: title, language: language, sections: sections)
        song.arrangements = [SongArrangement(id: "default", name: "Default", sequence: sequence)]
        song.defaultArrangement = "default"
        return song
    }

    /// The text after "Title:" or "Título:" at the start of a line, or nil when the line is not a title.
    private static func titleValue(_ line: String) -> String? {
        let prefix = ["title:", "título:", "titulo:"].first { line.prefix($0.count).lowercased() == $0 }
        return prefix.map { line.dropFirst($0.count).trimmingCharacters(in: .whitespaces) }
    }

    /// The section a label line names, such as "Verse 2:" or "coro", with the label as written but without the colon.
    private static func label(_ line: String) -> (kind: SongSectionKind, prefix: String, number: Int?, label: String)? {
        let written = (line.hasSuffix(":") ? String(line.dropLast()) : line).trimmingCharacters(in: .whitespaces)
        let digits = String(written.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        let name = written.dropLast(digits.count).trimmingCharacters(in: .whitespaces).lowercased()
        guard let entry = kinds[name] else { return nil }
        return (entry.kind, entry.prefix, digits.isEmpty ? nil : Int(digits), written)
    }
}
