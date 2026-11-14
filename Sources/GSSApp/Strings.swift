import Foundation
import GSSCore
import GSSLibrary

/// Looks up user-facing strings in this module's `Localizable.strings`, in the language chosen in Settings or else the system's.
enum Strings {
    static let bundle = Bundle.module
    /// Chosen explicitly: without an app bundle, Foundation follows the executable, which has no localizations.
    static let language = language(for: AppSettings().language, system: Locale.preferredLanguages)
    static func language(for preferences: [String]) -> String { Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: preferences).first ?? "en" }
    static func language(for setting: InterfaceLanguage, system: [String]) -> String { language(for: setting == .system ? system : [setting.rawValue]) }
    /// A language's name in that language, such as "Español"; the system choice in the interface language.
    static func languageName(_ choice: InterfaceLanguage, language: String = language) -> String {
        switch choice {
        case .system: return text("System", language: language)
        case .en: return "English"
        case .es: return "Español"
        }
    }

    static func text(_ key: String, language: String = language) -> String {
        let localized = bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
        return localized.localizedString(forKey: key, value: nil, table: nil)
    }

    static var appName: String { text("Global Service Studio") }
    /// A slide count such as "1 slide" or "2 slides", with the plural rules of the language (Localizable.stringsdict).
    static func slideCount(_ count: Int, language: String = language) -> String {
        String(format: text("%ld slides", language: language), locale: Locale(identifier: language), count)
    }
    /// A song count such as "1 song" or "2 songs", under the library search field.
    static func songCount(_ count: Int, language: String = language) -> String {
        String(format: text("%ld songs", language: language), locale: Locale(identifier: language), count)
    }
    /// The title of the library's problems row, such as "Problems (2)".
    static func problemsTitle(_ count: Int, language: String = language) -> String {
        String(format: text("Problems (%ld)", language: language), locale: Locale(identifier: language), count)
    }
    /// The name of a section: for a known kind, its kind and number in the interface language, such as "Verse 2",
    /// whatever label the file wrote; otherwise its label as written, or its kind.
    static func sectionName(_ section: SongSection, language: String = language) -> String {
        let kinds = ["verse": "Verse", "chorus": "Chorus", "prechorus": "Pre-Chorus", "bridge": "Bridge", "intro": "Intro",
                     "outro": "Outro", "tag": "Tag", "interlude": "Interlude", "ending": "Ending"]
        guard let key = kinds[section.kind.rawValue] else { return section.label ?? section.kind.rawValue }
        let kind = text(key, language: language)
        return section.number.map { String(format: text("%1$@ %2$ld", language: language), kind, $0) } ?? kind
    }
    /// The kinds the Add Part menu creates, with their menu title, which is also the placeholder words of the new section.
    static let newSectionKinds: [(kind: SongSectionKind, title: String)] = [(.verse, "New Verse"), (.chorus, "New Chorus"), (.prechorus, "New Pre-Chorus"), (.bridge, "New Bridge"), (.ending, "New Ending")]
    /// The words a new section starts with: its menu title, or its name for other kinds.
    static func newSectionText(_ section: SongSection, language: String = language) -> String {
        newSectionKinds.first { $0.kind == section.kind }.map { text($0.title, language: language) } ?? sectionName(section, language: language)
    }
}

extension Strings {
    /// Why a library folder could not be opened or a song saved.
    static func libraryMessage(for error: Error, language: String = language) -> String {
        switch error {
        case LibraryError.folderNotEmpty: return text("This folder is not empty and is not a library. Choose an empty folder or an existing library.", language: language)
        case FormatError.wrongFormat: return text("The library.json file in this folder belongs to another app.", language: language)
        case FormatError.unsupportedVersion: return text("This library was made by a newer version of Global Service Studio.", language: language)
        default: return text("The folder could not be read or written. Check that it exists and that you can change it.", language: language)
        }
    }
}

extension AppMode {
    /// The localized name of the mode.
    public var title: String { Strings.text(self == .prepare ? "Prepare" : "Live") }
}

extension Strings {
    /// The short mark of a repetition, such as "2/3", on slide thumbnails and song order chips; nil when the part is not repeated.
    static func repetitionMark(_ repetition: Int, of count: Int, language: String = language) -> String? {
        count > 1 ? String(format: text("%1$ld/%2$ld", language: language), repetition, count) : nil
    }
    /// The mark under a part of the song order: "×3" on the first part of a run of repeats, "2/3" and "3/3" on the others,
    /// "repeat" on a part sung earlier but not right before, or nil.
    static func orderMark(_ part: SongPart, language: String = language) -> String? {
        if part.repetitionCount > 1 && part.repetition == 1 { return String(format: text("×%ld", language: language), part.repetitionCount) }
        return repetitionMark(part.repetition, of: part.repetitionCount, language: language) ?? (part.isRepeat ? text("repeat", language: language) : nil)
    }
}

extension LiveSlide {
    /// The section, the repetition when the part repeats, and the slide's place in it, such as "Chorus · repetition 2 of 3 · 1 of 2".
    public var position: String { position() }
    func position(language: String = Strings.language) -> String {
        repetitionCount > 1
            ? String(format: Strings.text("%1$@ · repetition %2$ld of %3$ld · %4$ld of %5$ld", language: language), section, repetition, repetitionCount, part, partCount)
            : String(format: Strings.text("%1$@ · %2$ld of %3$ld", language: language), section, part, partCount)
    }
    /// The section, with the repetition when the part repeats, such as "Chorus · repetition 2 of 3"; on the stage output.
    func heading(language: String = Strings.language) -> String {
        repetitionCount > 1 ? String(format: Strings.text("%1$@ · repetition %2$ld of %3$ld", language: language), section, repetition, repetitionCount) : section
    }
    /// The short repetition mark of the slide's part, such as "2/3", or nil when it is not repeated.
    var repetitionMark: String? { Strings.repetitionMark(repetition, of: repetitionCount) }
}
