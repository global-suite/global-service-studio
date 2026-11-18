import Foundation

/// One designed slide of a presentation.
public struct PresentationSlide: Equatable, Sendable, JSONRepresentable {
    public var id: String
    public var label: String?
    public var elements: [PresentationElement]
    public var notes: String?
    /// The layout the editor built the slide from; absent for imported slides (ADR 0011).
    public var layout: PresentationSlideLayout?
    /// Whether the slide is left out of the program; written only when `true` (ADR 0011).
    public var hidden: Bool
    public var unknown: [String: JSONValue] = [:]
    public init(id: String, label: String? = nil, elements: [PresentationElement], notes: String? = nil,
                layout: PresentationSlideLayout? = nil, hidden: Bool = false) {
        (self.id, self.label, self.elements, self.notes) = (id, label, elements, notes)
        (self.layout, self.hidden) = (layout, hidden)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        var hidden = false
        if let value: JSONValue = try reader.optional("hidden") {
            guard case .bool(let flag) = value else { throw FormatError.invalidField(path + ".hidden") }
            hidden = flag
        }
        try self.init(id: reader.required("id"), label: reader.optional("label"),
                      elements: reader.required("elements"), notes: reader.optional("notes"),
                      layout: reader.optional("layout"), hidden: hidden)
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["id": id.json, "label": label?.json, "elements": elements.json, "notes": notes?.json,
                 "layout": layout?.json, "hidden": hidden ? .bool(true) : nil],
                unknown: unknown)
    }
}

/// The file an imported deck came from (ADR 0011).
public struct PresentationSource: Equatable, Sendable, JSONRepresentable {
    public var kind: PresentationSourceKind
    /// The last known absolute path of the file.
    public var path: String
    /// Security-scoped bookmark data in Base64; only the app resolves it.
    public var bookmark: String?
    /// The time of the last import, in UTC, in RFC 3339 form.
    public var importedAt: String
    public var unknown: [String: JSONValue] = [:]
    public init(kind: PresentationSourceKind, path: String, bookmark: String? = nil, importedAt: String) {
        (self.kind, self.path, self.bookmark, self.importedAt) = (kind, path, bookmark, importedAt)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(kind: reader.required("kind"), path: reader.required("path"),
                      bookmark: reader.optional("bookmark"), importedAt: reader.required("importedAt"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["kind": kind.json, "path": path.json, "bookmark": bookmark?.json, "importedAt": importedAt.json],
                unknown: unknown)
    }
}

/// The application an imported deck came from; unknown kinds are kept as written.
public struct PresentationSourceKind: OpenStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let keynote = Self(rawValue: "keynote"), powerPoint = Self(rawValue: "powerPoint"),
                      pdf = Self(rawValue: "pdf")
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
    /// How an image fills its frame; absent means `fit` (ADR 0010).
    public var scaling: PresentationImageScaling?
    public var unknown: [String: JSONValue] = [:]
    public init(id: String, kind: PresentationElementKind, slot: String? = nil, frame: ThemeFrame? = nil,
                text: [String: String]? = nil, font: ThemeFont? = nil, color: String? = nil,
                align: ThemeAlignment? = nil, media: MediaReference? = nil, scaling: PresentationImageScaling? = nil) {
        (self.id, self.kind, self.slot, self.frame, self.text) = (id, kind, slot, frame, text)
        (self.font, self.color, self.align, self.media, self.scaling) = (font, color, align, media, scaling)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(id: reader.required("id"), kind: reader.required("kind"), slot: reader.optional("slot"),
                      frame: reader.optional("frame"), text: reader.optional("text"), font: reader.optional("font"),
                      color: reader.optional("color"), align: reader.optional("align"),
                      media: reader.optional("media"), scaling: reader.optional("scaling"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["id": id.json, "kind": kind.json, "slot": slot?.json, "frame": frame?.json, "text": text?.json,
                 "font": font?.json, "color": color?.json, "align": align?.json, "media": media?.json,
                 "scaling": scaling?.json],
                unknown: unknown)
    }
}

/// The kind of a slide element; unknown kinds are kept as written.
public struct PresentationElementKind: OpenStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let text = Self(rawValue: "text"), image = Self(rawValue: "image"), video = Self(rawValue: "video")
}

/// How an image fills its frame when their proportions differ; unknown values are kept as written.
public struct PresentationImageScaling: OpenStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// The whole image shows; the leftover bands are transparent.
    public static let fit = Self(rawValue: "fit")
    /// The image covers the frame and the overflow is cropped.
    public static let fill = Self(rawValue: "fill")
    /// The image covers the frame and is distorted to match it.
    public static let stretch = Self(rawValue: "stretch")
}

extension PresentationElement {
    /// The scaling to display: `scaling` when it is a known value, else `fit`.
    public var effectiveScaling: PresentationImageScaling {
        guard let scaling, [.fit, .fill, .stretch].contains(scaling) else { return .fit }
        return scaling
    }
}
