import Foundation
import XCTest

@testable import GSSCore

final class FormatCanonicalJSONTests: XCTestCase {
    private func text(_ value: JSONValue) throws -> String {
        String(decoding: try value.canonicalData(), as: UTF8.self)
    }

    private func parse(_ json: String) throws -> JSONValue {
        try JSONValue(parsing: Data(json.utf8))
    }

    func testNestedValueHasExactCanonicalText() throws {
        let value: JSONValue = .object([
            "s": .string("x"),
            "b": .array([.integer(1), .double(2.5), .null]),
            "a": .object(["e": .object([:]), "d": .array([]), "c": .bool(true)]),
        ])
        XCTAssertEqual(try text(value), """
        {
          "a": {
            "c": true,
            "d": [],
            "e": {}
          },
          "b": [
            1,
            2.5,
            null
          ],
          "s": "x"
        }

        """)
    }

    func testKeysAreSortedByUnicodeCodePoint() throws {
        // "e\u{0302}" sorts before "\u{00E9}" by code point, but after it in normalized order.
        let value: JSONValue = .object([
            "\u{00E9}": .integer(4), "e\u{0302}": .integer(3), "a": .integer(2), "Z": .integer(1),
        ])
        XCTAssertEqual(try text(value), "{\n  \"Z\": 1,\n  \"a\": 2,\n  \"e\u{0302}\": 3,\n  \"\u{00E9}\": 4\n}\n")
    }

    func testIntegersAndDecimalsKeepTheirKind() throws {
        let value = try parse(#"{"a": 1, "b": 1.0, "c": 2.50, "d": -3}"#)
        XCTAssertEqual(value, .object(["a": .integer(1), "b": .double(1), "c": .double(2.5), "d": .integer(-3)]))
        XCTAssertEqual(try text(value), "{\n  \"a\": 1,\n  \"b\": 1.0,\n  \"c\": 2.5,\n  \"d\": -3\n}\n")
    }

    func testStringsUseMinimalEscaping() throws {
        let value = JSONValue.string("q\"b\\s/c\u{1}\n\t é ñ 😀")
        XCTAssertEqual(try text(value), #""q\"b\\s/c\u0001\n\t é ñ 😀""# + "\n")
        XCTAssertEqual(try JSONValue(parsing: try value.canonicalData()), value)
    }

    func testParseSerializeParseIsIdentity() throws {
        let original = try parse(#"{"z": [true, false, null, {"k": "v"}], "n": -0.25, "i": 42, "s": "día"}"#)
        XCTAssertEqual(try JSONValue(parsing: try original.canonicalData()), original)
    }

    func testSerializingIsByteStable() throws {
        var first: [String: JSONValue] = [:]
        var second: [String: JSONValue] = [:]
        let keys = (0..<50).map { "key\($0)" }
        for key in keys { first[key] = .string(key) }
        for key in keys.reversed() { second[key] = .string(key) }
        let bytes = try JSONValue.object(first).canonicalData()
        XCTAssertEqual(bytes, try JSONValue.object(second).canonicalData())
        XCTAssertEqual(bytes, try JSONValue.object(first).canonicalData())
    }

    func testInvalidJSONThrowsTypedError() {
        XCTAssertThrowsError(try parse(#"{"a": "#)) { XCTAssertEqual($0 as? FormatError, .invalidJSON) }
    }
}
