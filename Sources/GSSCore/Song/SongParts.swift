import Foundation

/// The kind of a song section; unknown kinds are kept as written.
public struct SongSectionKind: OpenStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let verse = Self(rawValue: "verse")
    public static let chorus = Self(rawValue: "chorus")
    public static let prechorus = Self(rawValue: "prechorus")
    public static let bridge = Self(rawValue: "bridge")
    public static let intro = Self(rawValue: "intro")
    public static let outro = Self(rawValue: "outro")
    public static let tag = Self(rawValue: "tag")
    public static let interlude = Self(rawValue: "interlude")
    public static let ending = Self(rawValue: "ending")
    public static let other = Self(rawValue: "other")
}

/// A part of a song, such as a verse or a chorus.
public struct SongSection: Equatable, Sendable, JSONRepresentable {
    public var id: String
    public var kind: SongSectionKind
    public var number: Int?
    public var label: String?
    public var lines: [SongLine]
    public var unknown: [String: JSONValue] = [:]

    public init(id: String, kind: SongSectionKind, number: Int? = nil, label: String? = nil, lines: [SongLine]) {
        (self.id, self.kind, self.number, self.label, self.lines) = (id, kind, number, label, lines)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(id: reader.required("id"), kind: reader.required("kind"), number: reader.optional("number"),
                      label: reader.optional("label"), lines: reader.required("lines"))
        unknown = reader.unknown
    }

    public var json: JSONValue {
        .object(["id": id.json, "kind": kind.json, "number": number?.json, "label": label?.json, "lines": lines.json],
                unknown: unknown)
    }
}

/// One sung line, with its text per language tag.
public struct SongLine: Equatable, Sendable, JSONRepresentable {
    public var text: [String: String]
    public var chords: [SongChord]?
    public var breakAfter: String?
    public var unknown: [String: JSONValue] = [:]

    public init(text: [String: String], chords: [SongChord]? = nil, breakAfter: String? = nil) {
        (self.text, self.chords, self.breakAfter) = (text, chords, breakAfter)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(text: reader.required("text"), chords: reader.optional("chords"),
                      breakAfter: reader.optional("breakAfter"))
        unknown = reader.unknown
    }

    public var json: JSONValue {
        .object(["text": text.json, "chords": chords?.json, "breakAfter": breakAfter?.json], unknown: unknown)
    }
}

/// A chord placed at a Unicode code point offset in the primary-language text.
public struct SongChord: Equatable, Sendable, JSONRepresentable {
    public var at: Int
    public var chord: String
    public var unknown: [String: JSONValue] = [:]

    public init(at: Int, chord: String) { (self.at, self.chord) = (at, chord) }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(at: reader.required("at"), chord: reader.required("chord"))
        unknown = reader.unknown
    }

    public var json: JSONValue { .object(["at": at.json, "chord": chord.json], unknown: unknown) }
}

/// A named order of sections, by section id.
public struct SongArrangement: Equatable, Sendable, JSONRepresentable {
    public var id: String
    public var name: String
    public var sequence: [String]
    public var unknown: [String: JSONValue] = [:]

    public init(id: String, name: String, sequence: [String]) {
        (self.id, self.name, self.sequence) = (id, name, sequence)
    }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(id: reader.required("id"), name: reader.required("name"), sequence: reader.required("sequence"))
        unknown = reader.unknown
    }

    public var json: JSONValue {
        .object(["id": id.json, "name": name.json, "sequence": sequence.json], unknown: unknown)
    }
}

/// A writer, composer or translator of a song.
public struct SongAuthor: Equatable, Sendable, JSONRepresentable {
    public var name: String
    public var role: String?
    public var unknown: [String: JSONValue] = [:]

    public init(name: String, role: String? = nil) { (self.name, self.role) = (name, role) }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(name: reader.required("name"), role: reader.optional("role"))
        unknown = reader.unknown
    }

    public var json: JSONValue { .object(["name": name.json, "role": role?.json], unknown: unknown) }
}
