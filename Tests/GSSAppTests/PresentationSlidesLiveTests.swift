import CoreGraphics
import GSSCore
import GSSLibrary
import ImageIO
import XCTest
@testable import GSSApp

/// Presentation slides in Live and their scaling in Prepare (issue #133); every text and image here is invented.
final class PresentationSlidesLiveTests: XCTestCase {
    private let dawn = Song(title: "Dawn Invented", language: "en", sections: [
        SongSection(id: "v1", kind: .verse, number: 1, lines: [SongLine(text: ["en": "Dawn one"])]),
    ])

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PresentationSlidesLiveTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A small PNG of one invented color.
    private func png(width: Int, height: Int) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB(), info = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A library holding a three-slide imported deck, and a state with it chosen and a service of a song and the deck.
    private func live() throws -> (Library, Presentation, URL, AppState) {
        let library = try Library.open(folder()), id = UUID()
        let images = try library.writeSlideImages([png(width: 40, height: 30), png(width: 30, height: 40), png(width: 16, height: 9)], for: id)
        let deck = Presentation.importedDeck(id: id, title: "Invented Deck", images: images, notes: ["Invented note"])
        let url = try library.save(deck), state = AppState()
        state.perform(.chooseLibraryFolder(library.folder))
        let plan = Plan(title: "Invented", items: [PlanItem(id: "dawn", kind: .song, song: dawn.id), PlanItem(id: "deck", kind: .presentation, presentation: id)])
        state.perform(.openPlan(plan, songs: [dawn], presentations: [deck]))
        return (library, deck, url, state)
    }

    func testScalingRewritesEverySlideSavesTheFileAndTheProgramFollowsInPlace() throws {
        let (library, deck, url, state) = try live()
        state.perform(.goToSlide(2))
        state.perform(.setPresentationScaling(id: deck.id, .fill))
        let saved = try library.loadPresentation(at: url)
        XCTAssertEqual(saved.slides.flatMap(\.elements).map(\.scaling), [.fill, .fill, .fill])
        XCTAssertEqual(saved.slides.map(\.notes), deck.slides.map(\.notes))
        XCTAssertEqual(state.program.slides.map(\.scaling), [.fit, .fill, .fill, .fill])
        XCTAssertEqual(state.program.presentations[deck.id], saved)
        XCTAssertEqual(state.programIndex, 2)
        XCTAssertEqual(state.shownImage, deck.slides[1].elements[0].media)
        XCTAssertEqual(state.liveProgramSlide?.scaling, .fill)
        XCTAssertNil(state.alert)
        state.perform(.setPresentationScaling(id: deck.id, .stretch))
        XCTAssertEqual(try library.loadPresentation(at: url).slides.flatMap(\.elements).map(\.scaling), [.stretch, .stretch, .stretch])
        XCTAssertEqual(state.programIndex, 2)
    }

    func testScalingAPresentationNotInTheServiceChangesNothing() throws {
        let (library, deck, url, state) = try live()
        state.perform(.goToSlide(1))
        let program = state.program
        state.perform(.setPresentationScaling(id: UUID(), .stretch))
        XCTAssertEqual(state.program, program)
        XCTAssertEqual(state.programIndex, 1)
        XCTAssertEqual(try library.loadPresentation(at: url), deck)
        XCTAssertNil(state.alert)
    }

    func testScalingAPresentationWithoutItsFileShowsAnAlertAndChangesNothing() throws {
        let (_, deck, url, state) = try live()
        try FileManager.default.removeItem(at: url)
        let program = state.program
        state.perform(.setPresentationScaling(id: deck.id, .fill))
        XCTAssertEqual(state.program, program)
        XCTAssertEqual(state.alert?.title, Strings.text("The presentation could not be saved."))
        XCTAssertEqual(Strings.text("The presentation could not be saved.", language: "es"), "No se pudo guardar la presentación.")
    }

    func testOnlyPresentationSlidesGetAPictureForTheGridAndPanels() throws {
        let (library, deck, _, state) = try live()
        XCTAssertNil(state.presentationPicture(at: 0), "a song slide keeps its lines")
        XCTAssertNil(state.presentationPicture(at: 4))
        let picture = try XCTUnwrap(state.presentationPicture(at: 1))
        XCTAssertEqual(picture, PresentationPicture(image: deck.slides[0].elements[0].media, scaling: .fit, libraryFolder: library.folder))
    }

    func testFitLeavesTransparentBandsFillCropsAndStretchCoversTheContainer() {
        let container = CGSize(width: 160, height: 90)
        XCTAssertEqual(PresentationSlideLayer.scaledRect(imageSize: CGSize(width: 200, height: 100), outputSize: container, scaling: .fit), CGRect(x: 0, y: 5, width: 160, height: 80))
        XCTAssertEqual(PresentationSlideLayer.scaledRect(imageSize: CGSize(width: 100, height: 200), outputSize: container, scaling: .fit), CGRect(x: 57.5, y: 0, width: 45, height: 90))
        XCTAssertEqual(PresentationSlideLayer.scaledRect(imageSize: CGSize(width: 200, height: 100), outputSize: container, scaling: .fill), CGRect(x: -10, y: 0, width: 180, height: 90))
        XCTAssertEqual(PresentationSlideLayer.scaledRect(imageSize: CGSize(width: 100, height: 200), outputSize: container, scaling: .fill), CGRect(x: 0, y: -115, width: 160, height: 320))
        XCTAssertEqual(PresentationSlideLayer.scaledRect(imageSize: CGSize(width: 100, height: 200), outputSize: container, scaling: .stretch), CGRect(x: 0, y: 0, width: 160, height: 90))
        XCTAssertEqual(PresentationSlideLayer.scaledRect(imageSize: CGSize(width: 32, height: 18), outputSize: container, scaling: .fit), CGRect(x: 0, y: 0, width: 160, height: 90))
        XCTAssertEqual(PresentationSlideLayer.scaledRect(imageSize: .zero, outputSize: container, scaling: .fit), CGRect(x: 0, y: 0, width: 160, height: 90))
    }

    func testScalingNamesAreLocalized() {
        XCTAssertEqual(["Fit", "Fill", "Stretch", "Scaling"].map { Strings.text($0, language: "es") }, ["Encajar", "Rellenar", "Estirar", "Ajuste"])
        XCTAssertEqual(Strings.text("Loading slide…", language: "es"), "Cargando diapositiva…")
    }
}
