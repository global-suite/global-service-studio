import Foundation

/// An error reading or validating a Global Service Studio file.
public enum FormatError: Error, Equatable, Sendable {
    case invalidJSON
    case wrongFormat(expected: String, found: String)
    case missingField(String)
    case invalidField(String)
    case unsupportedVersion(found: Int, supported: Int)
    case validation(reason: String, at: String)
}

/// A type read from and written to a `JSONValue`; `path` locates it for error messages.
public protocol JSONRepresentable {
    init(json: JSONValue, at path: String) throws
    var json: JSONValue { get }
}

/// Takes known keys out of a JSON object; whatever is left is `unknown`.
public struct JSONObjectReader: Equatable, Sendable {
    public let path: String
    public private(set) var unknown: [String: JSONValue]

    public init(_ json: JSONValue, at path: String) throws {
        guard case .object(let fields) = json else { throw FormatError.invalidField(path) }
        self.path = path
        unknown = fields
    }

    /// Reads a key that must be present and not null.
    public mutating func required<T: JSONRepresentable>(_ key: String) throws -> T {
        guard let value: T = try optional(key) else { throw FormatError.missingField(keyPath(key)) }
        return value
    }

    /// Reads a key that may be absent; a null is left in `unknown` so it is written back.
    public mutating func optional<T: JSONRepresentable>(_ key: String) throws -> T? {
        guard let value = unknown[key], value != .null else { return nil }
        unknown[key] = nil
        return try T(json: value, at: keyPath(key))
    }

    private func keyPath(_ key: String) -> String {
        path.isEmpty ? key : path + "." + key
    }
}

extension JSONValue {
    /// An object of the present `known` fields over the `unknown` ones; a known key wins.
    public static func object(_ known: [String: JSONValue?], unknown: [String: JSONValue]) -> JSONValue {
        var fields = unknown
        for case let (key, value?) in known { fields[key] = value }
        return .object(fields)
    }
}

/// The `format`, `version` and `id` fields every file starts with.
public enum Envelope: Sendable {
    /// Parses `data`, checks the envelope and returns the id and a reader over the other fields.
    public static func open(_ data: Data, format: String, supportedVersion: Int) throws -> (UUID, JSONObjectReader) {
        var reader = try JSONObjectReader(JSONValue(parsing: data), at: "")
        let found: String = try reader.required("format")
        guard found == format else { throw FormatError.wrongFormat(expected: format, found: found) }
        let version: Int = try reader.required("version")
        guard version <= supportedVersion else {
            throw FormatError.unsupportedVersion(found: version, supported: supportedVersion)
        }
        guard version >= 1 else { throw FormatError.invalidField("version") }
        return (try reader.required("id"), reader)
    }

    /// The envelope fields to write, with the id in lowercase.
    public static func fields(format: String, version: Int, id: UUID) -> [String: JSONValue?] {
        ["format": .string(format), "version": .integer(version), "id": id.json]
    }
}

extension JSONValue: JSONRepresentable {
    public init(json: JSONValue, at path: String) { self = json }
    public var json: JSONValue { self }
}

extension String: JSONRepresentable {
    public init(json: JSONValue, at path: String) throws {
        guard case .string(let value) = json else { throw FormatError.invalidField(path) }
        self = value
    }
    public var json: JSONValue { .string(self) }
}

extension Int: JSONRepresentable {
    public init(json: JSONValue, at path: String) throws {
        guard case .integer(let value) = json else { throw FormatError.invalidField(path) }
        self = value
    }
    public var json: JSONValue { .integer(self) }
}

extension Double: JSONRepresentable {
    public init(json: JSONValue, at path: String) throws {
        switch json {
        case .integer(let value): self = Double(value)
        case .double(let value): self = value
        default: throw FormatError.invalidField(path)
        }
    }
    /// Whole numbers are written as integers.
    public var json: JSONValue {
        if let integer = Int(exactly: self) { return .integer(integer) }
        return .double(self)
    }
}

extension UUID: JSONRepresentable {
    public init(json: JSONValue, at path: String) throws {
        guard case .string(let text) = json, let value = UUID(uuidString: text) else {
            throw FormatError.invalidField(path)
        }
        self = value
    }
    public var json: JSONValue { .string(uuidString.lowercased()) }
}

extension Array: JSONRepresentable where Element: JSONRepresentable {
    public init(json: JSONValue, at path: String) throws {
        guard case .array(let values) = json else { throw FormatError.invalidField(path) }
        self = try values.enumerated().map { try Element(json: $1, at: "\(path)[\($0)]") }
    }
    public var json: JSONValue { .array(map(\.json)) }
}

extension Dictionary: JSONRepresentable where Key == String, Value: JSONRepresentable {
    public init(json: JSONValue, at path: String) throws {
        guard case .object(let fields) = json else { throw FormatError.invalidField(path) }
        self = try fields.reduce(into: [:]) { result, field in
            result[field.key] = try Value(json: field.value, at: path.isEmpty ? field.key : path + "." + field.key)
        }
    }
    public var json: JSONValue { .object(mapValues(\.json)) }
}
