import AppKit
import Combine
import SwiftUI

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

extension NSToolbarItem.Identifier {
    static let mode = NSToolbarItem.Identifier("mode")
}

/// The main window: unified toolbar with the mode switch, a sidebar and the content of the current mode.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let state: AppState
    let modeControl = NSSegmentedControl(labels: AppMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let splitViewController = NSSplitViewController()
    private var subscription, alertSubscription: AnyCancellable?
    private var keyMonitor: Any?

    init(state: AppState, appearance: Appearance = .standard) {
        self.state = state
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = Strings.appName
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = appearance.window.nsColor
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: Sidebar(state: state)))
        (sidebar.minimumThickness, sidebar.maximumThickness) = (200, 320)
        splitViewController.addSplitViewItem(sidebar)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: NSHostingController(rootView: ModeContent(state: state, appearance: appearance))))
        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.contentMinSize = NSSize(width: 1100, height: 700)
        window.center()
        super.init(window: window)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.centeredItemIdentifier = .mode
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        (modeControl.target, modeControl.action) = (self, #selector(modeControlChanged(_:)))
        modeControl.toolTip = Strings.text("Switch between Prepare and Live")
        subscription = state.$mode.sink { [weak self] in self?.modeControl.selectedSegment = AppMode.allCases.firstIndex(of: $0) ?? 0 }
        alertSubscription = state.$alert.compactMap { $0 }.sink { [weak self] in self?.show($0) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.handleKey($0) ?? $0 }
    }

    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc func selectMode(_ sender: NSMenuItem) { state.perform(.setMode(AppMode.allCases[sender.tag])) }
    @objc func goToNextSlide(_ sender: Any?) { state.perform(.nextSlide) }
    @objc func goToPreviousSlide(_ sender: Any?) { state.perform(.previousSlide) }

    /// In Live mode, Space and Right arrow go to the next slide, Left arrow to the previous one, F1 clears the slide and F3 clears all.
    /// In Prepare mode, outside the words editor, Left and Right arrows select the previous or next part and Delete removes it from the order;
    /// with a plan item selected, Option-Up and Option-Down move it in the service and Delete removes it instead.
    /// With a Library song open, Command-Return adds it after the selected plan item and Option-Command-Return at the end. Returns nil when the key was used.
    func handleKey(_ event: NSEvent) -> NSEvent? {
        let part = state.selectedPart, option = event.modifierFlags.contains(.option)
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if [36, 76].contains(event.keyCode), flags == .command || flags == [.command, .option], state.openSongFile != nil,
           event.window === window, !(window?.firstResponder is NSText) {
            state.addOpenSongToService(atEnd: option)
            return nil
        }
        var commands: [UInt16: AppCommand] = state.mode == .live ? [49: .nextSlide, 124: .nextSlide, 123: .previousSlide, 122: .clearSlide, 120: .clearBackground, 99: .clearAll]
            : [123: .selectPart(part - 1), 124: .selectPart(part + 1), 51: .removeArrangementItem(at: part), 117: .removeArrangementItem(at: part)]
        if state.mode == .prepare, let item = state.selectedPlanItem {
            commands = option ? [126: .movePlanItem(from: item, to: item - 1), 125: .movePlanItem(from: item, to: item + 1)] : [51: .removePlanItem(at: item), 117: .removePlanItem(at: item)]
        }
        let blocked: NSEvent.ModifierFlags = option && state.mode == .prepare ? [.command, .control] : [.command, .control, .option]
        guard event.window === window, !(window?.firstResponder is NSText),
              event.modifierFlags.isDisjoint(with: blocked), let command = commands[event.keyCode] else { return event }
        state.perform(command)
        return nil
    }
    @objc private func modeControlChanged(_ sender: NSSegmentedControl) { state.perform(.setMode(AppMode.allCases[sender.selectedSegment])) }

    @objc func toggleSidebar(_ sender: Any?) { splitViewController.toggleSidebar(sender) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectMode(_:)) {
            menuItem.state = AppMode.allCases[menuItem.tag] == state.mode ? .on : .off
        }
        if menuItem.action == #selector(goToNextSlide(_:)) { return state.mode == .live && state.nextSlide != nil }
        if menuItem.action == #selector(goToPreviousSlide(_:)) { return state.mode == .live && state.previousSlide != nil }
        return true
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .mode, .flexibleSpace] }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == .mode else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        (item.view, item.label) = (modeControl, Strings.text("Mode"))
        return item
    }

    func toolbarWillAddItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem, item.itemIdentifier == .toggleSidebar else { return }
        item.toolTip = Strings.text("Show or hide the sidebar")
    }
}

extension AppState {
    /// Adds the Library song open in the sidebar after the plan item selected in Prepare, at the end when none is or when `atEnd`; it never goes on air.
    func addOpenSongToService(atEnd: Bool) {
        guard let url = openSongFile else { return }
        let count = program.plan.items.count, after = atEnd || mode != .prepare ? nil : selectedPlanItem
        perform(.addToService(url, position: .end))
        if let after, program.plan.items.count == count + 1 { perform(.movePlanItem(from: count, to: after + 1)) }
    }
}

struct ModeContent: View {
    @ObservedObject var state: AppState
    let appearance: Appearance
    /// Whether Prepare shows the whole service as a run sheet instead of the selected item.
    @State private var showsRunSheet = false

    var body: some View {
        if state.mode == .live { LiveView(state: state, appearance: appearance) }
        else {
            VStack(spacing: 0) {
                if !state.program.plan.items.isEmpty { PrepareViewBar(showsRunSheet: $showsRunSheet).background(appearance.window.color) }
                if showsRunSheet && !state.program.plan.items.isEmpty { RunSheetView(state: state, appearance: appearance) }
                else if let item = state.selectedPlanItem, state.program.plan.items.indices.contains(item) { PlanItemEditor(state: state, appearance: appearance, index: item) }
                else { PrepareView(state: state, appearance: appearance) }
            }
        }
    }
}
