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
    /// The name of a section: its label as written, or its kind and number in the interface language, such as "Verse 2".
    static func sectionName(_ section: SongSection, language: String = language) -> String {
        let kinds = ["verse": "Verse", "chorus": "Chorus", "prechorus": "Pre-Chorus", "bridge": "Bridge", "intro": "Intro",
                     "outro": "Outro", "tag": "Tag", "interlude": "Interlude", "ending": "Ending"]
        if let label = section.label { return label }
        let kind = kinds[section.kind.rawValue].map { text($0, language: language) } ?? section.kind.rawValue
        return section.number.map { String(format: text("%1$@ %2$ld", language: language), kind, $0) } ?? kind
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
