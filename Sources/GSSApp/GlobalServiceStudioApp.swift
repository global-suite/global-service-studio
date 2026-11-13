import AppKit

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
    private let state = AppState()
    private lazy var windowController = MainWindowController(state: state)
    private lazy var audienceOutput = AudienceOutputController(state: state, operatorWindow: windowController.window)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = MainMenu.make(output: audienceOutput.menu)
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
