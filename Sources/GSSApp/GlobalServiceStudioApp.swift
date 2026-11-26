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
    private lazy var keyOutput = AudienceOutputController(state: state, role: .key, operatorWindow: windowController.window)
    private lazy var stageOutput = AudienceOutputController(state: state, role: .stage, operatorWindow: windowController.window)
    private lazy var backgroundMenu = BackgroundMenuController(state: state)
    private lazy var serviceMenus = ServiceMenus(state: state)
    /// The developer measurement, only when launched with `--measure-live` (docs/live-measurement.md).
    private var measurement: LiveMeasurement?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = MainMenu.make(output: OutputMenu.make(audience: audienceOutput.menu, key: keyOutput.menu, stage: stageOutput.menu, background: backgroundMenu.menu), services: serviceMenus)
        windowController.showWindow(nil)
        state.perform(.openLaunchService)
        state.perform(.openMostRecentSong)
        state.perform(.openLibraryIndex)
        NSApp.activate(ignoringOtherApps: true)
        measurement = LiveMeasurement.startIfRequested(state: state, operatorWindow: windowController.window)
    }

    @objc func showSettings(_ sender: Any?) { settingsWindow.show() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Asks to save unsaved changes to the service before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windowController.mayReplaceService(quitting: true) ? .terminateNow : .terminateCancel
    }
}
