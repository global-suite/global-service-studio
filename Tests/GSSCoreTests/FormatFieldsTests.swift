import Foundation
import XCTest

@testable import GSSCore

final class FormatFieldsTests: XCTestCase {
    func testReaderTakesKnownKeysAndKeepsTheRest() throws {
        var reader = try JSONObjectReader(.object(["a": .integer(1), "n": .null, "x": .bool(true)]), at: "")
        XCTAssertEqual(try reader.required("a") as Int, 1)
        XCTAssertNil(try reader.optional("n") as String?)
        XCTAssertEqual(reader.unknown, ["n": .null, "x": .bool(true)])
        XCTAssertThrowsError(try reader.required("b") as Int) { XCTAssertEqual($0 as? FormatError, .missingField("b")) }
    }

    func testMistypedFieldReportsKeyPath() throws {
        var reader = try JSONObjectReader(.object(["list": .array([.integer(1), .string("2")])]), at: "root")
        XCTAssertThrowsError(try reader.required("list") as [Int]) {
            XCTAssertEqual($0 as? FormatError, .invalidField("root.list[1]"))
        }
    }

    func testKnownKeyWinsOverUnknownField() {
        let value = JSONValue.object(["a": .integer(1), "b": nil], unknown: ["a": .integer(2), "c": .null])
        XCTAssertEqual(value, .object(["a": .integer(1), "c": .null]))
    }

    func testEnvelopeChecksFormatAndVersionAndWritesLowercaseId() throws {
        let id = UUID()
        let data = try JSONValue.object(Envelope.fields(format: "gss.test", version: 1, id: id), unknown: ["x": .null])
            .canonicalData()
        let (readId, reader) = try Envelope.open(data, format: "gss.test", supportedVersion: 1)
        XCTAssertEqual(readId, id)
        XCTAssertEqual(reader.unknown, ["x": .null])
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(id.uuidString.lowercased()))
        XCTAssertThrowsError(try Envelope.open(data, format: "gss.other", supportedVersion: 1)) {
            XCTAssertEqual($0 as? FormatError, .wrongFormat(expected: "gss.other", found: "gss.test"))
        }
        XCTAssertThrowsError(try Envelope.open(data, format: "gss.test", supportedVersion: 0)) {
            XCTAssertEqual($0 as? FormatError, .unsupportedVersion(found: 1, supported: 0))
        }
    }
}
