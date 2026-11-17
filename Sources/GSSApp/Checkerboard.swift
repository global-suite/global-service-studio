import GSSCore
import SwiftUI

/// The `transparent` token of design/system.md: a static checkerboard of #2A2A2C and #1E1E1E squares,
/// drawn only in operator previews behind a slide with nothing on the media layer.
struct Checkerboard: View {
    static let light = RGBA(hex: 0x2A2A2C), dark = RGBA(hex: 0x1E1E1E)

    /// The side of a square: 8 points on a 220-point-wide preview, scaling with the width, never under 4.
    static func tileSize(forWidth width: CGFloat) -> CGFloat { max(4, width * 8 / 220) }

    var body: some View {
        Canvas { context, size in
            let tile = Self.tileSize(forWidth: size.width)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.dark.color))
            var squares = Path()
            for row in 0..<Int((size.height / tile).rounded(.up)) {
                for column in stride(from: row % 2, to: Int((size.width / tile).rounded(.up)), by: 2) {
                    squares.addRect(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
                }
            }
            context.fill(squares, with: .color(Self.light.color))
        }
        .accessibilityHidden(true)
    }
}

/// What an operator preview draws behind a slide.
enum PreviewBackdrop: Equatable {
    /// Nothing is on the media layer: the slide is transparent.
    case checkerboard
    /// The background or full-screen video on air.
    case media(MediaFill)
    /// The key output's color.
    case keyColor(RGBA)
    /// The stage output's black.
    case black
}

/// The backdrop of a preview of an output with a role: the audience shows what is on its media layer, else the checkerboard;
/// the key its key color and the stage black, as their outputs do. The theme's screen color never counts as a background.
func previewBackdrop(state: AppState, role: OutputRole) -> PreviewBackdrop {
    switch role {
    case .key: return .keyColor(KeyOutputView.background(state))
    case .stage: return .black
    case .audience: return state.mediaFill(for: .audience).map { .media($0) } ?? .checkerboard
    }
}

/// Draws a preview backdrop; media fills the preview as on the audience output, over its black.
struct PreviewBackdropView: View {
    let backdrop: PreviewBackdrop

    var body: some View {
        switch backdrop {
        case .checkerboard: Checkerboard()
        case .media(let fill): ZStack { AudienceOutputView.background.color; MediaLayer(fill: fill) }
        case .keyColor(let color): color.color
        case .black: Color.black
        }
    }
}

private struct PreviewBackdropKey: EnvironmentKey { static let defaultValue = PreviewBackdrop.checkerboard }

extension EnvironmentValues {
    /// The backdrop slide previews draw behind their lines; the checkerboard unless a view sets what is on air.
    var previewBackdrop: PreviewBackdrop {
        get { self[PreviewBackdropKey.self] }
        set { self[PreviewBackdropKey.self] = newValue }
    }
}
