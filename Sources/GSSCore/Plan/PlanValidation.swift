import Foundation

extension Plan {
    /// Checks the date, start times, item ids, what each item kind needs and lengths.
    ///
    /// Whether a referenced song, arrangement or presentation exists is not checked here: the file
    /// stays valid when one is missing, and the library reports it when the plan is used (ADR 0009).
    public func validate() throws {
        func fail(_ reason: String, _ path: String) -> FormatError { .validation(reason: reason, at: path) }
        if let date, !Self.isCalendarDate(date) { throw fail("invalidDate", "date") }
        for (t, time) in (times ?? []).enumerated() where !Self.isClockTime(time.start) {
            throw fail("invalidTime", "times[\(t)].start")
        }
        var itemIds = Set<String>()
        for (i, item) in items.enumerated() {
            let path = "items[\(i)]"
            if item.id.isEmpty { throw fail("emptyItemId", path + ".id") }
            guard itemIds.insert(item.id).inserted else { throw fail("duplicateItemId", path + ".id") }
            if item.kind == .song, item.song == nil { throw fail("missingSong", path + ".song") }
            if item.kind == .presentation, item.presentation == nil {
                throw fail("missingPresentation", path + ".presentation")
            }
            if item.kind == .media {
                guard let media = item.media else { throw fail("missingMedia", path + ".media") }
                if !media.hasLibraryRelativePath { throw fail("invalidMediaPath", path + ".media.path") }
            }
            if let length = item.length, length < 0 { throw fail("negativeLength", path + ".length") }
        }
    }

    /// The ASCII digits of `text` split at `separator`, if every part has the given number of digits.
    private static func numbers(_ text: String, _ separator: Character, widths: [Int]) -> [Int]? {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.map(\.count) == widths,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        return parts.compactMap { Int($0) }
    }

    /// Whether `text` is a 24-hour `HH:MM` time.
    static func isClockTime(_ text: String) -> Bool {
        numbers(text, ":", widths: [2, 2]).map { $0[0] < 24 && $0[1] < 60 } ?? false
    }

    /// Whether `text` is a `YYYY-MM-DD` day of the Gregorian calendar.
    static func isCalendarDate(_ text: String) -> Bool {
        guard let parts = numbers(text, "-", widths: [4, 2, 2]), (1...12).contains(parts[1]) else { return false }
        let year = parts[0], leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][parts[1] - 1]
        return (1...days).contains(parts[2])
    }
}
