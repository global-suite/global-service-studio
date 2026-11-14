import Foundation

/// Groups a part's lines into slides from a theme's line limit and wrap mode.
///
/// A forced break ends a slide after its line, and each run of lines between forced breaks is grouped on its own.
/// `balanced`, the default for unknown wrap values too, uses the fewest slides that respect the limit and
/// makes their line counts as even as possible, larger slides first. `natural` fills each slide up to the limit.
/// A limit of zero or less is treated as one line per slide.
public enum SlideBreaks {
    /// The ranges of line indices, in order, that make up each slide of `count` lines.
    /// - Parameter breaksAfter: indices of lines that end a slide; indices outside the lines are ignored.
    public static func ranges(count: Int, breaksAfter: Set<Int> = [], maxLines: Int, wrap: ThemeWrap?) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        while start < count {
            let end = (start..<count).first { breaksAfter.contains($0) }.map { $0 + 1 } ?? count
            var lower = start
            for size in sizes(of: end - start, maxLines: max(maxLines, 1), wrap: wrap) {
                result.append(lower..<lower + size)
                lower += size
            }
            start = end
        }
        return result
    }

    /// The slides of a section's lines; a line whose `breakAfter` is `"slide"` ends a slide.
    public static func ranges(of lines: [SongLine], maxLines: Int, wrap: ThemeWrap?) -> [Range<Int>] {
        let breaks = Set(lines.indices.filter { lines[$0].breakAfter == "slide" })
        return ranges(count: lines.count, breaksAfter: breaks, maxLines: maxLines, wrap: wrap)
    }

    /// The line count of each slide for one run of `count` lines without forced breaks; `maxLines` is at least 1.
    private static func sizes(of count: Int, maxLines: Int, wrap: ThemeWrap?) -> [Int] {
        guard count > 0 else { return [] }
        if wrap == .natural {
            return Array(repeating: maxLines, count: count / maxLines) + (count % maxLines > 0 ? [count % maxLines] : [])
        }
        let slides = (count + maxLines - 1) / maxLines
        let base = count / slides, larger = count % slides
        return (0..<slides).map { $0 < larger ? base + 1 : base }
    }
}
