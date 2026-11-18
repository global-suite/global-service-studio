import Foundation

extension Theme {
    public static let titleSlot = "title", bodySlot = "body", captionSlot = "caption"

    /// The slot named `name`: the theme's own, or for `title`, `body` and `caption` the default derived from
    /// the theme's `lyrics` slot (ADR 0011). `builtInLyrics` stands in when the theme has no `lyrics` slot.
    public func slot(_ name: String, builtInLyrics: ThemeSlot) -> ThemeSlot? {
        if let slot = slots[name] { return slot }
        return Self.defaultSlot(name, from: slots[Self.lyricsSlot] ?? builtInLyrics)
    }

    /// The default of ADR 0011 for `title`, `body` or `caption`, derived from `lyrics`; nil for other names.
    public static func defaultSlot(_ name: String, from lyrics: ThemeSlot) -> ThemeSlot? {
        let frame = lyrics.frame, font = lyrics.font
        switch name {
        case bodySlot:
            var body = lyrics
            body.frame = ThemeFrame(x: frame.x, y: 0.3, width: frame.width, height: 0.6)
            return body
        case titleSlot:
            return ThemeSlot(frame: ThemeFrame(x: frame.x, y: 0.08, width: frame.width, height: 0.18),
                             font: ThemeFont(family: font.family, weight: .bold, size: font.size * 1.4),
                             color: lyrics.color, align: lyrics.align)
        case captionSlot:
            return ThemeSlot(frame: ThemeFrame(x: frame.x, y: 0.82, width: frame.width, height: 0.1),
                             font: ThemeFont(family: font.family, weight: font.weight, size: font.size * 0.6),
                             color: lyrics.color, align: lyrics.align, maxLines: 2)
        default:
            return nil
        }
    }
}
