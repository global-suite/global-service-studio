import AppKit
import CoreAudio
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
    /// The Core Audio UID of the device full-screen videos play their sound on; nil is the system default.
    public var audioOutputDeviceUID: String? {
        get { defaults.string(forKey: "audioOutputDeviceUID") }
        nonmutating set { defaults.set(newValue, forKey: "audioOutputDeviceUID") }
    }
}

/// The General settings: the interface language, applied the next time the app opens, and how repeated parts show in Live.
struct SettingsView: View {
    @ObservedObject var state: AppState
    let settings: AppSettings
    @State private var language: InterfaceLanguage
    @State private var audioDevice: String?
    private let audioDevices = AudioOutputDevice.all()

    init(state: AppState, settings: AppSettings) {
        (self.state, self.settings) = (state, settings)
        _language = State(initialValue: settings.language)
        _audioDevice = State(initialValue: settings.audioOutputDeviceUID)
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
            Picker(Strings.text("Video sound"), selection: $audioDevice) {
                Text(Strings.text("System default")).tag(String?.none)
                ForEach(audioDevices, id: \.uid) { Text($0.name).tag(Optional($0.uid)) }
            }
            .onChange(of: audioDevice) { settings.audioOutputDeviceUID = $0 }
            .padding(.top, 12)
            Text(Strings.text("Full-screen videos play their sound on this device. Backgrounds are always muted."))
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
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

/// An audio device with output streams, from Core Audio.
struct AudioOutputDevice: Equatable {
    let uid, name: String

    /// The connected devices that can play sound; none when Core Audio cannot list them.
    static func all() -> [AudioOutputDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = Self.address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = Self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput), count: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &count) == noErr, count > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioOutputDevice(uid: uid, name: name)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector), value: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
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
