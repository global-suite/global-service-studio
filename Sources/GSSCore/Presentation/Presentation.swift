import Foundation

/// A presentation file (`gss.presentation`): free-form slides designed one by one.
public struct Presentation: Equatable, Sendable {
    public static let format = "gss.presentation"
    public static let supportedVersion = 1

    public var id: UUID
    public var title: String
    public var theme: UUID?
    public var slides: [PresentationSlide]
    public var externalIds: [String: JSONValue]?
    public var extensions: [String: JSONValue]?
    public var unknown: [String: JSONValue] = [:]
    public init(id: UUID = UUID(), title: String, theme: UUID? = nil, slides: [PresentationSlide]) {
        (self.id, self.title, self.theme, self.slides) = (id, title, theme, slides)
    }

    /// Reads and validates a presentation file.
    public static func decode(from data: Data) throws -> Presentation {
        var (id, reader) = try Envelope.open(data, format: format, supportedVersion: supportedVersion)
        var presentation = try Presentation(id: id, title: reader.required("title"), theme: reader.optional("theme"),
                                            slides: reader.required("slides"))
        presentation.externalIds = try reader.optional("externalIds")
        presentation.extensions = try reader.optional("extensions")
        presentation.unknown = reader.unknown
        try presentation.validate()
        return presentation
    }

    /// The canonical bytes of the presentation file.
    public func encoded() throws -> Data {
        let fields: [String: JSONValue?] = [
            "title": title.json, "theme": theme?.json, "slides": slides.json,
            "externalIds": externalIds?.json, "extensions": extensions?.json,
        ]
        let envelope = Envelope.fields(format: Self.format, version: Self.supportedVersion, id: id)
        return try JSONValue.object(fields.merging(envelope) { $1 }, unknown: unknown).canonicalData()
    }
}
