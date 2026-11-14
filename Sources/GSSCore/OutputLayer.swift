import Foundation

/// A layer of a presentation output, ordered from bottom to top of the composite.
///
/// The raw value is the z-order: a layer with a higher raw value is drawn above
/// every layer with a lower one.
public enum OutputLayer: Int, CaseIterable, Comparable, Codable, Sendable {
    /// Solid background color that fills the screen behind everything else.
    case screenColor = 0
    /// Live video from a capture device, such as a camera feed.
    case videoInput = 1
    /// Background images and videos.
    case media = 2
    /// The current slide: text, lyrics and slide graphics.
    case slide = 3
    /// Announcement loops shown over the slide.
    case announcements = 4
    /// Persistent overlays, such as logos or lower thirds.
    case props = 5
    /// Short messages for the audience, such as a countdown or a notice.
    case messages = 6
    /// Mask that crops or shapes the final composite for the physical screen.
    case mask = 7

    /// Every layer in the order it is composited, from bottom to top.
    public static let compositingOrder: [OutputLayer] = allCases.sorted()

    public static func < (lhs: OutputLayer, rhs: OutputLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What an output is for; the role sets the output's default look: which layers it shows (ADR 0008).
public enum OutputRole: String, CaseIterable, Codable, Sendable {
    /// What the room sees: every layer.
    case audience
    /// A teleprompter for the stage, with its own layout.
    case stage
    /// Words over a key color for a video switcher; never backgrounds or video input.
    case key

    /// The layers the output shows, in compositing order.
    public var layers: [OutputLayer] {
        switch self {
        case .audience: return OutputLayer.compositingOrder
        case .stage: return [.slide, .messages]
        case .key: return [.slide, .props, .messages]
        }
    }

    /// Whether the output shows a layer.
    public func shows(_ layer: OutputLayer) -> Bool { layers.contains(layer) }
}
