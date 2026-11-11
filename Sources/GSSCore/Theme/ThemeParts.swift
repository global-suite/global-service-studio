import Foundation

/// The size of the design canvas; frames and font sizes are fractions of it.
public struct ThemeCanvas: Equatable, Sendable, JSONRepresentable {
    public var width, height: Double
    public var unknown: [String: JSONValue] = [:]
    public init(width: Double, height: Double) { (self.width, self.height) = (width, height) }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(width: reader.required("width"), height: reader.required("height"))
        unknown = reader.unknown
    }
    public var json: JSONValue { .object(["width": width.json, "height": height.json], unknown: unknown) }
}

/// What is drawn behind the slots: a color, or an image or video file.
public struct ThemeBackground: Equatable, Sendable, JSONRepresentable {
    public var kind: ThemeBackgroundKind
    public var color: String?
    public var media: ThemeMediaReference?
    public var unknown: [String: JSONValue] = [:]
    public init(kind: ThemeBackgroundKind, color: String? = nil, media: ThemeMediaReference? = nil) {
        (self.kind, self.color, self.media) = (kind, color, media)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(kind: reader.required("kind"), color: reader.optional("color"), media: reader.optional("media"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["kind": kind.json, "color": color?.json, "media": media?.json], unknown: unknown)
    }
}

/// A media file by library-relative path and SHA-256 content hash.
public struct ThemeMediaReference: Equatable, Sendable, JSONRepresentable {
    public var path, sha256: String
    public var unknown: [String: JSONValue] = [:]
    public init(path: String, sha256: String) { (self.path, self.sha256) = (path, sha256) }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(path: reader.required("path"), sha256: reader.required("sha256"))
        unknown = reader.unknown
    }
    public var json: JSONValue { .object(["path": path.json, "sha256": sha256.json], unknown: unknown) }
}

/// A named text area of the theme, such as `lyrics` or `footer`.
public struct ThemeSlot: Equatable, Sendable, JSONRepresentable {
    public var frame: ThemeFrame
    public var font: ThemeFont
    public var color: String
    public var align: ThemeAlignment
    public var maxLines: Int?
    public var wrap: ThemeWrap?
    public var unknown: [String: JSONValue] = [:]
    public init(frame: ThemeFrame, font: ThemeFont, color: String, align: ThemeAlignment,
                maxLines: Int? = nil, wrap: ThemeWrap? = nil) {
        (self.frame, self.font, self.color, self.align) = (frame, font, color, align)
        (self.maxLines, self.wrap) = (maxLines, wrap)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(frame: reader.required("frame"), font: reader.required("font"), color: reader.required("color"),
                      align: reader.required("align"), maxLines: reader.optional("maxLines"),
                      wrap: reader.optional("wrap"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["frame": frame.json, "font": font.json, "color": color.json, "align": align.json,
                 "maxLines": maxLines?.json, "wrap": wrap?.json], unknown: unknown)
    }
}

/// A rectangle in fractions of the canvas, from its top-left corner.
public struct ThemeFrame: Equatable, Sendable, JSONRepresentable {
    public var x, y, width, height: Double
    public var unknown: [String: JSONValue] = [:]
    public init(x: Double, y: Double, width: Double, height: Double) {
        (self.x, self.y, self.width, self.height) = (x, y, width, height)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(x: reader.required("x"), y: reader.required("y"), width: reader.required("width"),
                      height: reader.required("height"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["x": x.json, "y": y.json, "width": width.json, "height": height.json], unknown: unknown)
    }
}

/// A font; `size` is a fraction of the canvas height.
public struct ThemeFont: Equatable, Sendable, JSONRepresentable {
    public var family: String
    public var weight: ThemeFontWeight
    public var size: Double
    public var unknown: [String: JSONValue] = [:]
    public init(family: String, weight: ThemeFontWeight, size: Double) {
        (self.family, self.weight, self.size) = (family, weight, size)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(family: reader.required("family"), weight: reader.required("weight"),
                      size: reader.required("size"))
        unknown = reader.unknown
    }
    public var json: JSONValue {
        .object(["family": family.json, "weight": weight.json, "size": size.json], unknown: unknown)
    }
}

/// How a second language is shown.
public struct ThemeLanguages: Equatable, Sendable, JSONRepresentable {
    public var layout: ThemeLanguageLayout
    public var unknown: [String: JSONValue] = [:]
    public init(layout: ThemeLanguageLayout) { self.layout = layout }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(layout: reader.required("layout"))
        unknown = reader.unknown
    }
    public var json: JSONValue { .object(["layout": layout.json], unknown: unknown) }
}

/// The kind of a theme background; unknown kinds are kept as written.
public struct ThemeBackgroundKind: RawRepresentable, Hashable, Sendable, JSONRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(json: JSONValue, at path: String) throws { rawValue = try String(json: json, at: path) }
    public var json: JSONValue { .string(rawValue) }
    public static let color = Self(rawValue: "color"), image = Self(rawValue: "image"), video = Self(rawValue: "video")
}

/// The horizontal alignment of a slot's text; unknown values are kept as written.
public struct ThemeAlignment: RawRepresentable, Hashable, Sendable, JSONRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(json: JSONValue, at path: String) throws { rawValue = try String(json: json, at: path) }
    public var json: JSONValue { .string(rawValue) }
    public static let leading = Self(rawValue: "leading"), center = Self(rawValue: "center"),
                      trailing = Self(rawValue: "trailing")
}

/// How lines are split to fit a slot; unknown modes are kept as written.
public struct ThemeWrap: RawRepresentable, Hashable, Sendable, JSONRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(json: JSONValue, at path: String) throws { rawValue = try String(json: json, at: path) }
    public var json: JSONValue { .string(rawValue) }
    public static let balanced = Self(rawValue: "balanced"), natural = Self(rawValue: "natural")
}

/// How a second language appears; unknown layouts are kept as written.
public struct ThemeLanguageLayout: RawRepresentable, Hashable, Sendable, JSONRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(json: JSONValue, at path: String) throws { rawValue = try String(json: json, at: path) }
    public var json: JSONValue { .string(rawValue) }
    public static let primaryOnly = Self(rawValue: "primaryOnly"), stacked = Self(rawValue: "stacked"),
                      alternating = Self(rawValue: "alternating")
}

/// The weight of a font; unknown weights are kept as written.
public struct ThemeFontWeight: RawRepresentable, Hashable, Sendable, JSONRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(json: JSONValue, at path: String) throws { rawValue = try String(json: json, at: path) }
    public var json: JSONValue { .string(rawValue) }
    public static let regular = Self(rawValue: "regular"), medium = Self(rawValue: "medium"),
                      semibold = Self(rawValue: "semibold"), bold = Self(rawValue: "bold")
}
