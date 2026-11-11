import Foundation
import XCTest

@testable import GSSCore

final class OutputLayerTests: XCTestCase {
    func testBottomLayerIsScreenColor() {
        XCTAssertEqual(OutputLayer.compositingOrder.first, .screenColor)
        XCTAssertEqual(OutputLayer.allCases.min(), .screenColor)
    }

    func testTopLayerIsMask() {
        XCTAssertEqual(OutputLayer.compositingOrder.last, .mask)
        XCTAssertEqual(OutputLayer.allCases.max(), .mask)
    }

    func testCompositingOrderIsStrictlyAscending() {
        let order = OutputLayer.compositingOrder
        for (lower, upper) in zip(order, order.dropFirst()) {
            XCTAssertLessThan(lower, upper)
            XCTAssertLessThan(lower.rawValue, upper.rawValue)
        }
    }

    func testCompositingOrderContainsEveryLayerOnce() {
        let order = OutputLayer.compositingOrder
        XCTAssertEqual(order.count, OutputLayer.allCases.count)
        XCTAssertEqual(Set(order), Set(OutputLayer.allCases))
    }

    func testCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(OutputLayer.allCases)
        let decoded = try JSONDecoder().decode([OutputLayer].self, from: encoded)
        XCTAssertEqual(decoded, OutputLayer.allCases)
    }
}
