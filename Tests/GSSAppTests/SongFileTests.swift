import GSSCore
import XCTest
@testable import GSSApp

final class SongFileTests: XCTestCase {
    /// An invented OpenLyrics song whose Spanish verse has fewer lines than the English one, so it is skipped.
    private let openLyrics = """
        <?xml version="1.0" encoding="UTF-8"?>
        <song xmlns="http://openlyrics.info/namespace/2009/song" version="0.9">
          <properties><titles><title>Morning Field</title></titles></properties>
          <lyrics>
            <verse name="v1" lang="en"><lines>Light on the hill<br/>Wind in the grass</lines></verse>
            <verse name="v1" lang="es"><lines>Una sola línea</lines></verse>
          </lyrics>
        </song>
        """

    func testOpenLyricsDataUsesTheOpenLyricsImporterAndReportsSkippedVerses() throws {
        let opened = try SongFile.importSong(data: Data(openLyrics.utf8), fileName: "morning")
        XCTAssertEqual(opened.song.title, "Morning Field")
        XCTAssertEqual(opened.song.sections.count, 1)
        let expected = OpenLyricsImporter.SkippedVerse(name: "v1", language: "es", reason: .lineCountMismatch)
        XCTAssertEqual(opened.skipped, [expected])
    }

    func testPlainTextDataUsesThePlainTextImporter() throws {
        let text = "Verse 1\nLight on the hill\nWind in the grass\n\nChorus\nSing in the morning\n"
        let opened = try SongFile.importSong(data: Data(text.utf8), fileName: "Morning Field")
        XCTAssertEqual(opened.song.title, "Morning Field")
        XCTAssertEqual(opened.song.sections.count, 2)
        XCTAssertEqual(opened.skipped, [])
    }

    func testPlainTextWithoutLyricsStillGivesTheNoLyricsMessage() {
        XCTAssertThrowsError(try SongFile.importSong(data: Data("\n\n".utf8), fileName: "empty")) { error in
            XCTAssertEqual(SongFile.message(for: error, language: "en"), "This file has no lyrics.")
            XCTAssertEqual(SongFile.message(for: error, language: "es"), "Este archivo no tiene letra.")
        }
    }

    func testMalformedXMLGivesALocalizedError() {
        let data = Data("<song>\n<lyrics></song>\n".utf8)
        XCTAssertThrowsError(try SongFile.importSong(data: data, fileName: "broken")) { error in
            XCTAssertEqual(SongFile.message(for: error, language: "en"), "This file is not valid XML (line 2).")
            XCTAssertEqual(SongFile.message(for: error, language: "es"), "Este archivo no es XML válido (línea 2).")
        }
    }

    func testXMLThatIsNotOpenLyricsGivesALocalizedError() {
        let data = Data("<html><body>Light on the hill</body></html>".utf8)
        XCTAssertThrowsError(try SongFile.importSong(data: data, fileName: "page")) { error in
            XCTAssertEqual(SongFile.message(for: error, language: "en"), "This XML file is not an OpenLyrics song.")
            XCTAssertEqual(SongFile.message(for: error, language: "es"), "Este archivo XML no es una canción OpenLyrics.")
        }
    }

    func testSkippedVersesAreListedOneLinePerVerse() throws {
        let skipped = [
            OpenLyricsImporter.SkippedVerse(name: "v1", language: "es", reason: .lineCountMismatch),
            OpenLyricsImporter.SkippedVerse(name: "c", language: "fr", reason: .noMainLanguage),
        ]
        let english = try XCTUnwrap(SongFile.skippedAlert(skipped, language: "en"))
        XCTAssertEqual(english.title, "Some verses were not imported.")
        XCTAssertEqual(english.message, "v1 (language: es)\nc (language: fr)")
        let spanish = try XCTUnwrap(SongFile.skippedAlert(skipped, language: "es"))
        XCTAssertEqual(spanish.title, "Algunas partes no se importaron.")
        XCTAssertEqual(spanish.message, "v1 (idioma: es)\nc (idioma: fr)")
        XCTAssertNil(SongFile.skippedAlert([], language: "en"))
    }

    func testPlainTextThatStartsWithAnAngleBracketIsReadAsText() throws {
        let text = "<3 Invented Title\n\nInvented line one\nInvented line two\n"
        let result = try SongFile.importSong(data: Data(text.utf8), fileName: "Invented")
        let first = result.song.sections.first?.lines.first?.text.values.first
        XCTAssertEqual(first, "<3 Invented Title")
        XCTAssertTrue(result.skipped.isEmpty)
    }
}
