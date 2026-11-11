import Foundation

/// A theme file (`gss.theme`): how content looks, with no content in it.
public struct Theme: Equatable, Sendable {
    public static let format = "gss.theme"
    public static let supportedVersion = 1
    public static let lyricsSlot = "lyrics", translationSlot = "translation", footerSlot = "footer"

    public var id: UUID
    public var name: String
    public var canvas: ThemeCanvas
    public var background: ThemeBackground
    public var slots: [String: ThemeSlot]
    public var languages: ThemeLanguages
    public var externalIds: [String: JSONValue]?
    public var extensions: [String: JSONValue]?
    public var unknown: [String: JSONValue] = [:]
    public init(id: UUID = UUID(), name: String, canvas: ThemeCanvas, background: ThemeBackground,
                slots: [String: ThemeSlot], languages: ThemeLanguages) {
        (self.id, self.name, self.canvas, self.background) = (id, name, canvas, background)
        (self.slots, self.languages) = (slots, languages)
    }

    /// Reads a theme file.
    public static func decode(from data: Data) throws -> Theme {
        var (id, reader) = try Envelope.open(data, format: format, supportedVersion: supportedVersion)
        var theme = try Theme(id: id, name: reader.required("name"), canvas: reader.required("canvas"),
                              background: reader.required("background"), slots: reader.required("slots"),
                              languages: reader.required("languages"))
        theme.externalIds = try reader.optional("externalIds")
        theme.extensions = try reader.optional("extensions")
        theme.unknown = reader.unknown
        return theme
    }

    /// The canonical bytes of the theme file.
    public func encoded() throws -> Data {
        let fields: [String: JSONValue?] = [
            "name": name.json, "canvas": canvas.json, "background": background.json, "slots": slots.json,
            "languages": languages.json, "externalIds": externalIds?.json, "extensions": extensions?.json,
        ]
        let envelope = Envelope.fields(format: Self.format, version: Self.supportedVersion, id: id)
        return try JSONValue.object(fields.merging(envelope) { $1 }, unknown: unknown).canonicalData()
    }
}
