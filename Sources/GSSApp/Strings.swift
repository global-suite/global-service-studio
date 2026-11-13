import Foundation
import GSSCore

/// Looks up user-facing strings in this module's `Localizable.strings`, in the system language.
enum Strings {
    static let bundle = Bundle.module
    /// Chosen explicitly: without an app bundle, Foundation follows the executable, which has no localizations.
    static let language = language(for: Locale.preferredLanguages)
    static func language(for preferences: [String]) -> String { Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: preferences).first ?? "en" }

    static func text(_ key: String, language: String = language) -> String {
        let localized = bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
        return localized.localizedString(forKey: key, value: nil, table: nil)
    }

    static var appName: String { text("Global Service Studio") }
    /// A slide count such as "1 slide" or "2 slides", with the plural rules of the language (Localizable.stringsdict).
    static func slideCount(_ count: Int, language: String = language) -> String {
        String(format: text("%ld slides", language: language), locale: Locale(identifier: language), count)
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

extension AppMode {
    /// The localized name of the mode.
    public var title: String { Strings.text(self == .prepare ? "Prepare" : "Live") }
}

extension LiveSlide {
    /// The section and the slide's place in it, such as "Chorus · 1 of 2".
    public var position: String { String(format: Strings.text("%1$@ · %2$ld of %3$ld"), section, part, partCount) }
}
