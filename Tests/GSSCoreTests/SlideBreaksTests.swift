import GSSCore
import XCTest

final class SlideBreaksTests: XCTestCase {
    private func sizes(_ count: Int, max: Int, _ wrap: ThemeWrap? = nil, breaks: Set<Int> = []) -> [Int] {
        SlideBreaks.ranges(count: count, breaksAfter: breaks, maxLines: max, wrap: wrap).map(\.count)
    }

    func testBalancedUsesFewestSlidesWithEvenCountsLargerFirst() {
        XCTAssertEqual(sizes(5, max: 4, .balanced), [3, 2])
        XCTAssertEqual(sizes(5, max: 2, .balanced), [2, 2, 1])
        XCTAssertEqual(sizes(4, max: 4, .balanced), [4])
        XCTAssertEqual(sizes(6, max: 4, .balanced), [3, 3])
        XCTAssertEqual(sizes(7, max: 3, .balanced), [3, 2, 2])
        XCTAssertEqual(sizes(9, max: 4, .balanced), [3, 3, 3])
    }

    func testBalancedIsTheDefaultAndCoversUnknownWrapValues() {
        XCTAssertEqual(sizes(5, max: 4), [3, 2])
        XCTAssertEqual(sizes(5, max: 4, ThemeWrap(rawValue: "zigzag")), [3, 2])
    }

    func testNaturalFillsEachSlideUpToMaxLines() {
        XCTAssertEqual(sizes(5, max: 4, .natural), [4, 1])
        XCTAssertEqual(sizes(5, max: 2, .natural), [2, 2, 1])
        XCTAssertEqual(sizes(4, max: 4, .natural), [4])
    }

    func testRangesAreContiguousAndCoverEveryLine() {
        XCTAssertEqual(SlideBreaks.ranges(count: 7, maxLines: 3, wrap: .balanced), [0..<3, 3..<5, 5..<7])
        XCTAssertEqual(SlideBreaks.ranges(count: 5, maxLines: 4, wrap: .natural), [0..<4, 4..<5])
    }

    func testForcedBreakEndsASlideAndEachRunIsGroupedAlone() {
        // Lines 0-1 | 2-6: the second run of 5 lines balances to 3 and 2.
        XCTAssertEqual(SlideBreaks.ranges(count: 7, breaksAfter: [1], maxLines: 4, wrap: .balanced), [0..<2, 2..<5, 5..<7])
        XCTAssertEqual(sizes(7, max: 4, .natural, breaks: [1]), [2, 4, 1])
    }

    func testForcedBreakAtTheEndAndConsecutiveBreaks() {
        XCTAssertEqual(sizes(5, max: 4, .balanced, breaks: [4]), [3, 2])
        XCTAssertEqual(SlideBreaks.ranges(count: 5, breaksAfter: [0, 1, 2], maxLines: 4, wrap: .balanced), [0..<1, 1..<2, 2..<3, 3..<5])
        XCTAssertEqual(sizes(3, max: 4, breaks: [5, -1]), [3], "breaks outside the lines are ignored")
    }

    func testMaxLinesOfOneOrLessGivesOneLinePerSlide() {
        XCTAssertEqual(sizes(3, max: 1), [1, 1, 1])
        XCTAssertEqual(sizes(3, max: 0), [1, 1, 1])
        XCTAssertEqual(sizes(3, max: -2, .natural), [1, 1, 1])
    }

    func testEmptyInputGivesNoSlides() {
        XCTAssertEqual(SlideBreaks.ranges(count: 0, maxLines: 4, wrap: .balanced), [])
        XCTAssertEqual(SlideBreaks.ranges(count: 0, breaksAfter: [0], maxLines: 0, wrap: .natural), [])
        XCTAssertEqual(SlideBreaks.ranges(of: [SongLine](), maxLines: 4, wrap: nil), [])
    }

    func testSongLinesBreakOnlyWhereBreakAfterIsSlide() {
        let lines = ["Ember one", "Ember two", "Ember three", "Ember four", "Ember five"].enumerated().map {
            SongLine(text: ["en": $0.element], breakAfter: $0.offset == 0 ? "slide" : $0.offset == 2 ? "line" : nil)
        }
        XCTAssertEqual(SlideBreaks.ranges(of: lines, maxLines: 4, wrap: .balanced), [0..<1, 1..<5])
        XCTAssertEqual(SlideBreaks.ranges(of: lines, maxLines: 2, wrap: .natural), [0..<1, 1..<3, 3..<5])
    }
}
