import AppKit
import Combine
import CryptoKit
import GSSCore
import GSSLibrary
import ImageIO
import SwiftUI
import XCTest
@testable import GSSApp

final class SongBackgroundPickerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GSSSongBackgroundPickerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// A state whose library is a new folder inside the test folder.
    private func state() -> AppState {
        let name = "GSSSongBackgroundPickerTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.libraryFolder = folder.appendingPathComponent("Library")
        return AppState(settings: settings)
    }

    /// A 4 × 2 red PNG made with Core Graphics.
    private func png(_ name: String, in directory: URL? = nil) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        let url = (directory ?? folder).appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// The library's Media folder, created.
    private func media(_ state: AppState) throws -> URL {
        let media = try Library.open(state.libraryFolder).folder.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        return media
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    func testSettingTheSongDefaultStoresTheLibraryReferenceWithoutGoingOnAir() throws {
        let state = state(), media = try media(state)
        let image = try png("Light.png", in: media), video = media.appendingPathComponent("Waves.mov")
        try Data([0, 0, 0, 1]).write(to: video)
        let (program, index) = (state.program, state.programIndex)
        state.perform(.setSongBackground(section: nil, file: image))
        XCTAssertEqual(state.song.backgrounds, SongBackgrounds(defaultBackground: ThemeBackground(kind: .image, media: MediaReference(path: "Media/Light.png", sha256: try sha256(image)))))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: media.path).sorted(), ["Light.png", "Waves.mov"], "a library file is not copied again")
        state.perform(.setSongBackground(section: nil, file: video))
        XCTAssertEqual(state.song.backgrounds?.defaultBackground, ThemeBackground(kind: .video, media: MediaReference(path: "Media/Waves.mov", sha256: try sha256(video))))
        XCTAssertEqual(state.background, .none, "nothing goes on air")
        XCTAssertEqual(state.programIndex, index)
        XCTAssertEqual(state.program.plan, program.plan)
    }

    func testSettingAPartStoresItUnderTheSectionID() throws {
        let state = state(), image = try png("Light.png", in: try media(state)), section = state.song.sections[1].id
        state.perform(.setSongBackground(section: section, file: image))
        let expected = ThemeBackground(kind: .image, media: MediaReference(path: "Media/Light.png", sha256: try sha256(image)))
        XCTAssertEqual(state.song.backgrounds, SongBackgrounds(sections: [section: expected]))
        state.perform(.setSongBackground(section: "missing", file: image))
        XCTAssertEqual(state.song.backgrounds?.sections, [section: expected], "a section the song does not have is ignored")
    }

    func testRemovingCleansUpTheEmptyContainers() throws {
        let state = state(), image = try png("Light.png", in: try media(state)), section = state.song.sections[0].id
        state.perform(.setSongBackground(section: nil, file: image))
        state.perform(.setSongBackground(section: section, file: image))
        state.perform(.setSongBackground(section: section, file: nil))
        XCTAssertNotNil(state.song.backgrounds?.defaultBackground)
        XCTAssertNil(state.song.backgrounds?.sections)
        state.perform(.setSongBackground(section: nil, file: nil))
        XCTAssertNil(state.song.backgrounds)
    }

    func testTheSameValueAgainLeavesTheSongUnchanged() throws {
        let state = state(), image = try png("Light.png", in: try media(state))
        var published = 0
        let subscription = state.$song.dropFirst().sink { _ in published += 1 }
        state.perform(.setSongBackground(section: nil, file: nil))
        XCTAssertEqual(published, 0, "removing what is not there changes nothing")
        state.perform(.setSongBackground(section: nil, file: image))
        state.perform(.setSongBackground(section: nil, file: image))
        XCTAssertEqual(published, 1)
        subscription.cancel()
    }

    func testAFileOutsideTheLibraryIsImportedIntoMedia() throws {
        let state = state(), outside = try png("Light.png")
        state.perform(.setSongBackground(section: nil, file: outside))
        XCTAssertEqual(state.song.backgrounds?.defaultBackground?.media, MediaReference(path: "Media/Light.png", sha256: try sha256(outside)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.libraryFolder.appendingPathComponent("Media/Light.png").path))
    }

    func testARefusedFileShowsTheAlertAndChangesNothing() throws {
        let state = state(), refused = folder.appendingPathComponent("notes.txt")
        try Data("not media".utf8).write(to: refused)
        let song = state.song
        state.perform(.setSongBackground(section: nil, file: refused))
        XCTAssertEqual(state.alert?.title, Strings.text("Some files could not be added."))
        XCTAssertTrue(state.alert?.message.contains("notes.txt") == true)
        XCTAssertEqual(state.song, song)
    }

    func testTheDisplayHelperDescribesEachCase() throws {
        let state = state(), image = try png("Light.png", in: try media(state)), section = state.song.sections[0].id
        XCTAssertNil(state.songBackgroundChoice(section: nil))
        XCTAssertNil(state.songBackgroundChoice(section: section))
        XCTAssertEqual(SongBackgroundPicker.title(of: nil, isPart: false, language: "en"), "None · transparent")
        XCTAssertEqual(SongBackgroundPicker.title(of: nil, isPart: true, language: "en"), "Same as the song")
        state.perform(.setSongBackground(section: nil, file: image))
        let choice = SongBackgroundChoice(name: "Light", kind: .image, url: state.libraryFolder.appendingPathComponent("Media/Light.png"))
        XCTAssertEqual(state.songBackgroundChoice(section: nil), choice)
        XCTAssertNil(state.songBackgroundChoice(section: section), "a part without its own background follows the song")
        XCTAssertEqual(SongBackgroundPicker.title(of: choice, isPart: true, language: "en"), "Light")
        state.perform(.setSongBackground(section: section, file: image))
        XCTAssertEqual(state.songBackgroundChoice(section: section), choice)
    }

    func testPrepareRendersWithTheBackgroundRowsAt1440x900() throws {
        let state = state()
        state.perform(.setSongBackground(section: nil, file: try png("Light.png", in: try media(state))))
        let host = NSHostingView(rootView: PrepareView(state: state, appearance: .standard))
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testSongBackgroundStringsAreTranslated() {
        for key in ["Song background", "Background of %@", "None · transparent", "Same as the song", "Change…", "Remove", "Use the song's background"] {
            XCTAssertNotEqual(Strings.text(key, language: "es"), key, key)
            XCTAssertEqual(Strings.text(key, language: "en"), key, key)
        }
        XCTAssertEqual(SongBackgroundPicker.title(of: nil, isPart: false, language: "es"), "Ninguno · transparente")
    }
}
