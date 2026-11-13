import AppKit
import Combine
import SwiftUI

/// A connected display as the Output menu lists it.
struct ScreenInfo: Equatable {
    let id: ScreenID
    let name: String

    /// The connected displays in the system's order, the menu bar display first.
    static func connected() -> [ScreenInfo] {
        NSScreen.screens.compactMap { screen in screen.displayID.map { ScreenInfo(id: $0, name: screen.localizedName) } }
    }
}

extension NSScreen {
    var displayID: ScreenID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}

/// The display the audience output uses by default: the first, in order, that does not hold the operator window; nil with a single display.
/// When the operator's display is unknown, the first display counts as the operator's.
func defaultOutputScreen(screens: [ScreenInfo], operatorScreenID: ScreenID?) -> ScreenInfo? {
    guard screens.count > 1 else { return nil }
    let operatorID = operatorScreenID ?? screens[0].id
    return screens.first { $0.id != operatorID }
}

/// A borderless window over a whole display, above the menu bar, that never takes keyboard focus or mouse events.
final class OutputWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        (level, backgroundColor, isOpaque, hasShadow, ignoresMouseEvents, isReleasedWhenClosed) = (.screenSaver, .black, true, false, true, false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = content
    }
}

/// What the audience sees: the live lines centered in white on black, or black only while cleared.
struct AudienceOutputView: View {
    @ObservedObject var state: AppState

    /// The lines on the output: the live slide's, none while cleared; past the last slide the last one stays.
    static func lines(_ state: AppState) -> [String] { state.shownLines }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(Array(Self.lines(state).enumerated()), id: \.offset) { Text($0.element) }
            }
            .font(.system(size: geometry.size.height * 0.07, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .padding(.horizontal, geometry.size.width * 0.05)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
    }
}

/// Owns the Output menu and the audience output window. The menu changes the state through commands; the window follows the state.
final class AudienceOutputController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    let state: AppState
    let menu = NSMenu(title: Strings.text("Output"))
    private(set) var window: OutputWindow?
    private weak var operatorWindow: NSWindow?
    private let screens: () -> [ScreenInfo]
    private var subscription: AnyCancellable?
    private var observer: NSObjectProtocol?

    init(state: AppState, operatorWindow: NSWindow?, screens: @escaping () -> [ScreenInfo] = ScreenInfo.connected) {
        (self.state, self.operatorWindow, self.screens) = (state, operatorWindow, screens)
        super.init()
        menu.delegate = self
        menuNeedsUpdate(menu)
        subscription = state.$isAudienceOutputShown.combineLatest(state.$outputScreen).sink { [weak self] in self?.update(shown: $0, screen: $1) }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// Closes the output when its display disconnects, follows a new size of its display and rebuilds the menu.
    func screensChanged() {
        if let screen = state.outputScreen, !screens().contains(where: { $0.id == screen }) { state.perform(.selectOutputScreen(nil)) }
        update(shown: state.isAudienceOutputShown, screen: state.outputScreen)
        menuNeedsUpdate(menu)
    }

    /// One item per display, an explanation when there is only one, and the show or hide command.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let list = screens()
        menu.removeAllItems()
        for screen in list {
            let item = NSMenuItem(title: screen.name, action: #selector(selectScreen(_:)), keyEquivalent: "")
            (item.target, item.tag) = (self, Int(screen.id))
            menu.addItem(item)
        }
        if list.count < 2 { menu.addItem(withTitle: Strings.text("Connect a second display to show the audience output."), action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: Strings.text("Show Audience Output"), action: #selector(toggleAudienceOutput(_:)), keyEquivalent: "o")
        (toggle.target, toggle.keyEquivalentModifierMask) = (self, [.command, .shift])
        menu.addItem(toggle)
    }

    @objc func selectScreen(_ sender: NSMenuItem) { state.perform(.selectOutputScreen(ScreenID(sender.tag))) }

    /// Hides the output, or shows it, first choosing a display other than the operator's when none is chosen or it is gone.
    @objc func toggleAudienceOutput(_ sender: Any?) {
        guard !state.isAudienceOutputShown else { return state.perform(.showAudienceOutput(false)) }
        let list = screens()
        if !list.contains(where: { $0.id == state.outputScreen }) {
            state.perform(.selectOutputScreen(defaultOutputScreen(screens: list, operatorScreenID: operatorWindow?.screen?.displayID)?.id))
        }
        state.perform(.showAudienceOutput(true))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let canShow = screens().count > 1
        if menuItem.action == #selector(selectScreen(_:)) { menuItem.state = ScreenID(menuItem.tag) == state.outputScreen ? .on : .off }
        if menuItem.action == #selector(toggleAudienceOutput(_:)) {
            menuItem.title = Strings.text(state.isAudienceOutputShown ? "Hide Audience Output" : "Show Audience Output")
            menuItem.toolTip = canShow ? nil : Strings.text("Connect a second display to show the audience output.")
            return canShow || state.isAudienceOutputShown
        }
        return canShow
    }

    /// Covers the chosen display while shown, without taking focus; hidden otherwise or when that display is not connected.
    private func update(shown: Bool, screen id: ScreenID?) {
        guard shown, let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return window?.orderOut(nil) ?? () }
        let window = window ?? OutputWindow(content: NSHostingView(rootView: AudienceOutputView(state: state)))
        self.window = window
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }
}
