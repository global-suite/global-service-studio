import Foundation

/// Backgrounds a song cues on the media layer: one for the whole song and one per section id.
/// Each value has the shape of a theme background; section keys that name no section are kept.
public struct SongBackgrounds: Equatable, Sendable, JSONRepresentable {
    /// Written as `default`.
    public var defaultBackground: ThemeBackground?
    public var sections: [String: ThemeBackground]?
    public var unknown: [String: JSONValue] = [:]
    public init(defaultBackground: ThemeBackground? = nil, sections: [String: ThemeBackground]? = nil) {
        (self.defaultBackground, self.sections) = (defaultBackground, sections)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(defaultBackground: reader.optional("default"), sections: reader.optional("sections"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["default": defaultBackground?.json, "sections": sections?.json], unknown: unknown)
    }
}
