import AppKit
import SwiftUI

/// The interface language: the system's, or one the app is translated into.
public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system, en, es
}

/// How Live shows a part sung several times in a row.
public enum RepetitionMode: String, CaseIterable, Sendable {
    /// Every repetition has its own slides, marked "repetition 2 of 3".
    case separateSlides
    /// Each run of repeats is shown once, its name marked "×3".
    case oncePerRun

    /// The localization key of the mode's name.
    var title: String { self == .separateSlides ? "Separate slides for each repetition" : "Show repeated parts once" }
}

/// The user's settings, kept in user defaults; unknown stored values read as the defaults.
public struct AppSettings {
    let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var language: InterfaceLanguage {
        get { defaults.string(forKey: "language").flatMap(InterfaceLanguage.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "language") }
    }
    public var repetitionMode: RepetitionMode {
        get { defaults.string(forKey: "repetitionMode").flatMap(RepetitionMode.init(rawValue:)) ?? .separateSlides }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "repetitionMode") }
    }
}

/// The General settings: the interface language, applied the next time the app opens, and how repeated parts show in Live.
struct SettingsView: View {
    @ObservedObject var state: AppState
    let settings: AppSettings
    @State private var language: InterfaceLanguage

    init(state: AppState, settings: AppSettings) {
        (self.state, self.settings) = (state, settings)
        _language = State(initialValue: settings.language)
    }

    var body: some View {
        Form {
            Picker(Strings.text("Language"), selection: $language) {
                ForEach(InterfaceLanguage.allCases, id: \.self) { Text(Strings.languageName($0)).tag($0) }
            }
            .onChange(of: language) { settings.language = $0 }
            Text(Strings.text("Changes apply the next time you open the app.")).font(.system(size: 11)).foregroundColor(.secondary)
            Picker(Strings.text("Repeated parts"), selection: Binding(get: { state.repetitionMode }, set: { state.perform(.setRepetitionMode($0)) })) {
                ForEach(RepetitionMode.allCases, id: \.self) { Text(Strings.text($0.title)).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// The single Settings window.
final class SettingsWindowController: NSWindowController {
    convenience init(state: AppState, settings: AppSettings) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state, settings: settings)))
        (window.title, window.styleMask) = (Strings.text("Settings"), [.titled, .closable])
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    /// Shows the window, or brings it to the front when it is open.
    func show() {
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }
}
