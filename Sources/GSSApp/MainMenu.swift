import AppKit

/// The main menu, built in code.
enum MainMenu {
    /// `output` is the Output menu, kept up to date by its owner.
    static func make(output: NSMenu) -> NSMenu {
        let text = { (key: String) in Strings.text(key) }, name = Strings.appName
        let windowMenu = submenu(text("Window"), [item(text("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"), item(text("Zoom"), #selector(NSWindow.performZoom(_:)))])
        NSApp.windowsMenu = windowMenu.submenu
        let outputMenu = NSMenuItem(title: output.title, action: nil, keyEquivalent: "")
        outputMenu.submenu = output
        let menu = NSMenu()
        [
            submenu(name, [
                item(String(format: text("About %@"), name), #selector(NSApplication.orderFrontStandardAboutPanel(_:))), .separator(),
                item(text("Settings…"), #selector(AppDelegate.showSettings(_:)), ","), .separator(),
                item(String(format: text("Hide %@"), name), #selector(NSApplication.hide(_:)), "h"), .separator(),
                item(String(format: text("Quit %@"), name), #selector(NSApplication.terminate(_:)), "q"),
            ]),
            submenu(text("File"), [
                item(text("Open Song…"), #selector(MainWindowController.openSong(_:)), "o"), item(text("Save Song"), #selector(MainWindowController.saveSong(_:)), "s"),
                item(text("Choose Library Folder…"), #selector(MainWindowController.chooseLibraryFolder(_:))),
            ]),
            submenu(text("Edit"), [
                item(text("Undo"), Selector(("undo:")), "z"), item(text("Redo"), Selector(("redo:")), "Z"), .separator(),
                item(text("Cut"), #selector(NSText.cut(_:)), "x"), item(text("Copy"), #selector(NSText.copy(_:)), "c"),
                item(text("Paste"), #selector(NSText.paste(_:)), "v"), item(text("Select All"), #selector(NSText.selectAll(_:)), "a"),
            ]),
            submenu(text("View"), [
                item(AppMode.prepare.title, #selector(MainWindowController.selectMode(_:)), "1", tag: 0),
                item(AppMode.live.title, #selector(MainWindowController.selectMode(_:)), "2", tag: 1), .separator(),
                item(text("Previous Slide"), #selector(MainWindowController.goToPreviousSlide(_:))),
                item(text("Next Slide"), #selector(MainWindowController.goToNextSlide(_:))), .separator(),
                item(text("Show or Hide Sidebar"), #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
            ]),
            outputMenu,
            windowMenu,
        ].forEach(menu.addItem)
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        (item.keyEquivalentModifierMask, item.tag) = (modifiers, tag)
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""), menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }
}
