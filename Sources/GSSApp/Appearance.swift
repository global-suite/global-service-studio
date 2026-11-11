/// An sRGB color with components from 0 to 1.
public struct RGBA: Equatable, Sendable {
    public let red, green, blue, alpha: Double

    /// A color from 0-255 components, as written in design/system.md.
    public init(_ red: Int, _ green: Int, _ blue: Int, _ alpha: Double = 1) {
        (self.red, self.green, self.blue, self.alpha) = (Double(red) / 255, Double(green) / 255, Double(blue) / 255, alpha)
    }

    /// An opaque color from a hex value such as `0x1C1C1C`.
    public init(hex: Int) {
        self.init(hex >> 16 & 0xFF, hex >> 8 & 0xFF, hex & 0xFF)
    }
}

/// One of the dark appearances of design/system.md; only the surface tokens differ.
public struct Appearance: Equatable, Sendable {
    public let window, contentRaised, sidebar, titlebar, separator: RGBA

    public static let midnight = Appearance(window: RGBA(hex: 0x1C1C1C), contentRaised: RGBA(hex: 0x242424), sidebar: RGBA(22, 22, 22, 0.90), titlebar: RGBA(28, 28, 28, 0.92), separator: RGBA(255, 255, 255, 0.10))
    public static let graphite = Appearance(window: RGBA(hex: 0x1E1E1E), contentRaised: RGBA(hex: 0x2A2A2C), sidebar: RGBA(40, 40, 42, 0.72), titlebar: RGBA(46, 46, 48, 0.86), separator: RGBA(255, 255, 255, 0.10))
    public static let black = Appearance(window: RGBA(hex: 0x000000), contentRaised: RGBA(hex: 0x1C1C1C), sidebar: RGBA(10, 10, 10, 0.94), titlebar: RGBA(10, 10, 10, 0.94), separator: RGBA(255, 255, 255, 0.14))
    /// The default appearance.
    public static let standard = midnight

    // Shared by every appearance.
    public static let control = RGBA(255, 255, 255, 0.08)
    public static let controlHover = RGBA(255, 255, 255, 0.13)
    public static let label = RGBA(255, 255, 255, 0.85)
    public static let labelSecondary = RGBA(255, 255, 255, 0.55)
    public static let labelTertiary = RGBA(255, 255, 255, 0.28)
    public static let accent = RGBA(hex: 0x0A84FF)
    public static let live = RGBA(hex: 0xFF453A)
    public static let next = RGBA(hex: 0xFF9F0A)
    public static let ok = RGBA(hex: 0x32D74B)
    public static let keyGreen = RGBA(hex: 0x00B140)
}
