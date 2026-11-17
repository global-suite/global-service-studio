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

/// The display an output uses by default: the first, in order, that holds neither the operator window nor another output (`avoiding`),
/// else the first without the operator window; nil with a single display. When the operator's display is unknown, the first display counts as the operator's.
func defaultOutputScreen(screens: [ScreenInfo], operatorScreenID: ScreenID?, avoiding others: ScreenID?...) -> ScreenInfo? {
    defaultOutputScreen(screens: screens, operatorScreenID: operatorScreenID, avoiding: others)
}

func defaultOutputScreen(screens: [ScreenInfo], operatorScreenID: ScreenID?, avoiding others: [ScreenID?]) -> ScreenInfo? {
    guard screens.count > 1 else { return nil }
    let operatorID = operatorScreenID ?? screens[0].id
    return screens.first { $0.id != operatorID && !others.contains($0.id) } ?? screens.first { $0.id != operatorID }
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

/// The slide layer: the live lines in a theme slot over transparency, nothing while cleared (ADR 0008).
/// Each line shrinks to fit the slot's width, and the font shrinks so every line fits its height.
struct SlideLayer: View {
    let lines: [String]
    let slot: ThemeSlot
    /// A soft shadow under the text, which the key output uses.
    var shadow = false

    var body: some View {
        GeometryReader { geometry in
            let layout = SlotLayout(slot: slot, size: geometry.size, lineCount: lines.count)
            VStack(alignment: layout.alignment.horizontal, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { Text($0.element) }
            }
            .font(Font(layout.font as CTFont))
            .foregroundColor(layout.color.color)
            .shadow(color: .black.opacity(shadow ? 0.6 : 0), radius: 2, y: 1)
            .multilineTextAlignment(layout.textAlignment)
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .frame(width: layout.frame.width, height: layout.frame.height, alignment: layout.alignment)
            .position(x: layout.frame.midX, y: layout.frame.midY)
        }
    }
}

/// What the audience sees: the screen color layer, the media layer with the background, then the slide layer.
struct AudienceOutputView: View {
    @ObservedObject var state: AppState
    var theme = OutputThemes.theme(for: .audience)
    /// The screen color layer, under the background.
    static let background = RGBA(hex: 0x000000)

    /// The lines on the output: the live slide's, none while cleared; past the last slide the last one stays.
    static func lines(_ state: AppState) -> [String] { state.shownLines }
    /// The slide layer: a presentation slide's image with its scaling, its bands transparent over the media layer, else the lines.
    static func content(_ state: AppState) -> SlideContent { SlideContent(state) }

    var body: some View {
        ZStack {
            Self.background.color
            MediaLayer(fill: state.mediaFill(for: .audience, theme: theme))
            SlideContentLayer(content: Self.content(state), slot: OutputThemes.lyricsSlot(of: theme), libraryFolder: state.libraryFolder)
        }
    }
}

/// What a video switcher receives: the slide layer in the lower third over the key color, never backgrounds (ADR 0008).
struct KeyOutputView: View {
    @ObservedObject var state: AppState
    var theme = OutputThemes.theme(for: .key)

    static func lines(_ state: AppState) -> [String] { state.shownLines }
    static func background(_ state: AppState) -> RGBA { (KeyColor(hex: state.keyColor) ?? .green).rgba }
    /// The slide layer: a presentation slide full frame ("Se muestra completa"), so fit becomes fill; else the lines.
    static func content(_ state: AppState) -> SlideContent { SlideContent(state) { $0 == .fit ? .fill : $0 } }

    var body: some View {
        ZStack {
            Self.background(state).color
            SlideContentLayer(content: Self.content(state), slot: OutputThemes.lyricsSlot(of: theme), libraryFolder: state.libraryFolder, shadow: true)
        }
    }
}

/// The Output menu: one submenu for each output, then the Background submenu when given.
enum OutputMenu {
    static func make(audience: NSMenu, key: NSMenu, stage: NSMenu? = nil, background: NSMenu? = nil) -> NSMenu {
        let menu = NSMenu(title: Strings.text("Output"))
        for submenu in [audience, key] + [stage, background].compactMap({ $0 }) {
            if submenu === background { menu.addItem(.separator()) }
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }
}

/// Owns one output's menu and window, for the audience, key or stage role. The menu changes the state through commands; the window follows the state.
final class AudienceOutputController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    let state: AppState
    let role: OutputRole
    let menu: NSMenu
    private(set) var window: OutputWindow?
    private weak var operatorWindow: NSWindow?
    private let screens: () -> [ScreenInfo]
    private var subscription: AnyCancellable?
    private var observer: NSObjectProtocol?
    private var preloading: AnyCancellable?

    /// The audience controller preloads the next slide's image into `imageCache` whenever the live slide or the program changes.
    init(state: AppState, role: OutputRole = .audience, operatorWindow: NSWindow?, screens: @escaping () -> [ScreenInfo] = ScreenInfo.connected,
         imageCache: SlideImageCache = .shared) {
        (self.state, self.role, self.operatorWindow, self.screens) = (state, role, operatorWindow, screens)
        menu = NSMenu(title: Strings.text(Self.texts[role]!.title))
        super.init()
        menu.delegate = self
        menuNeedsUpdate(menu)
        let shown = [.key: state.$isKeyOutputShown, .stage: state.$isStageOutputShown][role] ?? state.$isAudienceOutputShown
        let screen = [.key: state.$keyOutputScreen, .stage: state.$stageOutputScreen][role] ?? state.$outputScreen
        subscription = shown.combineLatest(screen).sink { [weak self] in self?.update(shown: $0, screen: $1) }
        if role == .audience {
            // Published before the change; the main queue hop reads the new live slide.
            preloading = state.$programIndex.combineLatest(state.$program).receive(on: DispatchQueue.main)
                .sink { [weak state] _ in state?.preloadNextSlideImage(cache: imageCache) }
        }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// Each role's menu title, show and hide items, shortcut with Command-Shift, and message when only one display is connected.
    private static let texts: [OutputRole: (title: String, show: String, hide: String, key: String, connect: String)] = [
        .audience: ("Audience Output", "Show Audience Output", "Hide Audience Output", "o", "Connect a second display to show the audience output."),
        .key: ("Key Output", "Show Key Output", "Hide Key Output", "k", "Connect a second display to show the key output."),
        .stage: ("Stage Output", "Show Stage Output", "Hide Stage Output", "t", "Connect a second display to show the stage output."),
    ]
    private var texts: (title: String, show: String, hide: String, key: String, connect: String) { Self.texts[role]! }
    private var isShown: Bool { [.key: state.isKeyOutputShown, .stage: state.isStageOutputShown][role] ?? state.isAudienceOutputShown }
    private var screen: ScreenID? { [.key: state.keyOutputScreen, .stage: state.stageOutputScreen][role] ?? state.outputScreen }
    private var otherScreens: [ScreenID?] {
        [.audience: state.outputScreen, .key: state.keyOutputScreen, .stage: state.stageOutputScreen].filter { $0.key != role }.map(\.value)
    }
    private func select(_ screen: ScreenID?) {
        state.perform([.key: .selectKeyOutputScreen(screen), .stage: .selectStageOutputScreen(screen)][role] ?? .selectOutputScreen(screen))
    }
    private func show(_ shown: Bool) { state.perform([.key: .showKeyOutput(shown), .stage: .showStageOutput(shown)][role] ?? .showAudienceOutput(shown)) }
    private var connectMessage: String { Strings.text(texts.connect) }

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
        let toggle = NSMenuItem(title: Strings.text(texts.show), action: #selector(toggleOutput(_:)), keyEquivalent: texts.key)
        (toggle.target, toggle.keyEquivalentModifierMask) = (self, [.command, .shift])
        menu.addItem(toggle)
    }

    @objc func selectScreen(_ sender: NSMenuItem) { select(ScreenID(sender.tag)) }

    /// Hides the output, or shows it, first choosing a display other than the operator's and the other outputs' when none is chosen or it is gone.
    @objc func toggleOutput(_ sender: Any?) {
        guard !isShown else { return show(false) }
        let list = screens()
        if !list.contains(where: { $0.id == screen }) {
            select(defaultOutputScreen(screens: list, operatorScreenID: operatorWindow?.screen?.displayID, avoiding: otherScreens)?.id)
        }
        show(true)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let canShow = screens().count > 1
        if menuItem.action == #selector(selectScreen(_:)) { menuItem.state = ScreenID(menuItem.tag) == screen ? .on : .off }
        if menuItem.action == #selector(toggleOutput(_:)) {
            menuItem.title = Strings.text(isShown ? texts.hide : texts.show)
            menuItem.toolTip = canShow ? nil : connectMessage
            return canShow || isShown
        }
        return canShow
    }

    /// Covers the chosen display while shown, without taking focus; hidden otherwise or when that display is not connected.
    private func update(shown: Bool, screen id: ScreenID?) {
        guard shown, let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return window?.orderOut(nil) ?? () }
        let view = [.key: AnyView(KeyOutputView(state: state)), .stage: AnyView(StageOutputView(state: state))][role] ?? AnyView(AudienceOutputView(state: state))
        let content = NSHostingView(rootView: view)
        let window = window ?? OutputWindow(content: content)
        self.window = window
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }
}
