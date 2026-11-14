import AppKit
import GSSLibrary

/// Starts the application.
public enum GlobalServiceStudioApp {
    /// Runs the app until it quits.
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var state = AppState(settings: settings, indexURL: LibraryIndex.defaultURL)
    private lazy var settingsWindow = SettingsWindowController(state: state, settings: settings)
    private lazy var windowController = MainWindowController(state: state)
    private lazy var audienceOutput = AudienceOutputController(state: state, operatorWindow: windowController.window)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = MainMenu.make(output: audienceOutput.menu)
        windowController.showWindow(nil)
        state.perform(.openMostRecentSong)
        state.perform(.openLibraryIndex)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings(_ sender: Any?) { settingsWindow.show() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
