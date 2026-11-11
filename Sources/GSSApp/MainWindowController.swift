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
    private var subscription: AnyCancellable?

    init(state: AppState, appearance: Appearance = .standard) {
        self.state = state
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = Strings.appName
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = appearance.window.nsColor
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SidebarPlaceholder()))
        (sidebar.minimumThickness, sidebar.maximumThickness) = (200, 320)
        splitViewController.addSplitViewItem(sidebar)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: NSHostingController(rootView: ModePlaceholder(state: state, appearance: appearance))))
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc func selectMode(_ sender: NSMenuItem) { state.perform(.setMode(AppMode.allCases[sender.tag])) }
    @objc private func modeControlChanged(_ sender: NSSegmentedControl) { state.perform(.setMode(AppMode.allCases[sender.selectedSegment])) }

    @objc func toggleSidebar(_ sender: Any?) { splitViewController.toggleSidebar(sender) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectMode(_:)) {
            menuItem.state = AppMode.allCases[menuItem.tag] == state.mode ? .on : .off
        }
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

struct SidebarPlaceholder: View {
    var body: some View {
        List {
            ForEach(["Service", "Library"], id: \.self) { key in
                Section(Strings.text(key)) {
                    Text(Strings.text("Nothing here yet")).foregroundColor(Color(nsColor: Appearance.labelTertiary.nsColor))
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct ModePlaceholder: View {
    @ObservedObject var state: AppState
    let appearance: Appearance

    var body: some View {
        VStack(spacing: 8) {
            Text(state.mode.title).font(.system(size: 22, weight: .bold)).foregroundColor(Color(nsColor: Appearance.label.nsColor))
            Text(state.mode.explanation).font(.system(size: 13)).foregroundColor(Color(nsColor: Appearance.labelSecondary.nsColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: appearance.window.nsColor))
    }
}
