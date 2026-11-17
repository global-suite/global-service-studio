import AVFoundation
import Combine
import GSSCore
import GSSLibrary
import XCTest
@testable import GSSApp

/// Presentations in the program (issue #129, first slice); every text and image here is invented.
final class ProgramPresentationTests: XCTestCase {
    private let first = MediaReference(path: "Media/Presentations/deck/001.png", sha256: String(repeating: "a", count: 64))
    private let second = MediaReference(path: "Media/Presentations/deck/002.png", sha256: String(repeating: "b", count: 64))
    private let talk = PlanItem(id: "talk", kind: .item, title: "Talk")
    private let dawn = Song(title: "Dawn Invented", language: "en", sections: [
        SongSection(id: "v1", kind: .verse, number: 1, lines: ["Dawn one", "Dawn two", "Dawn three"].map { SongLine(text: ["en": $0]) }),
        SongSection(id: "c", kind: .chorus, lines: [SongLine(text: ["en": "Dawn chorus"])]),
    ])

    /// Three slides: an image with notes, a text before an image set to fill, and a text only.
    private var deck: Presentation {
        let frame = ThemeFrame(x: 0, y: 0, width: 1, height: 1)
        let text = PresentationElement(id: "t", kind: .text, slot: "lyrics", text: ["en": "Invented title"])
        return Presentation(title: "Invented Deck", slides: [
            PresentationSlide(id: "s1", elements: [PresentationElement(id: "e", kind: .image, frame: frame, media: first)], notes: "Invented note"),
            PresentationSlide(id: "s2", elements: [text, PresentationElement(id: "e", kind: .image, frame: frame, media: second, scaling: .fill)]),
            PresentationSlide(id: "s3", elements: [text]),
        ])
    }
    private func songItem(_ sequence: [String]? = nil) -> PlanItem {
        var item = PlanItem(id: "dawn", kind: .song, song: dawn.id)
        item.sequence = sequence
        return item
    }
    private func deckItem(_ deck: Presentation, id: String = "deck") -> PlanItem { PlanItem(id: id, kind: .presentation, presentation: deck.id) }
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ProgramPresentationTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testPresentationItemsGiveOneSlideEachWithImageScalingAndNotes() {
        let deck = deck, missing = PlanItem(id: "gone", kind: .presentation, presentation: UUID())
        let plan = Plan(title: "Invented", items: [songItem(), deckItem(deck), talk, missing])
        let program = Program(plan: plan, songs: [dawn.id: dawn], presentations: [deck.id: deck])
        XCTAssertEqual(program.slides.map(\.item), [0, 0, 0, 1, 1, 1, 2], "a missing presentation gives no slides")
        XCTAssertEqual(program.slides.map(\.image), [nil, nil, nil, first, second, nil, nil])
        XCTAssertEqual(program.slides.map(\.scaling), [.fit, .fit, .fit, .fit, .fill, .fit, .fit])
        XCTAssertEqual(program.slides.map(\.notes), [nil, nil, nil, "Invented note", nil, nil, nil])
        XCTAssertEqual(program.slides.map(\.partIndex), [0, 0, 1, nil, nil, nil, nil])
        XCTAssertEqual(program.slides.map(\.sectionID), ["v1", "v1", "c", nil, nil, nil, nil])
        XCTAssertEqual(program.slides[3..<6].map(\.slide.lines), [[], [], []])
        XCTAssertEqual(program.title(of: 1), "Invented Deck")
    }

    func testSongSlidesAreUnchangedAndTheirPartsMatchTheBackgroundCues() {
        let plan = Plan(title: "Invented", items: [songItem(["c", "c", "v1"]), talk])
        for mode in [RepetitionMode.separateSlides, .oncePerRun] {
            let program = Program(plan: plan, songs: [dawn.id: dawn], mode: mode)
            var ordered = dawn
            (ordered.arrangements, ordered.defaultArrangement) = ([SongArrangement(id: "", name: "", sequence: ["c", "c", "v1"])], "")
            let expected = SongPart.parts(of: ordered, mode: mode).flatMap(\.slides) + [LiveSlide(section: "Talk", part: 1, partCount: 1, lines: [])]
            XCTAssertEqual(program.slides.map(\.slide), expected)
            XCTAssertEqual(program.slides.map(\.image), Array(repeating: nil, count: expected.count))
            for index in program.slides.indices.dropLast() {
                XCTAssertEqual(program.slides[index].partIndex, program.cuePosition(at: index, mode: mode)?.part)
                XCTAssertEqual(program.slides[index].sectionID, program.cuePosition(at: index, mode: mode)?.section)
            }
        }
    }

    func testNextAndPreviousMoveThroughPresentationSlides() {
        let deck = deck, state = AppState()
        state.perform(.openPlan(Plan(title: "Invented", items: [songItem(), deckItem(deck)]), songs: [dawn], presentations: [deck]))
        state.perform(.goToSlide(2))
        XCTAssertNil(state.shownImage)
        state.perform(.nextSlide)
        XCTAssertEqual([state.programIndex, state.liveItem], [3, 1])
        XCTAssertEqual(state.shownImage, first)
        XCTAssertEqual(state.shownLines, [])
        XCTAssertEqual(state.liveProgramSlide?.notes, "Invented note")
        state.perform(.nextSlide)
        XCTAssertEqual(state.shownImage, second)
        state.perform(.clearSlide)
        XCTAssertNil(state.shownImage, "Clear Slide hides the image")
        state.perform(.previousSlide)
        XCTAssertEqual(state.shownImage, first)
        state.perform(.previousSlide)
        XCTAssertEqual(state.shownLines, ["Dawn chorus"])
    }

    func testAddingAPresentationGoesNextOrAtTheEndAndNeverOnAir() throws {
        let deck = deck, url = try Library.open(folder()).save(deck), state = AppState()
        state.perform(.openPlan(Plan(title: "Invented", items: [songItem(), talk]), songs: [dawn]))
        state.perform(.addPresentationToService(url, position: .next))
        XCTAssertEqual(state.programIndex, -1)
        XCTAssertNil(state.shownImage)
        state.perform(.goToSlide(3))
        state.perform(.addPresentationToService(url, position: .end))
        state.perform(.addPresentationToService(url, position: .next))
        state.perform(.addPresentationToService(url.deletingLastPathComponent().appendingPathComponent("gone.presentation.json"), position: .end))
        let items = state.program.plan.items
        XCTAssertEqual(items.map(\.kind), [.presentation, .song, .presentation, .item, .presentation])
        XCTAssertEqual(items.map(\.presentation), [deck.id, nil, deck.id, nil, deck.id])
        XCTAssertEqual(items.map { $0.title ?? "" }, ["Invented Deck", "", "Invented Deck", "Talk", "Invented Deck"])
        XCTAssertEqual([state.programIndex, state.liveItem, state.nextItem], [3, 1, 2])
        XCTAssertEqual(state.shownLines, ["Dawn one", "Dawn two"])
        XCTAssertEqual(state.program.slides.count, 3 + 3 + 3 + 1 + 3)
        XCTAssertEqual(state.alert?.title, Strings.text("The presentation could not be opened."))
        XCTAssertEqual(Strings.text("The presentation could not be opened.", language: "es"), "No se pudo abrir la presentación.")
    }

    func testOpeningAServiceResolvesPresentationsAndTheLibraryListsThem() throws {
        let deck = deck, library = try Library.open(folder()), gone = PlanItem(id: "gone", kind: .presentation, title: "Gone Deck", presentation: UUID())
        try library.save(deck)
        let planURL = try library.save(Plan(title: "Invented", date: "2026-11-22", items: [deckItem(deck), gone]))
        let state = AppState()
        state.perform(.chooseLibraryFolder(library.folder))
        state.perform(.openService(planURL))
        XCTAssertEqual(state.program.slides.map(\.image), [first, second, nil])
        XCTAssertEqual(state.alert?.message, String(format: Strings.text("“%@” is not in the library."), "Gone Deck"))
        let listed = expectation(description: "presentations listed")
        let subscription = state.$libraryPresentations.first { !$0.isEmpty }.sink { _ in listed.fulfill() }
        wait(for: [listed], timeout: 10)
        subscription.cancel()
        XCTAssertEqual(state.libraryPresentations.map(\.presentation), [deck])
    }

    func testAFullScreenVideoHidesThePresentationImage() throws {
        let deck = deck, state = AppState(), video = try clip(in: folder())
        state.perform(.openPlan(Plan(title: "Invented", items: [deckItem(deck)]), songs: [], presentations: [deck]))
        state.perform(.goToSlide(0))
        state.perform(.playFullScreen(video))
        let shown = expectation(description: "full-screen video")
        let subscription = state.$fullScreenVideo.first { $0 == video }.sink { _ in shown.fulfill() }
        wait(for: [shown], timeout: 10)
        subscription.cancel()
        XCTAssertNil(state.shownImage)
        XCTAssertEqual(state.liveProgramSlide?.image, first, "the slide stays live under the video")
        state.perform(.stopVideo)
        XCTAssertEqual(state.shownImage, first)
    }

    /// A one-second 16 × 16 H.264 clip of gray frames.
    private func clip(in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("film.mp4"), writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            XCTAssertTrue(adaptor.append(try XCTUnwrap(buffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 24)))
        }
        input.markAsFinished()
        let finished = expectation(description: "clip written")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 10)
        return url
    }
}
