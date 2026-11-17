import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders the pages of an exported deck into slide images (ADR 0010). It runs during an import, off the main thread
/// and never on the render path, which only shows the finished images.
enum DeckRenderer {
    static let hd = CGSize(width: 1920, height: 1080), ultraHD = CGSize(width: 3840, height: 2160)

    /// A PNG of the page's crop box at its own aspect ratio, as large as fits in `target`; where the page paints nothing
    /// the image is transparent, so a slide shown with `fit` leaves the background visible.
    static func png(of page: CGPDFPage, fitting target: CGSize) -> Data? {
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = min(target.width / box.width, target.height / box.height)
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
