import Foundation

/// One designed slide of a presentation.
public struct PresentationSlide: Equatable, Sendable, JSONRepresentable {
    public var id: String
    public var label: String?
    public var elements: [PresentationElement]
    public var notes: String?
    public var unknown: [String: JSONValue] = [:]
    public init(id: String, label: String? = nil, elements: [PresentationElement], notes: String? = nil) {
        (self.id, self.label, self.elements, self.notes) = (id, label, elements, notes)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(id: reader.required("id"), label: reader.optional("label"),
                      elements: reader.required("elements"), notes: reader.optional("notes"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["id": id.json, "label": label?.json, "elements": elements.json, "notes": notes?.json],
                unknown: unknown)
    }
}

/// Something placed on a slide: text in a theme slot or its own frame, an image or a video.
public struct PresentationElement: Equatable, Sendable, JSONRepresentable {
    public var id: String
    public var kind: PresentationElementKind
    public var slot: String?
    public var frame: ThemeFrame?
    public var text: [String: String]?
    public var font: ThemeFont?
    public var color: String?
    public var align: ThemeAlignment?
    public var media: MediaReference?
    public var unknown: [String: JSONValue] = [:]
    public init(id: String, kind: PresentationElementKind, slot: String? = nil, frame: ThemeFrame? = nil,
                text: [String: String]? = nil, font: ThemeFont? = nil, color: String? = nil,
                align: ThemeAlignment? = nil, media: MediaReference? = nil) {
        (self.id, self.kind, self.slot, self.frame, self.text) = (id, kind, slot, frame, text)
        (self.font, self.color, self.align, self.media) = (font, color, align, media)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(id: reader.required("id"), kind: reader.required("kind"), slot: reader.optional("slot"),
                      frame: reader.optional("frame"), text: reader.optional("text"), font: reader.optional("font"),
                      color: reader.optional("color"), align: reader.optional("align"),
                      media: reader.optional("media"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["id": id.json, "kind": kind.json, "slot": slot?.json, "frame": frame?.json, "text": text?.json,
                 "font": font?.json, "color": color?.json, "align": align?.json, "media": media?.json],
                unknown: unknown)
    }
}

/// The kind of a slide element; unknown kinds are kept as written.
public struct PresentationElementKind: OpenStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let text = Self(rawValue: "text"), image = Self(rawValue: "image"), video = Self(rawValue: "video")
}
