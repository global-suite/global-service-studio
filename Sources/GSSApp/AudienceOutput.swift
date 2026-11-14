import AppKit
import Combine
import GSSCore
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

/// The display an output uses by default: the first, in order, that holds neither the operator window nor the other output (`avoiding`),
/// else the first without the operator window; nil with a single display. When the operator's display is unknown, the first display counts as the operator's.
func defaultOutputScreen(screens: [ScreenInfo], operatorScreenID: ScreenID?, avoiding other: ScreenID? = nil) -> ScreenInfo? {
    guard screens.count > 1 else { return nil }
    let operatorID = operatorScreenID ?? screens[0].id
    return screens.first { $0.id != operatorID && $0.id != other } ?? screens.first { $0.id != operatorID }
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

/// The slide layer: the live lines in white over transparency, nothing while cleared (ADR 0008).
struct SlideLayer: View {
    let lines: [String]
    let alignment: Alignment

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { Text($0.element) }
            }
            .font(.system(size: geometry.size.height * 0.07, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(alignment == .center ? 0 : 0.6), radius: 2, y: 1)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .padding(.horizontal, geometry.size.width * 0.05)
            .padding(.bottom, alignment == .bottom ? geometry.size.height * 0.08 : 0)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
        }
    }
}

/// What the audience sees: the screen color layer, the media layer with the background, then the slide layer.
struct AudienceOutputView: View {
    @ObservedObject var state: AppState
    /// The screen color layer, under the background.
    static let background = RGBA(hex: 0x000000)

    /// The lines on the output: the live slide's, none while cleared; past the last slide the last one stays.
    static func lines(_ state: AppState) -> [String] { state.shownLines }

    var body: some View {
        ZStack {
            Self.background.color
            MediaLayer(fill: state.mediaFill(for: .audience))
            SlideLayer(lines: Self.lines(state), alignment: .center)
        }
    }
}

/// What a video switcher receives: the slide layer in the lower third over the key color, never backgrounds (ADR 0008).
struct KeyOutputView: View {
    @ObservedObject var state: AppState

    static func lines(_ state: AppState) -> [String] { state.shownLines }
    static func background(_ state: AppState) -> RGBA { (KeyColor(hex: state.keyColor) ?? .green).rgba }

    var body: some View {
        ZStack {
            Self.background(state).color
            SlideLayer(lines: Self.lines(state), alignment: .bottom)
        }
    }
}

/// The Output menu: one submenu for each output, then the Background submenu when given.
enum OutputMenu {
    static func make(audience: NSMenu, key: NSMenu, background: NSMenu? = nil) -> NSMenu {
        let menu = NSMenu(title: Strings.text("Output"))
        for submenu in [audience, key] + (background.map { [$0] } ?? []) {
            if submenu === background { menu.addItem(.separator()) }
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }
}

/// Owns one output's menu and window, for the audience or the key role. The menu changes the state through commands; the window follows the state.
final class AudienceOutputController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    let state: AppState
    let role: OutputRole
    let menu: NSMenu
    private(set) var window: OutputWindow?
    private weak var operatorWindow: NSWindow?
    private let screens: () -> [ScreenInfo]
    private var subscription: AnyCancellable?
    private var observer: NSObjectProtocol?

    init(state: AppState, role: OutputRole = .audience, operatorWindow: NSWindow?, screens: @escaping () -> [ScreenInfo] = ScreenInfo.connected) {
        (self.state, self.role, self.operatorWindow, self.screens) = (state, role, operatorWindow, screens)
        menu = NSMenu(title: Strings.text(role == .key ? "Key Output" : "Audience Output"))
        super.init()
        menu.delegate = self
        menuNeedsUpdate(menu)
        let shown = role == .key ? state.$isKeyOutputShown : state.$isAudienceOutputShown, screen = role == .key ? state.$keyOutputScreen : state.$outputScreen
        subscription = shown.combineLatest(screen).sink { [weak self] in self?.update(shown: $0, screen: $1) }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private var isShown: Bool { role == .key ? state.isKeyOutputShown : state.isAudienceOutputShown }
    private var screen: ScreenID? { role == .key ? state.keyOutputScreen : state.outputScreen }
    private var otherScreen: ScreenID? { role == .key ? state.outputScreen : state.keyOutputScreen }
    private func select(_ screen: ScreenID?) { state.perform(role == .key ? .selectKeyOutputScreen(screen) : .selectOutputScreen(screen)) }
    private func show(_ shown: Bool) { state.perform(role == .key ? .showKeyOutput(shown) : .showAudienceOutput(shown)) }
    private var connectMessage: String {
        Strings.text(role == .key ? "Connect a second display to show the key output." : "Connect a second display to show the audience output.")
    }

    /// Closes the output when its display disconnects, follows a new size of its display and rebuilds the menu.
    func screensChanged() {
        if let screen, !screens().contains(where: { $0.id == screen }) { select(nil) }
        update(shown: isShown, screen: screen)
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
        if list.count < 2 { menu.addItem(withTitle: connectMessage, action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: Strings.text(role == .key ? "Show Key Output" : "Show Audience Output"), action: #selector(toggleOutput(_:)), keyEquivalent: role == .key ? "k" : "o")
        (toggle.target, toggle.keyEquivalentModifierMask) = (self, [.command, .shift])
        menu.addItem(toggle)
    }

    @objc func selectScreen(_ sender: NSMenuItem) { select(ScreenID(sender.tag)) }

    /// Hides the output, or shows it, first choosing a display other than the operator's and the other output's when none is chosen or it is gone.
    @objc func toggleOutput(_ sender: Any?) {
        guard !isShown else { return show(false) }
        let list = screens()
        if !list.contains(where: { $0.id == screen }) {
            select(defaultOutputScreen(screens: list, operatorScreenID: operatorWindow?.screen?.displayID, avoiding: otherScreen)?.id)
        }
        show(true)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let canShow = screens().count > 1
        if menuItem.action == #selector(selectScreen(_:)) { menuItem.state = ScreenID(menuItem.tag) == screen ? .on : .off }
        if menuItem.action == #selector(toggleOutput(_:)) {
            let titles = role == .key ? ("Hide Key Output", "Show Key Output") : ("Hide Audience Output", "Show Audience Output")
            menuItem.title = Strings.text(isShown ? titles.0 : titles.1)
            menuItem.toolTip = canShow ? nil : connectMessage
            return canShow || isShown
        }
        return canShow
    }

    /// Covers the chosen display while shown, without taking focus; hidden otherwise or when that display is not connected.
    private func update(shown: Bool, screen id: ScreenID?) {
        guard shown, let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return window?.orderOut(nil) ?? () }
        let content = role == .key ? NSHostingView(rootView: AnyView(KeyOutputView(state: state))) : NSHostingView(rootView: AnyView(AudienceOutputView(state: state)))
        let window = window ?? OutputWindow(content: content)
        self.window = window
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }
}
