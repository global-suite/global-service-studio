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
