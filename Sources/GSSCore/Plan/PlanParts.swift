import Foundation

/// A named start time of the service, such as a morning meeting at `10:00`.
public struct PlanTime: Equatable, Sendable, JSONRepresentable {
    public var name: String
    /// The start as 24-hour `HH:MM`.
    public var start: String
    public var unknown: [String: JSONValue] = [:]
    public init(name: String, start: String) { (self.name, self.start) = (name, start) }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(name: reader.required("name"), start: reader.required("start"))
        unknown = reader.unknown
    }
    public var json: JSONValue { .object(["name": name.json, "start": start.json], unknown: unknown) }
}

/// One entry of the order of service. Which fields apply depends on `kind`.
public struct PlanItem: Equatable, Sendable, JSONRepresentable {
    public var id: String
    public var kind: PlanItemKind
    public var title: String?
    public var song: UUID?
    public var arrangement: String?
    /// Section ids for this service only; the song itself is not changed.
    public var sequence: [String]?
    public var key: String?
    public var presentation: UUID?
    public var media: MediaReference?
    /// The length in seconds.
    public var length: Double?
    public var position: PlanItemPosition?
    public var notes: [PlanNote]?
    public var externalIds: [String: JSONValue]?
    public var extensions: [String: JSONValue]?
    public var unknown: [String: JSONValue] = [:]
    public init(id: String, kind: PlanItemKind, title: String? = nil, song: UUID? = nil, presentation: UUID? = nil,
                media: MediaReference? = nil, length: Double? = nil, position: PlanItemPosition? = nil) {
        (self.id, self.kind, self.title, self.song, self.presentation) = (id, kind, title, song, presentation)
        (self.media, self.length, self.position) = (media, length, position)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(id: reader.required("id"), kind: reader.required("kind"), title: reader.optional("title"),
                      song: reader.optional("song"), presentation: reader.optional("presentation"),
                      media: reader.optional("media"), length: reader.optional("length"),
                      position: reader.optional("position"))
        (arrangement, sequence, key) = try (reader.optional("arrangement"), reader.optional("sequence"),
                                            reader.optional("key"))
        (notes, externalIds, extensions) = try (reader.optional("notes"), reader.optional("externalIds"),
                                                reader.optional("extensions"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["id": id.json, "kind": kind.json, "title": title?.json, "song": song?.json,
                 "arrangement": arrangement?.json, "sequence": sequence?.json, "key": key?.json,
                 "presentation": presentation?.json, "media": media?.json, "length": length?.json,
                 "position": position?.json, "notes": notes?.json, "externalIds": externalIds?.json,
                 "extensions": extensions?.json], unknown: unknown)
    }
}

/// A note on a plan item for one team, such as vocals or lighting.
public struct PlanNote: Equatable, Sendable, JSONRepresentable {
    public var category: String
    public var text: String
    public var unknown: [String: JSONValue] = [:]
    public init(category: String, text: String) { (self.category, self.text) = (category, text) }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(category: reader.required("category"), text: reader.required("text"))
        unknown = reader.unknown
    }
    public var json: JSONValue { .object(["category": category.json, "text": text.json], unknown: unknown) }
}

/// The kind of a plan item; unknown kinds are kept as written.
public struct PlanItemKind: OpenStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let header = Self(rawValue: "header"), song = Self(rawValue: "song")
    public static let presentation = Self(rawValue: "presentation"), media = Self(rawValue: "media")
    public static let item = Self(rawValue: "item")
}

/// When an item happens relative to the service; unknown values are kept as written.
public struct PlanItemPosition: OpenStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let pre = Self(rawValue: "pre"), during = Self(rawValue: "during"), post = Self(rawValue: "post")
}
