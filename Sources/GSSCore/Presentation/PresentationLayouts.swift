import Foundation

/// The layout a slide was built from in the editor; unknown layouts are kept as written (ADR 0011).
public struct PresentationSlideLayout: OpenStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let title = Self(rawValue: "title"), titleText = Self(rawValue: "titleText"),
                      text = Self(rawValue: "text"), imageCaption = Self(rawValue: "imageCaption"),
                      image = Self(rawValue: "image")

    /// The theme slots that hold the layout's text, in order; nil for an unknown layout.
    public var textSlots: [String]? {
        switch self {
        case .title, .titleText: return [Theme.titleSlot, Theme.bodySlot]
        case .text: return [Theme.bodySlot]
        case .imageCaption: return [Theme.captionSlot]
        case .image: return []
        default: return nil
        }
    }

    /// The frame of the layout's picture, or nil when it has none; `lyricsFrame` is the theme's `lyrics` frame.
    public func imageFrame(lyricsFrame: ThemeFrame) -> ThemeFrame? {
        switch self {
        case .imageCaption: return ThemeFrame(x: lyricsFrame.x, y: 0.08, width: lyricsFrame.width, height: 0.7)
        case .image: return ThemeFrame(x: 0, y: 0, width: 1, height: 1)
        default: return nil
        }
    }
}

extension PresentationSlide {
    /// A new slide for `layout`: one empty text element per slot of the layout, in `language`.
    public static func empty(id: String, layout: PresentationSlideLayout, language: String) -> PresentationSlide {
        let elements = (layout.textSlots ?? []).map {
            PresentationElement(id: $0, kind: .text, slot: $0, text: [language: ""])
        }
        return PresentationSlide(id: id, elements: elements, layout: layout)
    }

    /// The slide with `layout`, keeping its text (ADR 0011): text in a slot the layout has keeps it, other text
    /// joins `body`; images take the layout's picture frame, or are removed when it has none. An unknown
    /// layout leaves the elements as they are.
    public func changingLayout(to layout: PresentationSlideLayout, lyricsFrame: ThemeFrame) -> PresentationSlide {
        var slide = self
        slide.layout = layout
        guard let slots = layout.textSlots else { return slide }
        let imageFrame = layout.imageFrame(lyricsFrame: lyricsFrame)
        var kept: [PresentationElement] = [], moved: [PresentationElement] = []
        for var element in elements {
            if element.kind == .text {
                let keeps = element.slot.map { $0 == Theme.bodySlot || slots.contains($0) } ?? false
                if keeps { kept.append(element) } else { moved.append(element) }
            } else if element.kind != .image {
                kept.append(element)
            } else if let imageFrame {
                element.frame = imageFrame
                kept.append(element)
            }
        }
        for var element in moved {
            if let body = kept.firstIndex(where: { $0.kind == .text && $0.slot == Theme.bodySlot }) {
                kept[body].text = Self.joined(kept[body].text ?? [:], element.text ?? [:])
            } else {
                (element.slot, element.frame) = (Theme.bodySlot, nil)
                kept.append(element)
            }
        }
        slide.elements = kept
        return slide
    }

    /// `text` with each language of `extra` added on a new line; empty text adds nothing.
    private static func joined(_ text: [String: String], _ extra: [String: String]) -> [String: String] {
        var result = text
        for (language, line) in extra where !line.isEmpty {
            let current = result[language] ?? ""
            result[language] = current.isEmpty ? line : current + "\n" + line
        }
        return result
    }
}
