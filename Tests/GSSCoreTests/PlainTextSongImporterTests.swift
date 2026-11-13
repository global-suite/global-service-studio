import XCTest

@testable import GSSCore

final class PlainTextSongImporterTests: XCTestCase {
    private func song(_ text: String, language: String = "en") throws -> Song {
        let song = try PlainTextSongImporter.song(from: text, fallbackTitle: "Placeholder File", language: language)
        try song.validate()
        return song
    }
    private func order(_ song: Song) -> [String] { song.arrangements?.first { $0.id == song.defaultArrangement }?.sequence ?? [] }
    private func lines(_ section: SongSection, _ language: String = "en") -> [String] { section.lines.map { $0.text[language] ?? "" } }

    func testLabelsInEnglishAndSpanishWithNumbersStartSections() throws {
        let text = """
        Verse 1
        Placeholder sun is up
        Placeholder road ahead

        coro:
        Sample refrain line

        PRE-CHORUS
        Rising sample words

        Puente 2:
        Bridge words here

        Intro
        Opening hum

        Outro
        Closing hum

        Tag
        Tag words

        Interludio
        Interlude hum

        Final
        Ending words

        Verso 2
        Second verse words

        Precoro 3
        Another rise
        """
        let song = try song(text)
        XCTAssertEqual(song.sections.map(\.id), ["v1", "c1", "p1", "b2", "i1", "o1", "t1", "n1", "e1", "v2", "p3"])
        XCTAssertEqual(song.sections.map(\.kind), [.verse, .chorus, .prechorus, .bridge, .intro, .outro, .tag, .interlude, .ending, .verse, .prechorus])
        XCTAssertEqual(song.sections.map(\.number), [1, nil, nil, 2, nil, nil, nil, nil, nil, 2, 3])
        XCTAssertEqual(song.sections.map(\.label), ["Verse 1", "coro", "PRE-CHORUS", "Puente 2", "Intro", "Outro", "Tag", "Interludio", "Final", "Verso 2", "Precoro 3"])
        XCTAssertEqual(lines(song.sections[0]), ["Placeholder sun is up", "Placeholder road ahead"])
        XCTAssertEqual(order(song), song.sections.map(\.id))
        XCTAssertEqual([song.title, song.language], ["Placeholder File", "en"])
    }

    func testLabelOnlyBlocksRepeatAnExistingSection() throws {
        let song = try song("Chorus\nSample refrain\n\nVerse 1\nSample verse\n\nchorus:\n\nChorus 2\nOther refrain\n\nVERSE 1\n\nCoro 2\n\nBridge\n")
        XCTAssertEqual(song.sections.map(\.id), ["c1", "v1", "c2"])
        XCTAssertEqual(order(song), ["c1", "v1", "c1", "c2", "v1", "c2"])
    }

    func testUnlabeledBlocksBecomeTheNextVerse() throws {
        let song = try song("First sample words\nMore sample words\n\nChorus\nSample refrain\n\nSecond sample words\n\nVerse 5\nFifth words\n\nNext words")
        XCTAssertEqual(song.sections.map(\.id), ["v1", "c1", "v2", "v5", "v6"])
        XCTAssertEqual(song.sections.map(\.number), [1, nil, 2, 5, 6])
        XCTAssertEqual(song.sections.map(\.label), [nil, "Chorus", nil, "Verse 5", nil])
        XCTAssertEqual(lines(song.sections[2]), ["Second sample words"])
    }

    func testRepeatedLabelWithNewWordsGetsAUniqueId() throws {
        let song = try song("Chorus\nFirst refrain\n\nChorus\nSecond refrain\n\nChorus 2\nThird refrain")
        XCTAssertEqual(song.sections.map(\.id), ["c1", "c2", "c3"])
    }

    func testTitleLineSetsTheTitleInEitherLanguage() throws {
        XCTAssertEqual(try song("Title: Placeholder Song\nVerse 1\nSample words").title, "Placeholder Song")
        let spanish = try song("título:  Canción de prueba \n\nPalabras de ejemplo", language: "es")
        XCTAssertEqual([spanish.title, spanish.language], ["Canción de prueba", "es"])
        XCTAssertEqual(spanish.sections.map(\.id), ["v1"])
        XCTAssertEqual(lines(spanish.sections[0], "es"), ["Palabras de ejemplo"])
        XCTAssertEqual(try song("Sample words\nTitle: Not a title").title, "Placeholder File")
    }

    func testWindowsLineEndingsAndExtraBlankLines() throws {
        let song = try song("\r\n\r\nVerse 1\r\n  Sample one  \r\nSample two\r\n\r\n \t \r\n\r\nChorus\r\nSample refrain\r\n\r\n")
        XCTAssertEqual(song.sections.map(\.id), ["v1", "c1"])
        XCTAssertEqual(lines(song.sections[0]), ["Sample one", "Sample two"])
    }

    func testLabelLinesInsideABlockStartNewSections() throws {
        let song = try song("Verse 1\nPlaceholder one\nPlaceholder two\nCHORUS:\nSample refrain\nVerso 2\nSecond words\nChorus\nPlain line\nCoro\n")
        XCTAssertEqual(song.sections.map(\.id), ["v1", "c1", "v2", "c2"])
        XCTAssertEqual(lines(song.sections[0]), ["Placeholder one", "Placeholder two"])
        XCTAssertEqual(lines(song.sections[3]), ["Plain line"])
        XCTAssertEqual(order(song), ["v1", "c1", "v2", "c2", "c1"])
    }

    func testRepeatMarkersRepeatTheSectionInTheArrangement() throws {
        let text = "Verse 1 x2\nVerse words\nChorus (x2)\nRefrain words\n\nPuente X3:\nBridge words\n\ncoro ×2\n\nEnding( x 2 )\nLast words\n\nVerse 1: x1"
        let song = try song(text)
        XCTAssertEqual(song.sections.map(\.id), ["v1", "c1", "b1", "e1"])
        XCTAssertEqual(song.sections.map(\.number), [1, nil, nil, nil])
        XCTAssertEqual(song.sections.map(\.label), ["Verse 1", "Chorus", "Puente", "Ending"])
        XCTAssertEqual(order(song), ["v1", "v1", "c1", "c1", "b1", "b1", "b1", "c1", "c1", "e1", "e1", "v1"])
        XCTAssertEqual(lines(song.sections[2]), ["Bridge words"])
    }

    func testLinesThatOnlyLookLikeMarkersStayLyrics() throws {
        let song = try song("Verse 1\nSing it x2\nChorus x\nOver (x3)")
        XCTAssertEqual(song.sections.map(\.id), ["v1"])
        XCTAssertEqual(lines(song.sections[0]), ["Sing it x2", "Chorus x", "Over (x3)"])
    }

    func testFallbackTitleUsesSpacesForUnderscores() throws {
        let song = try PlainTextSongImporter.song(from: "Sample words", fallbackTitle: " Placeholder_Song_Name_ ")
        XCTAssertEqual(song.title, "Placeholder Song Name")
    }

    func testTextWithoutLyricsIsAnError() {
        for text in ["", "\n \r\n\t\n", "Title: Only A Title", "Verse 1\n\nChorus:"] {
            XCTAssertThrowsError(try song(text), text) { XCTAssertEqual($0 as? PlainTextSongImporter.ImportError, .noLyrics) }
        }
    }
}
