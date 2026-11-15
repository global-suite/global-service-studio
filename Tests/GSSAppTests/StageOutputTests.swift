import AppKit
import GSSCore
import SwiftUI
import XCTest
@testable import GSSApp

/// The stage teleprompter on its own display (issue #96); every text here is invented.
final class StageOutputTests: XCTestCase {
    private let screens = [ScreenInfo(id: 900_001, name: "Built-in"), ScreenInfo(id: 900_002, name: "Projector"),
                           ScreenInfo(id: 900_003, name: "Switcher"), ScreenInfo(id: 900_004, name: "Stage Monitor")]

    /// A state running a song sung as chorus, chorus, verse, with nothing on air.
    private func running() -> AppState {
        let song = Song(title: "Invented Tide", language: "en", sections: [
            SongSection(id: "v1", kind: .verse, number: 1, lines: ["Tide one", "Tide two"].map { SongLine(text: ["en": $0]) }),
            SongSection(id: "c", kind: .chorus, lines: [SongLine(text: ["en": "Tide chorus"])]),
        ])
        var item = PlanItem(id: "tide", kind: .song, song: song.id)
        item.sequence = ["c", "c", "v1"]
        let state = AppState()
        state.perform(.openPlan(Plan(title: "Invented", items: [item]), songs: [song]))
        return state
    }

    func testStageOutputCommandsShowItOnlyWithAChosenDisplay() {
        let state = AppState()
        XCTAssertNil(state.stageOutputScreen)
        state.perform(.showStageOutput(true))
        XCTAssertFalse(state.isStageOutputShown, "no display is chosen yet")
        state.perform(.selectStageOutputScreen(9))
        state.perform(.showStageOutput(true))
        XCTAssertEqual(state.stageOutputScreen, 9)
        XCTAssertTrue(state.isStageOutputShown)
        XCTAssertFalse(state.isAudienceOutputShown)
        XCTAssertFalse(state.isKeyOutputShown)
        state.perform(.showStageOutput(false))
        XCTAssertFalse(state.isStageOutputShown)
        XCTAssertEqual(state.stageOutputScreen, 9, "hiding keeps the display")
        state.perform(.showStageOutput(true))
        state.perform(.selectStageOutputScreen(nil))
        XCTAssertNil(state.stageOutputScreen)
        XCTAssertFalse(state.isStageOutputShown)
    }

    func testADisplayHoldsOneOfTheThreeOutputsInEveryDirection() {
        typealias Output = (select: (ScreenID?) -> AppCommand, show: (Bool) -> AppCommand, screen: (AppState) -> ScreenID?, shown: (AppState) -> Bool)
        let outputs: [Output] = [
            (AppCommand.selectOutputScreen, AppCommand.showAudienceOutput, { $0.outputScreen }, { $0.isAudienceOutputShown }),
            (AppCommand.selectKeyOutputScreen, AppCommand.showKeyOutput, { $0.keyOutputScreen }, { $0.isKeyOutputShown }),
            (AppCommand.selectStageOutputScreen, AppCommand.showStageOutput, { $0.stageOutputScreen }, { $0.isStageOutputShown }),
        ]
        for (a, first) in outputs.enumerated() {
            for (b, second) in outputs.enumerated() where a != b {
                let state = AppState(), third = outputs.indices.first { $0 != a && $0 != b }!
                state.perform(outputs[third].select(5))
                state.perform(outputs[third].show(true))
                state.perform(first.select(7))
                state.perform(first.show(true))
                state.perform(second.select(7))
                state.perform(second.show(true))
                XCTAssertEqual(second.screen(state), 7, "\(b) takes display 7 from \(a)")
                XCTAssertTrue(second.shown(state))
                XCTAssertNil(first.screen(state), "\(a) leaves display 7 for \(b)")
                XCTAssertFalse(first.shown(state))
                XCTAssertEqual(outputs[third].screen(state), 5, "\(third) on another display stays")
                XCTAssertTrue(outputs[third].shown(state))
            }
        }
    }

    func testStageViewShowsTheHeadingTheLiveLinesAndTheNextLines() {
        let state = running()
        XCTAssertEqual(StageOutputView.heading(state), "", "nothing is on air yet")
        XCTAssertEqual(StageOutputView.lines(state), [])
        XCTAssertEqual(StageOutputView.next(state), ["Tide chorus"])
        state.perform(.nextSlide)
        state.perform(.nextSlide)
        let chorus = Strings.text("Chorus")
        XCTAssertEqual(StageOutputView.heading(state), String(format: Strings.text("%1$@ · repetition %2$ld of %3$ld"), chorus, 2, 2))
        XCTAssertEqual(StageOutputView.heading(state), state.liveSlide.heading())
        XCTAssertEqual(StageOutputView.lines(state), ["Tide chorus"])
        XCTAssertEqual(StageOutputView.next(state), ["Tide one", "Tide two"])
        state.perform(.nextSlide)
        XCTAssertEqual(StageOutputView.lines(state), ["Tide one", "Tide two"])
        XCTAssertEqual(StageOutputView.next(state), [Strings.text("End of service")], "the last slide of the program is followed by the end of the service")
    }

    func testClearedStageShowsNoLinesAndNoHeading() {
        let state = running()
        state.perform(.nextSlide)
        state.perform(.clearSlide)
        XCTAssertEqual(StageOutputView.heading(state), "")
        XCTAssertEqual(StageOutputView.lines(state), [])
        XCTAssertEqual(StageOutputView.next(state), [])
        state.perform(.setBackground(.color("#0B1F3A")))
        XCTAssertNil(state.mediaFill(for: .stage), "the stage never shows backgrounds")
        XCTAssertEqual(StageOutputView.background, RGBA(hex: 0x000000))
    }

    func testStageOutputMenuUsesItsOwnTitlesShortcutAndAvoidsTheOtherDisplays() throws {
        let screens = screens, state = AppState()
        let controller = AudienceOutputController(state: state, role: .stage, operatorWindow: nil) { screens }
        let toggle = try XCTUnwrap(controller.menu.items.last)
        XCTAssertEqual(controller.menu.title, Strings.text("Stage Output"))
        XCTAssertEqual(toggle.keyEquivalent, "t")
        XCTAssertEqual(toggle.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertTrue(controller.validateMenuItem(toggle))
        XCTAssertEqual(toggle.title, Strings.text("Show Stage Output"))
        state.perform(.selectOutputScreen(900_002))
        state.perform(.selectKeyOutputScreen(900_003))
        controller.toggleOutput(nil)
        XCTAssertEqual(state.stageOutputScreen, 900_004, "the default display is neither the operator's, the audience's nor the key's")
        XCTAssertTrue(state.isStageOutputShown)
        XCTAssertEqual([state.outputScreen, state.keyOutputScreen], [900_002, 900_003])
        XCTAssertTrue(controller.validateMenuItem(toggle))
        XCTAssertEqual(toggle.title, Strings.text("Hide Stage Output"))
        controller.selectScreen(controller.menu.items[1])
        XCTAssertEqual(state.stageOutputScreen, 900_002)
        XCTAssertNil(state.outputScreen)
        controller.toggleOutput(nil)
        XCTAssertFalse(state.isStageOutputShown)

        let single = AudienceOutputController(state: AppState(), role: .stage, operatorWindow: nil) { [screens[0]] }
        XCTAssertTrue(single.menu.items.map(\.title).contains(Strings.text("Connect a second display to show the stage output.")))
        XCTAssertEqual(defaultOutputScreen(screens: screens, operatorScreenID: 900_001, avoiding: 900_002, 900_003)?.id, 900_004)
        XCTAssertEqual(defaultOutputScreen(screens: Array(screens.prefix(3)), operatorScreenID: 900_001, avoiding: 900_002, 900_003)?.id, 900_002)
    }

    func testOutputMenuHoldsTheStageSubmenuAfterTheKey() {
        let audience = NSMenu(title: "A"), key = NSMenu(title: "K"), stage = NSMenu(title: "S"), background = NSMenu(title: "B")
        let menu = OutputMenu.make(audience: audience, key: key, stage: stage, background: background)
        XCTAssertEqual(menu.items.map(\.submenu), [audience, key, stage, nil, background])
        let other = (NSMenu(title: "A"), NSMenu(title: "K"))
        XCTAssertEqual(OutputMenu.make(audience: other.0, key: other.1).items.map(\.submenu), [other.0, other.1], "without a stage menu it stays as before")
    }

    func testStageOutputStringsAreTranslated() {
        for key in ["Stage Output", "Show Stage Output", "Hide Stage Output", "Connect a second display to show the stage output.", "End of service"] {
            XCTAssertNotEqual(Strings.text(key, language: "es"), key, key)
            XCTAssertEqual(Strings.text(key, language: "en"), key, key)
        }
    }

    func testStageViewLaysOutFullScreenAndInThePreview() {
        let state = running()
        state.perform(.nextSlide)
        for size in [NSSize(width: 1920, height: 1080), NSSize(width: 320, height: 180)] {
            let view = NSHostingView(rootView: StageOutputView(state: state))
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(view.fittingSize.height, 0)
        }
        let preview = NSHostingView(rootView: OutputMonitor(output: LiveOutput.samples[2], state: state, width: 320))
        preview.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        preview.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(preview.fittingSize.height, 0)
    }
}
