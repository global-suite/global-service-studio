import GSSCore
import XCTest
@testable import GSSApp

final class SlideBreaksAppTests: XCTestCase {
    /// The grouping before line balancing: two lines per slide in order, the last slide may hold one.
    private func twoLineGroups(_ song: Song, _ section: SongSection) -> [[String]] {
        let texts = section.lines.map { $0.text[song.language] ?? "" }
        return stride(from: 0, to: texts.count, by: 2).map { Array(texts[$0..<min($0 + 2, texts.count)]) }
    }

    private var fiveLineSong: Song {
        let lines = ["Lantern one", "Lantern two", "Lantern three", "Lantern four", "Lantern five"].map { SongLine(text: ["en": $0]) }
        var song = Song(title: "Paper Lanterns", language: "en", sections: [
            SongSection(id: "v", kind: .verse, number: 1, label: "Verse 1", lines: lines),
            SongSection(id: "c", kind: .chorus, label: "Chorus", lines: Array(lines.prefix(2))),
        ])
        song.defaultArrangement = "a"
        song.arrangements = [SongArrangement(id: "a", name: "A", sequence: ["v", "v", "c"])]
        return song
    }

    func testDefaultArgumentsKeepTheTwoLineGrouping() {
        let song = SampleSong.song
        for mode in [RepetitionMode.separateSlides, .oncePerRun] {
            let parts = SongPart.parts(of: song, mode: mode)
            XCTAssertEqual(parts, SongPart.parts(of: song, mode: mode, maxLines: 2, wrap: .natural))
            for part in parts where !part.slides.isEmpty {
                XCTAssertEqual(part.slides.map(\.lines), twoLineGroups(song, part.section))
                XCTAssertEqual(part.slides.map(\.part), Array(1...part.slides.count))
                XCTAssertTrue(part.slides.allSatisfy { $0.partCount == part.slides.count })
            }
        }
        XCTAssertEqual(LiveSlide.slides(of: song).count, 11)
        XCTAssertEqual(SongPart.parts(of: fiveLineSong)[0].slides.map(\.lines.count), [2, 2, 1])
    }

    func testBalancedMaxLinesFourGivesFewerEvenSlidesAndKeepsRepetitions() {
        let song = fiveLineSong
        let parts = SongPart.parts(of: song, maxLines: 4, wrap: .balanced)
        XCTAssertEqual(parts.map(\.section.id), ["v", "v", "c"])
        XCTAssertEqual(parts.map(\.slides.count), [2, 2, 1])
        XCTAssertEqual(parts[0].slides.map(\.lines), [["Lantern one", "Lantern two", "Lantern three"], ["Lantern four", "Lantern five"]])
        XCTAssertEqual(parts[0].slides.map(\.part), [1, 2])
        XCTAssertEqual(parts[0].slides.map(\.partCount), [2, 2])
        XCTAssertEqual(parts.map(\.repetition), [1, 2, 1])
        XCTAssertEqual(parts.map(\.repetitionCount), [2, 2, 1])
        XCTAssertEqual(parts[1].slides.map(\.repetition), [2, 2])
        XCTAssertEqual(parts.map(\.firstSlide), [0, 2, 4])

        let once = SongPart.parts(of: song, mode: .oncePerRun, maxLines: 4, wrap: .balanced)
        XCTAssertEqual(once.map(\.slides.count), [2, 0, 1])
        XCTAssertEqual(once.map(\.repetitionCount), [2, 2, 1])
    }

    func testForcedSlideBreakIsKept() {
        var song = fiveLineSong
        song.sections[0].lines[0].breakAfter = "slide"
        let parts = SongPart.parts(of: song, maxLines: 4, wrap: .balanced)
        XCTAssertEqual(parts[0].slides.map(\.lines.count), [1, 4])
    }
}
