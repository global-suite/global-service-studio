import Foundation

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
}

extension AppMode {
    /// The localized name of the mode.
    public var title: String { Strings.text(self == .prepare ? "Prepare" : "Live") }
}

extension LiveSlide {
    /// The section and the slide's place in it, such as "Chorus · 1 of 2".
    public var position: String { String(format: Strings.text("%1$@ · %2$ld of %3$ld"), section, part, partCount) }
}
