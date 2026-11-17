import AVFoundation
import CoreGraphics
import GSSCore
import ImageIO
import XCTest
@testable import GSSApp

/// Song and part backgrounds go on air when the program reaches them (issue #122); every text here is invented.
final class BackgroundCueTests: XCTestCase {
    private var folder: URL!
    private let navy = ThemeBackground(kind: .color, color: "#0B1F3A")

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GSSBackgroundCueTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func media(_ kind: ThemeBackgroundKind, _ path: String) -> ThemeBackground {
        ThemeBackground(kind: kind, media: MediaReference(path: path, sha256: String(repeating: "0", count: 64)))
    }

    private func song(_ title: String, _ backgrounds: SongBackgrounds?) -> Song {
        let lines = { (name: String) in (1...4).map { SongLine(text: ["en": "\(title) \(name) \($0)"]) } }
        var song = Song(title: title, language: "en", sections: [SongSection(id: "v1", kind: .verse, number: 1, lines: lines("verse")),
                                                                 SongSection(id: "c", kind: .chorus, lines: lines("chorus"))])
        song.backgrounds = backgrounds
        return song
    }

    /// A state whose library is the temporary folder, running Morning (verse, chorus, verse: slides 0-5), a plain item (6) and Evening (7-10).
    private func running(_ backgrounds: SongBackgrounds?, sequence: [String] = ["v1", "c", "v1"]) -> AppState {
        let state = AppState(), morning = song("Morning Invented", backgrounds), evening = song("Evening Invented", nil)
        state.perform(.chooseLibraryFolder(folder))
        var item = PlanItem(id: "morning", kind: .song, song: morning.id)
        item.sequence = sequence
        let plan = Plan(title: "Invented", items: [item, PlanItem(id: "talk", kind: .item, title: "Talk"), PlanItem(id: "evening", kind: .song, song: evening.id)])
        state.perform(.openPlan(plan, songs: [morning, evening]))
        return state
    }

    /// A 4 × 2 PNG in the library's Media folder.
    private func png(_ name: String) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        let url = folder.appendingPathComponent("Media/\(name)")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// A short 64 × 36 H.264 clip in the library's Media folder.
    private func clip(_ name: String, frames: Int = 24) throws -> URL {
        let url = folder.appendingPathComponent("Media/\(name)")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 36])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 36,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
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

    private func waitFor<Value: Equatable>(_ value: Value, _ publisher: Published<Value>.Publisher) {
        let shown = expectation(description: "published")
        let subscription = publisher.first { $0 == value }.sink { _ in shown.fulfill() }
        wait(for: [shown], timeout: 10)
        subscription.cancel()
    }

    func testTheCueFollowsTheItemAndThePart() {
        let image = media(.image, "Media/a.png")
        let enter = ProgramPosition(item: "a", part: 0, section: "v1", songBackground: image, partBackground: nil)
        XCTAssertEqual(backgroundCue(previous: nil, current: enter), image, "entering a song item gives its default")
        XCTAssertEqual(backgroundCue(previous: nil, current: ProgramPosition(item: "a", part: 0, section: "c", songBackground: image, partBackground: navy)), navy, "the part wins")
        XCTAssertNil(backgroundCue(previous: enter, current: enter), "moving inside a part")
        XCTAssertEqual(backgroundCue(previous: enter, current: ProgramPosition(item: "a", part: 1, section: "c", songBackground: image, partBackground: navy)), navy)
        XCTAssertNil(backgroundCue(previous: enter, current: ProgramPosition(item: "a", part: 1, section: "v2", songBackground: image, partBackground: nil)), "a part without one")
        XCTAssertNil(backgroundCue(previous: enter, current: ProgramPosition(item: "b", part: 0, section: "v1", songBackground: nil, partBackground: nil)), "a song without one")

        XCTAssertEqual(Background(cue: navy, library: folder), .color("#0B1F3A"))
        XCTAssertNil(Background(cue: image, library: folder), "a missing file is skipped")
        XCTAssertNil(Background(cue: media(.image, "../outside.png"), library: folder))
    }

    func testASongDefaultAndAPartBackgroundGoOnAirOnTheirFirstSlides() throws {
        let state = running(SongBackgrounds(defaultBackground: media(.image, "Media/a.png"), sections: ["c": navy]))
        let image = try png("a.png")
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .image(image), "the song's default goes on air with it")
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .image(image))
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .color("#0B1F3A"), "the chorus switches on its first slide")
        state.perform(.clearBackground)
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .none, "moving within the part never fires again, so Clear Background holds")
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .none, "leaving the part does not undo it")
        state.perform(.previousSlide)
        XCTAssertEqual(state.background, .color("#0B1F3A"), "going back into the part fires again")
        state.perform(.goToSlide(6))
        state.perform(.setBackground(.color("#2B2B2B")))
        state.perform(.previousSlide)
        XCTAssertEqual(state.background, .image(image), "going back into the song is entering it; its last part has none")
    }

    func testAManualBackgroundHoldsUntilTheNextCueAndSongsWithoutOneLeaveIt() {
        let state = running(SongBackgrounds(sections: ["c": navy]))
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .none, "a song with no default leaves the background")
        state.perform(.setBackground(.color("#2B2B2B")))
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .color("#2B2B2B"))
        state.perform(.nextSlide)
        XCTAssertEqual(state.background, .color("#0B1F3A"), "the next cue replaces the operator's choice")
        state.perform(.setBackground(.color("#000000")))
        for slide in 4...8 {
            state.perform(.goToSlide(slide))
            XCTAssertEqual(state.background, .color("#000000"), "a plain item and a song without backgrounds leave it")
        }
    }

    func testAMissingFileIsSkipped() {
        let state = running(SongBackgrounds(defaultBackground: media(.video, "Media/missing.mp4"), sections: ["c": media(.image, "Media/gone.png")]))
        state.perform(.setBackground(.color("#2B2B2B")))
        for slide in 0...3 { state.perform(.goToSlide(slide)) }
        XCTAssertEqual(state.background, .color("#2B2B2B"))
    }

    func testTheSameVideoKeepsPlaying() throws {
        let loop = media(.video, "Media/loop.mp4")
        let state = running(SongBackgrounds(defaultBackground: loop, sections: ["c": loop]))
        let url = try clip("loop.mp4")
        state.perform(.nextSlide)
        waitFor(.video(url), state.$background)
        let video = try XCTUnwrap(state.backgroundVideo), player = video.player
        state.perform(.goToSlide(2))
        state.perform(.goToSlide(4))
        state.perform(.previousSlide)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(state.backgroundVideo === video)
        XCTAssertTrue(state.backgroundVideo?.player === player, "a repeated cue never restarts the video")
        XCTAssertEqual(player.rate, 1)
    }

    func testNoCueFiresDuringAFullScreenVideo() throws {
        let state = running(SongBackgrounds(sections: ["c": navy]), sequence: ["v1", "c"])
        let film = try clip("film.mp4", frames: 24 * 30)
        state.perform(.nextSlide)
        state.perform(.playFullScreen(film))
        waitFor(film, state.$fullScreenVideo)
        var item = state.program.plan.items[0]
        item.sequence = ["c", "v1"]
        state.perform(.updatePlanItem(at: 0, item))
        XCTAssertEqual(state.programIndex, 0)
        XCTAssertEqual(state.background, .none, "the live slide is now the chorus, but the video holds the cue")
        state.perform(.stopVideo)
        state.perform(.goToSlide(2))
        state.perform(.previousSlide)
        XCTAssertEqual(state.background, .color("#0B1F3A"), "the next transition after it fires")
    }

    func testPresentationAndPlainSlidesCueNothing() {
        let deck = Presentation(title: "Invented Deck", slides: [PresentationSlide(id: "s1", elements: [])])
        let morning = song("Morning Invented", SongBackgrounds(defaultBackground: navy))
        let plan = Plan(title: "Invented", items: [PlanItem(id: "morning", kind: .song, song: morning.id),
                                                   PlanItem(id: "deck", kind: .presentation, presentation: deck.id),
                                                   PlanItem(id: "talk", kind: .item, title: "Talk")])
        let program = Program(plan: plan, songs: [morning.id: morning], presentations: [deck.id: deck], mode: .separateSlides)
        let song = program.cuePosition(at: 0), slides = program.slides.indices.filter { program.slides[$0].item > 0 }
        XCTAssertEqual(song?.songBackground, navy)
        XCTAssertEqual(song?.section, program.slides[0].sectionID)
        for index in slides {
            let position = program.cuePosition(at: index)
            XCTAssertNil(position?.songBackground)
            XCTAssertNil(position?.partBackground)
            XCTAssertNil(backgroundCue(previous: song, current: position!), "a presentation or plain item leaves the background")
        }
        XCTAssertNil(program.cuePosition(at: program.slides.count))
    }
}
