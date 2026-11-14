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

/// A key color as `#RRGGBB`, the form the settings store.
public struct KeyColor: Equatable, Sendable {
    public let hex: String
    public static let green = KeyColor(hex: "#00B140")!
    public static let blue = KeyColor(hex: "#0047BB")!

    /// A color from `#RRGGBB`, in either case; nil for anything else.
    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        self.hex = hex.uppercased()
    }

    public var rgba: RGBA { RGBA(hex: Int(hex.dropFirst(), radix: 16)!) }
}

/// The user's settings, kept in user defaults; unknown stored values read as the defaults.
public struct AppSettings {
    let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    /// `~/Documents/Global Service Studio Library`; created only when a song is first saved.
    public static let defaultLibraryFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Global Service Studio Library")

    public var language: InterfaceLanguage {
        get { defaults.string(forKey: "language").flatMap(InterfaceLanguage.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "language") }
    }
    public var repetitionMode: RepetitionMode {
        get { defaults.string(forKey: "repetitionMode").flatMap(RepetitionMode.init(rawValue:)) ?? .separateSlides }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "repetitionMode") }
    }
    /// The key output's color; green when unset or not a `#RRGGBB` color.
    public var keyColor: String {
        get { defaults.string(forKey: "keyColor").flatMap(KeyColor.init(hex:))?.hex ?? KeyColor.green.hex }
        nonmutating set { defaults.set(newValue, forKey: "keyColor") }
    }
    public var libraryFolder: URL {
        get { defaults.url(forKey: "libraryFolder") ?? Self.defaultLibraryFolder }
        nonmutating set { defaults.set(newValue, forKey: "libraryFolder") }
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
            KeyColorPicker(state: state).padding(.top, 12)
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// The key output's color: green, blue or any custom color.
struct KeyColorPicker: View {
    @ObservedObject var state: AppState
    @State private var isCustom = false

    var body: some View {
        let current = KeyColor(hex: state.keyColor) ?? .green
        let choice = isCustom || (current != .green && current != .blue) ? "custom" : current.hex
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker(Strings.text("Key color"), selection: Binding(get: { choice }, set: { value in
                    isCustom = value == "custom"
                    if !isCustom { state.perform(.setKeyColor(value)) }
                })) {
                    Text(Strings.text("Green")).tag(KeyColor.green.hex)
                    Text(Strings.text("Blue")).tag(KeyColor.blue.hex)
                    Text(Strings.text("Custom")).tag("custom")
                }
                ColorPicker("", selection: Binding(get: { current.rgba.color }, set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    let hex = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
                    isCustom = true
                    state.perform(.setKeyColor("#" + hex))
                }), supportsOpacity: false)
                .labelsHidden()
                .disabled(choice != "custom")
            }
            Text(Strings.text("The Key output shows the lyrics over this color, for a video switcher to remove. It never shows backgrounds."))
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
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
