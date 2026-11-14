import Foundation
import XCTest

@testable import GSSCore

/// The service plan example of ADR 0005, with invented text and every item kind.
let planExample = """
{
  "format": "gss.plan", "version": 1, "id": "d51b0c3e-7a42-4f0b-b6f1-18a2c9e4d702", "title": "Sunday Gathering",
  "date": "2026-11-15", "times": [{ "name": "Morning", "start": "10:00" }],
  "theme": "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421",
  "items": [
    { "id": "i1", "kind": "header", "title": "Worship" },
    { "id": "i2", "kind": "song", "song": "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10", "arrangement": "short",
      "sequence": ["v1", "c1", "c1"], "key": "A", "length": 240, "position": "during",
      "notes": [{ "category": "Vocals", "text": "Repeat the chorus softly" }],
      "externalIds": { "planningCenter": { "itemId": "901" } } },
    { "id": "i3", "kind": "presentation", "presentation": "0a9d3f77-41c2-4b0e-9d6a-3c5f2e8b7a19", "length": 120 },
    { "id": "i4", "kind": "media", "title": "Countdown", "media": { "path": "Media/countdown.mp4", "sha256": "…" },
      "position": "pre" },
    { "id": "i5", "kind": "item", "title": "Message", "length": 1800.5 }
  ],
  "externalIds": { "planningCenter": { "planId": "77" } }, "extensions": { "org.example": { "color": "blue" } }
}
"""

/// The canonical bytes of the example with each `(old, new)` text replacement applied.
func planData(_ replacements: [(String, String)] = []) throws -> Data {
    let json = replacements.reduce(planExample) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    return try JSONValue(parsing: Data(json.utf8)).canonicalData()
}

func decodePlan(_ replacements: [(String, String)] = []) throws -> Plan {
    try Plan.decode(from: planData(replacements))
}

func assertPlanDecodeThrows(_ error: FormatError, _ replacements: [(String, String)]) {
    XCTAssertThrowsError(try decodePlan(replacements)) { XCTAssertEqual($0 as? FormatError, error) }
}

final class PlanFormatTests: XCTestCase {
    private func assertRoundTrips(_ replacements: [(String, String)]) throws {
        XCTAssertEqual(try decodePlan(replacements).encoded(), try planData(replacements))
    }

    func testDecodesTheExampleWithEveryItemKindAndEncodesItBackByteForByte() throws {
        try assertRoundTrips([])
        let plan = try decodePlan(), items = plan.items
        XCTAssertEqual(plan.id, UUID(uuidString: "d51b0c3e-7a42-4f0b-b6f1-18a2c9e4d702"))
        XCTAssertEqual([plan.title, plan.date], ["Sunday Gathering", "2026-11-15"])
        XCTAssertEqual(plan.times, [PlanTime(name: "Morning", start: "10:00")])
        XCTAssertEqual(plan.theme, UUID(uuidString: "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421"))
        XCTAssertEqual(plan.items.map(\.kind), [.header, .song, .presentation, .media, .item])
        XCTAssertEqual(plan.externalIds, ["planningCenter": .object(["planId": .string("77")])])
        XCTAssertEqual(plan.extensions, ["org.example": .object(["color": .string("blue")])])
        XCTAssertFalse(plan.isTemplate)
        XCTAssertEqual(items[0], PlanItem(id: "i1", kind: .header, title: "Worship"))
        XCTAssertEqual(items[1].song, UUID(uuidString: "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10"))
        XCTAssertEqual([items[1].arrangement, items[1].key], ["short", "A"])
        XCTAssertEqual(items[1].sequence, ["v1", "c1", "c1"])
        XCTAssertEqual([items[1].length, items[2].length, items[4].length], [240, 120, 1800.5])
        XCTAssertEqual([items[1].position, items[3].position], [.during, .pre])
        XCTAssertEqual(items[1].notes, [PlanNote(category: "Vocals", text: "Repeat the chorus softly")])
        XCTAssertEqual(items[1].externalIds, ["planningCenter": .object(["itemId": .string("901")])])
        XCTAssertEqual(items[2].presentation, UUID(uuidString: "0a9d3f77-41c2-4b0e-9d6a-3c5f2e8b7a19"))
        XCTAssertEqual(items[3].media, MediaReference(path: "Media/countdown.mp4", sha256: "…"))
        XCTAssertEqual(items[4], PlanItem(id: "i5", kind: .item, title: "Message", length: 1800.5))
    }

    func testUnknownFieldsSurviveAtEveryLevel() throws {
        let edits = [
            (#""title": "Sunday Gathering","#, #""title": "Sunday Gathering", "x-plan": 1,"#),
            (#""name": "Morning","#, #""name": "Morning", "x-time": true,"#),
            (#""id": "i1","#, #""id": "i1", "x-item": [1],"#),
            (#""category": "Vocals","#, #""category": "Vocals", "x-note": "n","#),
        ]
        try assertRoundTrips(edits)
        let plan = try decodePlan(edits)
        XCTAssertEqual(plan.unknown, ["x-plan": .integer(1)])
        XCTAssertEqual(plan.times?[0].unknown, ["x-time": .bool(true)])
        XCTAssertEqual(plan.items[0].unknown, ["x-item": .array([.integer(1)])])
        XCTAssertEqual(plan.items[1].notes?[0].unknown, ["x-note": .string("n")])
    }

    func testUnknownKindAndPositionSurvive() throws {
        let edits = [(#""kind": "header""#, #""kind": "offering""#), (#""during""#, #""afterglow""#)]
        try assertRoundTrips(edits)
        let plan = try decodePlan(edits)
        XCTAssertEqual(plan.items[0].kind, PlanItemKind(rawValue: "offering"))
        XCTAssertEqual(plan.items[1].position, PlanItemPosition(rawValue: "afterglow"))
    }

    func testAPlanWithoutADateIsATemplate() throws {
        try assertRoundTrips([(#""date": "2026-11-15","#, "")])
        XCTAssertTrue(try decodePlan([(#""date": "2026-11-15","#, "")]).isTemplate)
    }

    func testAPlanBuiltInCodeRoundTripsWithAbsentFieldsLeftOut() throws {
        let plan = Plan(title: "Midweek", items: [PlanItem(id: "h", kind: .header)])
        let data = try plan.encoded()
        XCTAssertEqual(try Plan.decode(from: data), plan)
        XCTAssertEqual(try Plan.decode(from: data).encoded(), data)
        let keys = ["date", "times", "theme", "song", "presentation", "length", "position", "notes",
                    "externalIds", "extensions", "media", "arrangement", "sequence", "key"]
        for key in keys { XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"\(key)\""), key) }
    }

    func testNewerVersionAndWrongFormatAreRejected() {
        assertPlanDecodeThrows(.unsupportedVersion(found: 2, supported: 1), [(#""version": 1"#, #""version": 2"#)])
        assertPlanDecodeThrows(.wrongFormat(expected: "gss.plan", found: "gss.song"), [(#""gss.plan""#, #""gss.song""#)])
    }

    func testMissingRequiredFieldReportsItsKeyPath() {
        assertPlanDecodeThrows(.missingField("times[0].start"), [(#", "start": "10:00""#, "")])
        assertPlanDecodeThrows(.missingField("items[3].media.sha256"), [(#", "sha256": "…""#, "")])
    }
}
