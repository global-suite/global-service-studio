import Foundation

extension JSONValue {
    /// Canonical bytes: UTF-8, keys sorted by code point, two-space indentation, one final newline.
    public func canonicalData() throws -> Data {
        Data((try text(indent: "") + "\n").utf8)
    }

    private func text(indent: String) throws -> String {
        let inner = indent + "  "
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .double(let value):
            guard value.isFinite else { throw FormatError.invalidJSON }
            return "\(value)"
        case .string(let value): return Self.quoted(value)
        case .array(let elements):
            return Self.block("[", "]", try elements.map { try $0.text(indent: inner) }, indent: indent)
        case .object(let fields):
            let keys = fields.keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
            let items = try keys.map { Self.quoted($0) + ": " + (try fields[$0]!.text(indent: inner)) }
            return Self.block("{", "}", items, indent: indent)
        }
    }

    private static func block(_ open: String, _ close: String, _ items: [String], indent: String) -> String {
        guard !items.isEmpty else { return open + close }
        let inner = indent + "  "
        return open + "\n" + inner + items.joined(separator: ",\n" + inner) + "\n" + indent + close
    }

    private static func quoted(_ string: String) -> String {
        var output = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"", "\\": output += "\\" + String(scalar)
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case _ where scalar.value < 0x20: output += String(format: "\\u%04x", scalar.value)
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
