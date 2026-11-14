import Foundation

/// Reads a song from an OpenLyrics 0.9 file (https://docs.openlyrics.org/en/latest/dataformat.html). Each verse name
/// (`v1`, `c`, `c2`, `b`, …) becomes a section; `<br/>` splits lines; chords, comments and formatting tags are dropped
/// but the lyric text inside them is kept. `verseOrder` becomes the default arrangement, otherwise the file order. The
/// language of the first verse is the song's language; a verse in another language is added to the same lines only
/// when its line count matches, and is otherwise reported in `skipped`. Instrumental parts are dropped.
public enum OpenLyricsImporter {
    /// Why a file could not become a song: it is not well-formed XML (`line` is where the parser stopped), its root
    /// element is not `song`, or no verse has lyric lines.
    public enum ImportError: Error, Equatable, Sendable { case malformedXML(line: Int), notOpenLyrics, noVerses }

    /// A verse whose lines were not imported.
    public struct SkippedVerse: Equatable, Sendable {
        /// A translation with another line count than the verse in the song's language, a verse with no counterpart of
        /// that name in the song's language, a transliterated (`translit`) verse, or a repeated name and language.
        public enum Reason: Equatable, Sendable { case lineCountMismatch, noMainLanguage, transliteration, duplicate }
        public var name: String, language: String, reason: Reason
        public init(name: String, language: String, reason: Reason) {
            (self.name, self.language, self.reason) = (name, language, reason)
        }
    }

    /// The imported song and the verses left out of it.
    public struct Imported: Equatable, Sendable {
        public var song: Song
        public var skipped: [SkippedVerse]
    }

    /// The first letter of a standard verse name and its section kind.
    private static let kinds: [Character: SongSectionKind] = [
        "v": .verse, "c": .chorus, "p": .prechorus, "b": .bridge, "i": .intro, "e": .ending, "o": .other,
    ]

    /// Builds a valid song; `fallbackTitle` is used when the file has no title.
    public static func song(from data: Data, fallbackTitle: String) throws -> Song {
        try read(data, fallbackTitle: fallbackTitle).song
    }

    /// Builds a valid song and lists the verses that were left out.
    public static func read(_ data: Data, fallbackTitle: String) throws -> Imported {
        let file = OpenLyricsReader()
        let parser = XMLParser(data: data)
        parser.delegate = file
        guard parser.parse() else {
            if file.notOpenLyrics { throw ImportError.notOpenLyrics }
            throw ImportError.malformedXML(line: parser.lineNumber)
        }
        func language(_ item: OpenLyricsReader.Item) -> String { item.lang ?? file.documentLanguage }
        let verses = file.verses.filter { !$0.lines.isEmpty && !$0.item.text.isEmpty }
        guard let first = verses.first(where: { !$0.item.translit }) else { throw ImportError.noVerses }
        let main = language(first.item)

        var sections: [SongSection] = [], skipped: [SkippedVerse] = []
        for verse in verses where !verse.item.translit && language(verse.item) == main {
            let id = verse.item.text.lowercased()
            guard !sections.contains(where: { $0.id == id }) else {
                skipped.append(SkippedVerse(name: verse.item.text, language: main, reason: .duplicate))
                continue
            }
            let lines = verse.lines.map { SongLine(text: [main: $0]) }
            sections.append(section(id: id, name: verse.item.text, lines: lines))
        }
        for verse in verses where verse.item.translit || language(verse.item) != main {
            let lang = language(verse.item), name = verse.item.text
            func skip(_ reason: SkippedVerse.Reason) { skipped.append(SkippedVerse(name: name, language: lang, reason: reason)) }
            guard !verse.item.translit else { skip(.transliteration); continue }
            guard let index = sections.firstIndex(where: { $0.id == name.lowercased() }) else { skip(.noMainLanguage); continue }
            guard sections[index].lines.first?.text[lang] == nil else { skip(.duplicate); continue }
            guard sections[index].lines.count == verse.lines.count else { skip(.lineCountMismatch); continue }
            for (l, line) in verse.lines.enumerated() { sections[index].lines[l].text[lang] = line }
        }

        let ids = Set(sections.map(\.id))
        let order = (file.fields["verseOrder"]?.text ?? "").split(separator: " ").map { $0.lowercased() }
        var sequence = order.filter { ids.contains($0) }
        if sequence.isEmpty { sequence = sections.map(\.id) }

        var song = Song(title: fallbackTitle, language: main, sections: sections)
        song.arrangements = [SongArrangement(id: "default", name: "Default", sequence: sequence)]
        song.defaultArrangement = "default"

        let titles = file.titles.filter { !$0.text.isEmpty }
        let chosen = titles.firstIndex { !$0.translit && language($0) == main } ?? titles.firstIndex { !$0.translit }
        var translated: [String: String] = [:], alternates: [String] = []
        for (t, title) in titles.enumerated() {
            if t == chosen {
                song.title = title.text
            } else if !title.translit, language(title) != main, translated[language(title)] == nil {
                translated[language(title)] = title.text
            } else {
                alternates.append(title.text)
            }
        }
        song.titles = translated.isEmpty ? nil : translated
        if !alternates.isEmpty { song.extensions = ["openlyrics": .object(["alternateTitles": alternates.json])] }

        let authors = file.authors.filter { !$0.text.isEmpty }.map { SongAuthor(name: $0.text, role: $0.type) }
        song.authors = authors.isEmpty ? nil : authors
        var tags: [String] = []
        for theme in file.themes where !theme.translit && language(theme) == main && !tags.contains(theme.text) {
            if !theme.text.isEmpty { tags.append(theme.text) }
        }
        song.tags = tags.isEmpty ? nil : tags
        func field(_ name: String) -> String? { file.fields[name].flatMap { $0.text.isEmpty ? nil : $0.text } }
        song.copyright = field("copyright")
        song.ccliNumber = field("ccliNo")
        song.key = field("key")
        song.timeSignature = field("timeSignature")
        let bpm = (file.fields["tempo"]?.type ?? "bpm") == "bpm" ? field("tempo").flatMap(Double.init) : nil
        song.tempo = bpm.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return Imported(song: song, skipped: skipped)
    }

    /// A section for a verse name: a standard name such as `v1`, `c` or `b2` sets the kind and number; a name with a
    /// part letter (`v1a`) keeps the name as its label, and any other name is kind `other` labelled with the name.
    private static func section(id: String, name: String, lines: [SongLine]) -> SongSection {
        guard let letter = id.first, let kind = kinds[letter], id.range(of: "^.[0-9]*[a-z]?$", options: .regularExpression) != nil else {
            return SongSection(id: id, kind: .other, label: name, lines: lines)
        }
        let digits = String(id.dropFirst().prefix { $0.isNumber })
        let part = id.count > digits.count + 1
        return SongSection(id: id, kind: kind, number: Int(digits), label: part ? name : nil, lines: lines)
    }
}

/// Collects the parts of an OpenLyrics file that a song can hold. Text has its runs of white space collapsed.
private final class OpenLyricsReader: NSObject, XMLParserDelegate {
    /// An element's text with the attributes the importer reads; for a verse, `text` is its name.
    struct Item {
        var text = "", lang: String?, type: String?, translit = false
    }

    var documentLanguage = "en"
    var notOpenLyrics = false
    var titles: [Item] = [], authors: [Item] = [], themes: [Item] = []
    var fields: [String: Item] = [:]
    var verses: [(item: Item, lines: [String])] = []

    private var stack: [String] = []
    private var current = Item()
    private var verse: (item: Item, lines: [String])?
    private var line = ""

    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if stack.isEmpty {
            guard name == "song" else {
                notOpenLyrics = true
                return parser.abortParsing()
            }
            documentLanguage = attributes["xml:lang"].map(Self.clean).flatMap { $0.isEmpty ? nil : $0 } ?? "en"
        }
        if name == "verse", stack.last == "lyrics" {
            verse = (Item(text: Self.clean(attributes["name"] ?? ""), lang: attributes["lang"],
                          translit: attributes["translit"] != nil), [])
        } else if name == "br", verse != nil {
            endLine()
        } else if verse == nil {
            current = Item(lang: attributes["lang"], type: attributes["type"], translit: attributes["translit"] != nil)
        }
        stack.append(name)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if verse != nil {
            if stack.contains("lines"), !stack.contains("comment") { line += string }
        } else {
            current.text += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = stack.removeLast()
        let parent = stack.last ?? ""
        current.text = Self.clean(current.text)
        switch (parent, name) {
        case (_, "lines") where verse != nil: endLine()
        case ("lyrics", "verse"):
            if let verse { verses.append(verse) }
            verse = nil
        case ("titles", "title"): titles.append(current)
        case ("authors", "author"): authors.append(current)
        case ("themes", "theme"): themes.append(current)
        case ("properties", _): fields[name] = current
        default: break
        }
    }

    private func endLine() {
        let text = Self.clean(line)
        if !text.isEmpty { verse?.lines.append(text) }
        line = ""
    }
}
