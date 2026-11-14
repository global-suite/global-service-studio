import AppKit
import GSSCore
import SwiftUI

/// The built-in themes the outputs use until the theme editor exists (issue #76).
enum OutputThemes {
    private static func lyrics(x: Double, y: Double, width: Double, height: Double, size: Double) -> [String: ThemeSlot] {
        [Theme.lyricsSlot: ThemeSlot(frame: ThemeFrame(x: x, y: y, width: width, height: height),
                                     font: ThemeFont(family: "Helvetica Neue", weight: .bold, size: size), color: "#FFFFFF", align: .center)]
    }

    private static func theme(_ id: String, _ name: String, slots: [String: ThemeSlot]) -> Theme {
        Theme(id: UUID(uuidString: id)!, name: name, canvas: ThemeCanvas(width: 1920, height: 1080),
              background: ThemeBackground(kind: .color, color: "#000000"), slots: slots, languages: ThemeLanguages(layout: .primaryOnly))
    }

    /// Full screen: the lyrics centered over the whole output.
    static let audience = theme("6F0C2B1E-3D4A-4E5F-9A61-0B7C8D9E1F20", "Full Screen",
                                slots: lyrics(x: 0.06, y: 0.1, width: 0.88, height: 0.8, size: 0.07))
    /// Lower third for a video switcher; its background never shows, because the key output has no media layer.
    static let key = theme("2A9D4C7E-81B3-4F06-A5D2-C3E4F5061728", "Lower Third",
                           slots: lyrics(x: 0.05, y: 0.68, width: 0.9, height: 0.26, size: 0.06))

    /// The theme an output with a role draws with; the stage reuses the audience theme for now.
    static func theme(for role: OutputRole) -> Theme { role == .key ? key : audience }

    /// The lyrics slot of a theme, or the audience one when the theme has none.
    static func lyricsSlot(of theme: Theme) -> ThemeSlot { theme.slots[Theme.lyricsSlot] ?? audience.slots[Theme.lyricsSlot]! }
}

extension RGBA {
    /// A color from a theme's `#RRGGBB` or `#RRGGBBAA`, in either case; nil for anything else.
    init?(themeHex hex: String) {
        let digits = hex.dropFirst()
        guard hex.first == "#", [6, 8].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = Int(digits, radix: 16) else { return nil }
        let rgb = digits.count == 8 ? value >> 8 : value
        self.init(rgb >> 16 & 0xFF, rgb >> 8 & 0xFF, rgb & 0xFF, digits.count == 8 ? Double(value & 0xFF) / 255 : 1)
    }
}

/// Where and how a theme slot draws on an output of a given size, in points.
struct SlotLayout: Equatable {
    let frame: CGRect
    /// The font size: the slot's fraction of the output height, made smaller when the lines would not fit the slot's height.
    let fontSize: CGFloat
    let font: NSFont
    let textAlignment: TextAlignment
    let alignment: Alignment
    /// The text color; white when the slot's color cannot be read.
    let color: RGBA

    init(slot: ThemeSlot, size: CGSize, lineCount: Int = 1) {
        let fraction = slot.frame
        frame = CGRect(x: fraction.x * size.width, y: fraction.y * size.height, width: fraction.width * size.width, height: fraction.height * size.height)
        let wanted = slot.font.size * size.height, base = Self.font(slot.font, size: wanted)
        let needed = NSLayoutManager().defaultLineHeight(for: base) * CGFloat(lineCount)
        fontSize = needed > frame.height ? wanted * frame.height / needed : wanted
        font = fontSize < wanted ? Self.font(slot.font, size: fontSize) : base
        switch slot.align {
        case .leading: (textAlignment, alignment) = (.leading, .leading)
        case .trailing: (textAlignment, alignment) = (.trailing, .trailing)
        default: (textAlignment, alignment) = (.center, .center)
        }
        color = RGBA(themeHex: slot.color) ?? RGBA(255, 255, 255)
    }

    /// The theme font at a size: the family with the nearest weight, or the system font of that weight when the family is not installed.
    static func font(_ font: ThemeFont, size: CGFloat) -> NSFont {
        let weights: [ThemeFontWeight: (Int, NSFont.Weight)] = [.regular: (5, .regular), .medium: (6, .medium), .semibold: (8, .semibold), .bold: (9, .bold)]
        let weight = weights[font.weight] ?? (5, .regular)
        return NSFontManager.shared.font(withFamily: font.family, traits: [], weight: weight.0, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight.1)
    }
}
