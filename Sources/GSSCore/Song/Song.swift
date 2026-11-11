import Foundation

/// A song file (`gss.song`): what is sung, without slide breaks or styling.
public struct Song: Equatable, Sendable {
    public static let format = "gss.song"
    public static let supportedVersion = 1

    public var id: UUID
    public var title: String
    public var titles: [String: String]?
    public var language: String
    public var authors: [SongAuthor]?
    public var copyright: String?
    public var ccliNumber: String?
    public var key: String?
    public var tempo: Double?
    public var timeSignature: String?
    public var tags: [String]?
    public var sections: [SongSection]
    public var arrangements: [SongArrangement]?
    public var defaultArrangement: String?
    public var externalIds: [String: JSONValue]?
    public var extensions: [String: JSONValue]?
    public var unknown: [String: JSONValue] = [:]

    public init(id: UUID = UUID(), title: String, language: String, sections: [SongSection]) {
        (self.id, self.title, self.language, self.sections) = (id, title, language, sections)
    }

    /// Reads and validates a song file.
    public static func decode(from data: Data) throws -> Song {
        var (id, reader) = try Envelope.open(data, format: format, supportedVersion: supportedVersion)
        var song = try Song(id: id, title: reader.required("title"), language: reader.required("language"),
                            sections: reader.required("sections"))
        song.titles = try reader.optional("titles")
        song.authors = try reader.optional("authors")
        song.copyright = try reader.optional("copyright")
        song.ccliNumber = try reader.optional("ccliNumber")
        song.key = try reader.optional("key")
        song.tempo = try reader.optional("tempo")
        song.timeSignature = try reader.optional("timeSignature")
        song.tags = try reader.optional("tags")
        song.arrangements = try reader.optional("arrangements")
        song.defaultArrangement = try reader.optional("defaultArrangement")
        song.externalIds = try reader.optional("externalIds")
        song.extensions = try reader.optional("extensions")
        song.unknown = reader.unknown
        try song.validate()
        return song
    }

    /// The canonical bytes of the song file.
    public func encoded() throws -> Data {
        let fields: [String: JSONValue?] = [
            "title": title.json, "titles": titles?.json, "language": language.json, "authors": authors?.json,
            "copyright": copyright?.json, "ccliNumber": ccliNumber?.json, "key": key?.json, "tempo": tempo?.json,
            "timeSignature": timeSignature?.json, "tags": tags?.json, "sections": sections.json,
            "arrangements": arrangements?.json, "defaultArrangement": defaultArrangement?.json,
            "externalIds": externalIds?.json, "extensions": extensions?.json,
        ]
        let envelope = Envelope.fields(format: Self.format, version: Self.supportedVersion, id: id)
        return try JSONValue.object(fields.merging(envelope) { $1 }, unknown: unknown).canonicalData()
    }
}
