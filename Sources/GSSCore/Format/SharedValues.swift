import Foundation

/// A string value with known constants that also keeps values it does not know.
public protocol OpenStringValue: RawRepresentable, Hashable, Sendable, JSONRepresentable where RawValue == String {
    init(rawValue: String)
}

extension OpenStringValue {
    public init(json: JSONValue, at path: String) throws { self.init(rawValue: try String(json: json, at: path)) }
    public var json: JSONValue { .string(rawValue) }
}

/// A media file referenced by library-relative path and content hash.
public struct MediaReference: Equatable, Sendable, JSONRepresentable {
    public var path, sha256: String
    public var unknown: [String: JSONValue] = [:]
    public init(path: String, sha256: String) { (self.path, self.sha256) = (path, sha256) }
    public init(json: JSONValue, at path: String) throws {
        var reader = try JSONObjectReader(json, at: path)
        try self.init(path: reader.required("path"), sha256: reader.required("sha256"))
        unknown = reader.unknown
    }
    public var json: JSONValue { .object(["path": path.json, "sha256": sha256.json], unknown: unknown) }

    /// Whether the path stays inside the library: not empty, not absolute and with no `..` component.
    public var hasLibraryRelativePath: Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix("~") && !parts.contains("..")
    }
}
