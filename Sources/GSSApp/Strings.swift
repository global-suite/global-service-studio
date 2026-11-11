import Foundation

/// Looks up user-facing strings in this module's `Localizable.strings`, in the system language.
enum Strings {
    static let bundle = Bundle.module

    static func text(_ key: String) -> String { bundle.localizedString(forKey: key, value: nil, table: nil) }

    static var appName: String { text("Global Service Studio") }
}

extension AppMode {
    /// The localized name of the mode.
    public var title: String { Strings.text(self == .prepare ? "Prepare" : "Live") }

    var explanation: String {
        Strings.text(self == .prepare
            ? "Build the service: songs, words, slides and themes."
            : "Run the service: what is live, what comes next and the outputs.")
    }
}
