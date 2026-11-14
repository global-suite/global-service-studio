import XCTest

@testable import GSSCore

final class OpenLyricsImporterTests: XCTestCase {
    private func xml(_ properties: String, _ lyrics: String, lang: String = "") -> Data {
        let attribute = lang.isEmpty ? "" : " xml:lang=\"\(lang)\""
        let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <song xmlns="http://openlyrics.info/namespace/2009/song" version="0.9"\(attribute)>
          <properties>\(properties)</properties>
          <lyrics>\(lyrics)</lyrics>
        </song>
        """
        return Data(text.utf8)
    }
    private func read(_ data: Data) throws -> OpenLyricsImporter.Imported {
        let imported = try OpenLyricsImporter.read(data, fallbackTitle: "Placeholder File")
        try imported.song.validate()
        return imported
    }
    private func order(_ song: Song) -> [String] {
        let arrangement = song.arrangements?.first { $0.id == song.defaultArrangement }
        return arrangement?.sequence ?? []
    }
    private func lines(_ section: SongSection, _ language: String = "en") -> [String?] { section.lines.map { $0.text[language] } }
    private let oneVerse = "<verse name=\"v1\"><lines>Placeholder line</lines></verse>"

    func testMetadataIsMapped() throws {
        let properties = """
        <titles><title>Sample Morning</title><title>Morning Sample</title><title lang="es">Mañana de ejemplo</title></titles>
        <authors><author type="words">A. Writer</author><author>B. Composer</author></authors>
        <copyright>2001 Placeholder Music</copyright><ccliNo>1234567</ccliNo><key>Eb</key>
        <tempo type="bpm">72</tempo><timeSignature>3/4</timeSignature>
        <themes><theme>Placeholder Theme</theme><theme lang="es">Tema</theme><theme>Second Theme</theme></themes>
        """
        let song = try read(xml(properties, oneVerse, lang: "en")).song
        XCTAssertEqual(song.title, "Sample Morning")
        XCTAssertEqual(song.titles, ["es": "Mañana de ejemplo"])
        XCTAssertEqual(song.extensions, ["openlyrics": .object(["alternateTitles": .array([.string("Morning Sample")])])])
        XCTAssertEqual(song.authors, [SongAuthor(name: "A. Writer", role: "words"), SongAuthor(name: "B. Composer")])
        XCTAssertEqual(song.copyright, "2001 Placeholder Music")
        XCTAssertEqual(song.ccliNumber, "1234567")
        XCTAssertEqual(song.key, "Eb")
        XCTAssertEqual(song.tempo, 72)
        XCTAssertEqual(song.timeSignature, "3/4")
        XCTAssertEqual(song.tags, ["Placeholder Theme", "Second Theme"])
        XCTAssertEqual(song.language, "en")
    }

    func testMissingMetadataStaysAbsentAndTextTempoIsDropped() throws {
        let song = try read(xml("<tempo type=\"text\">Moderate</tempo>", oneVerse)).song
        XCTAssertEqual(song.title, "Placeholder File")
        XCTAssertNil(song.titles)
        XCTAssertNil(song.extensions)
        XCTAssertNil(song.authors)
        XCTAssertNil(song.tempo)
        XCTAssertNil(song.tags)
        XCTAssertEqual(song.language, "en")
    }

    func testVerseNamesMapToKindsAndNumbers() throws {
        let names = ["v1", "c", "c2", "p", "b1", "i", "e", "o", "v2a", "x9"]
        let lyrics = names.map { "<verse name=\"\($0)\"><lines>Line of \($0)</lines></verse>" }.joined()
        let song = try read(xml("", lyrics)).song
        XCTAssertEqual(song.sections.map(\.id), names)
        let kinds: [SongSectionKind] = [.verse, .chorus, .chorus, .prechorus, .bridge, .intro, .ending, .other, .verse, .other]
        XCTAssertEqual(song.sections.map(\.kind), kinds)
        XCTAssertEqual(song.sections.map(\.number), [1, nil, 2, nil, 1, nil, nil, nil, 2, nil])
        XCTAssertEqual(song.sections.map(\.label), [nil, nil, nil, nil, nil, nil, nil, nil, "v2a", "x9"])
        XCTAssertEqual(lines(song.sections[1]), ["Line of c"])
    }

    func testVerseOrderBecomesTheDefaultArrangement() throws {
        let lyrics = """
        <verse name="v1"><lines>First words</lines></verse>
        <verse name="c"><lines>Refrain words</lines></verse>
        <instrument name="m"><lines><chord root="D"/></lines></instrument>
        """
        let song = try read(xml("<verseOrder>v1 C m v1  c missing</verseOrder>", lyrics)).song
        XCTAssertEqual(song.sections.map(\.id), ["v1", "c"])
        XCTAssertEqual(order(song), ["v1", "c", "v1", "c"])
        XCTAssertEqual(song.arrangements?.map(\.name), ["Default"])
    }

    func testWithoutVerseOrderTheFileOrderIsUsed() throws {
        let lyrics = "<verse name=\"c\"><lines>Refrain</lines></verse><verse name=\"v1\"><lines>Verse</lines></verse>"
        XCTAssertEqual(order(try read(xml("", lyrics)).song), ["c", "v1"])
    }

    func testLinesSplitOnBreaksAndChordsCommentsAndTagsAreStripped() throws {
        let lyrics = """
        <verse name="v1">
          <lines>
            <comment>Sing softly</comment>
            Pla<chord root="G">ce</chord>holder <tag name="red">morning</tag> line<br/>
            <chord root="C" structure="min"/>Second   placeholder line<br/>
          </lines>
          <lines break="optional">Third line</lines>
        </verse>
        """
        let section = try read(xml("", lyrics)).song.sections[0]
        XCTAssertEqual(lines(section), ["Placeholder morning line", "Second placeholder line", "Third line"])
        XCTAssertNil(section.lines[0].chords)
    }

    func testMatchingTranslationIsAddedToTheSameLines() throws {
        let lyrics = """
        <verse name="v1" lang="en"><lines>One line<br/>Two line</lines></verse>
        <verse name="v1" lang="es"><lines>Línea uno<br/>Línea dos</lines></verse>
        """
        let imported = try read(xml("", lyrics, lang: "de"))
        XCTAssertEqual(imported.song.language, "en")
        XCTAssertEqual(lines(imported.song.sections[0], "es"), ["Línea uno", "Línea dos"])
        XCTAssertEqual(imported.skipped, [])
    }

    func testTranslationWithOtherLineCountIsSkippedAndReported() throws {
        let lyrics = """
        <verse name="v1" lang="es"><lines>Línea uno<br/>Línea dos</lines></verse>
        <verse name="v1" lang="en"><lines>Only one line</lines></verse>
        <verse name="c" lang="en"><lines>Lonely refrain</lines></verse>
        <verse name="v1" lang="es" translit="en"><lines>Leenea uno<br/>Leenea dos</lines></verse>
        """
        let imported = try read(xml("", lyrics))
        XCTAssertEqual(imported.song.language, "es")
        XCTAssertEqual(imported.song.sections.map(\.id), ["v1"])
        XCTAssertEqual(lines(imported.song.sections[0], "en"), [nil, nil])
        let skipped = [
            OpenLyricsImporter.SkippedVerse(name: "v1", language: "en", reason: .lineCountMismatch),
            OpenLyricsImporter.SkippedVerse(name: "c", language: "en", reason: .noMainLanguage),
            OpenLyricsImporter.SkippedVerse(name: "v1", language: "es", reason: .transliteration),
        ]
        XCTAssertEqual(imported.skipped, skipped)
    }

    func testMalformedXMLIsRejected() {
        let data = Data("<song version=\"0.9\"><properties>\n<titles></song>".utf8)
        XCTAssertThrowsError(try OpenLyricsImporter.read(data, fallbackTitle: "F")) { error in
            XCTAssertEqual(error as? OpenLyricsImporter.ImportError, .malformedXML(line: 2))
        }
    }

    func testOtherRootIsNotOpenLyrics() {
        let data = Data("<?xml version=\"1.0\"?><plist><dict/></plist>".utf8)
        XCTAssertThrowsError(try OpenLyricsImporter.read(data, fallbackTitle: "F")) { XCTAssertEqual($0 as? OpenLyricsImporter.ImportError, .notOpenLyrics) }
    }

    func testSongWithoutVersesIsRejected() {
        let lyrics = "<instrument name=\"i\"><lines><chord root=\"D\"/></lines></instrument><verse name=\"v1\"><lines> <br/> </lines></verse>"
        XCTAssertThrowsError(try OpenLyricsImporter.read(xml("", lyrics), fallbackTitle: "F")) { XCTAssertEqual($0 as? OpenLyricsImporter.ImportError, .noVerses) }
    }

    func testImportedSongRoundTripsThroughTheSongFormat() throws {
        let properties = "<titles><title>Sample</title><title>Alternate</title></titles><ccliNo>42</ccliNo>"
        let lyrics = "<verse name=\"v1\"><lines>A<br/>B</lines></verse><verse name=\"v1\" lang=\"es\"><lines>Á<br/>Bé</lines></verse>"
        let song = try OpenLyricsImporter.song(from: xml(properties, lyrics), fallbackTitle: "F")
        let decoded = try Song.decode(from: song.encoded())
        XCTAssertEqual(decoded, song)
    }
}
