import Foundation

/// Reads a song from plain text. Blocks separated by blank lines are sections, and a line that is only a label such as
/// "Verse 2", "Coro" or "Bridge:" starts a new section wherever it appears. A label with no lines repeats a section
/// already used, and a repeat marker after a label ("x2", "(x3)", "×2") repeats its section that many times in a row.
/// A block without a label is the next verse. An optional first line "Title: …" or "Título: …" sets the title; without
/// it the fallback title is used, with underscores read as spaces.
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
        let spaced = fallbackTitle.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        var title = spaced.isEmpty ? fallbackTitle : spaced
        if let first = lines.firstIndex(where: { !$0.isEmpty }), let value = titleValue(lines[first]) {
            if !value.isEmpty { title = value }
            lines[first] = ""
        }
        var sections: [SongSection] = [], sequence: [String] = []
        var found: Label?, body: [String] = []
        func flush() {
            defer { (found, body) = (nil, []) }
            let times = found?.times ?? 1
            guard !body.isEmpty else {
                let repeated = sections.first { $0.kind == found?.kind && ($0.number ?? 1) == (found?.number ?? 1) }
                if let repeated, found != nil { sequence += Array(repeating: repeated.id, count: times) }
                return
            }
            let prefix = found?.prefix ?? "v"
            let number = found.map { $0.number }
                ?? (sections.filter { $0.kind == .verse }.map { $0.number ?? 1 }.max() ?? 0) + 1
            var n = number ?? 1
            while sections.contains(where: { $0.id == "\(prefix)\(n)" }) { n += 1 }
            sections.append(SongSection(id: "\(prefix)\(n)", kind: found?.kind ?? .verse, number: number, label: found?.label,
                                        lines: body.map { SongLine(text: [language: $0]) }))
            sequence += Array(repeating: "\(prefix)\(n)", count: times)
        }
        for line in lines {
            if line.isEmpty {
                flush()
            } else if let next = label(line) {
                flush()
                found = next
            } else {
                body.append(line)
            }
        }
        flush()
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

    /// A label line: its kind, the prefix of its section ids, its number, the label as written and how many times in a row
    /// its section is sung.
    private typealias Label = (kind: SongSectionKind, prefix: String, number: Int?, label: String, times: Int)

    /// The largest repeat marker honored; a larger one is read as this many times.
    private static let maximumRepeats = 99

    /// The section a label line names, such as "Verse 2:", "coro" or "Puente x3", with the label as written but without
    /// the colon or the repeat marker.
    private static func label(_ line: String) -> Label? {
        func dropColon(_ text: String) -> String { (text.hasSuffix(":") ? String(text.dropLast()) : text).trimmingCharacters(in: .whitespaces) }
        var written = dropColon(line), times = 1
        let marker = #"\s*(\(\s*[xX×]\s*[0-9]+\s*\)|[xX×]\s*[0-9]+)$"#
        if let range = written.range(of: marker, options: .regularExpression) {
            let count = written[range].filter { $0.isASCII && $0.isNumber }
            times = min(max(Int(count) ?? maximumRepeats, 1), maximumRepeats)
            written = dropColon(String(written[..<range.lowerBound]))
        }
        let digits = String(written.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        let name = written.dropLast(digits.count).trimmingCharacters(in: .whitespaces).lowercased()
        guard let entry = kinds[name] else { return nil }
        return (entry.kind, entry.prefix, digits.isEmpty ? nil : Int(digits), written, times)
    }
}
