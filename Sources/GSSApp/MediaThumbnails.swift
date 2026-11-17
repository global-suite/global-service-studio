import AVFoundation
import Foundation
import GSSLibrary
import ImageIO

/// What a media tile shows: a small picture, the size in pixels and, for a video, the length in seconds; nil when unknown.
struct MediaPreview: Equatable, @unchecked Sendable {
    let image: CGImage?
    let pixelSize: CGSize?
    let duration: Double?
}

/// Makes media previews off the main thread, never in a view body or on the render path, and keeps them by path and modification date.
actor MediaThumbnails {
    static let shared = MediaThumbnails()
    /// The longest side of a thumbnail in pixels.
    static let maxPixelSize = 320
    private var cache: [String: MediaPreview] = [:]

    func preview(of url: URL, kind: MediaFile.Kind, modified: Date) async -> MediaPreview {
        let key = "\(url.path)|\(modified.timeIntervalSinceReferenceDate)"
        if let cached = cache[key] { return cached }
        let made = kind == .image ? Self.imagePreview(url) : await Self.videoPreview(url)
        cache[key] = made
        return made
    }

    /// A thumbnail of an image file with ImageIO, and its size as shown (orientation applied).
    static func imagePreview(_ url: URL) -> MediaPreview {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            return MediaPreview(image: nil, pixelSize: nil, duration: nil)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var size = (properties[kCGImagePropertyPixelWidth] as? Int).flatMap { width in
            (properties[kCGImagePropertyPixelHeight] as? Int).map { CGSize(width: width, height: $0) }
        }
        if let rotated = size, let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
            size = CGSize(width: rotated.height, height: rotated.width)
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize]
        return MediaPreview(image: CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), pixelSize: size, duration: nil)
    }

    /// A poster frame of a video file with AVAssetImageGenerator, its display size and its length.
    static func videoPreview(_ url: URL) async -> MediaPreview {
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds).flatMap { $0.isFinite ? $0 : nil }
        var size: CGSize?
        if let track = try? await asset.loadTracks(withMediaType: .video).first, let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            let shown = CGRect(origin: .zero, size: natural).applying(transform)
            size = CGSize(width: abs(shown.width), height: abs(shown.height))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let image = try? await generator.image(at: CMTime(seconds: min(1, (seconds ?? 0) / 2), preferredTimescale: 600)).image
        return MediaPreview(image: image, pixelSize: size, duration: seconds)
    }

    /// The line under a tile: its kind, then for a video its length, then its size, such as "Video · 0:42 · 1920 × 1080".
    static func caption(kind: MediaFile.Kind, preview: MediaPreview?, language: String = Strings.language) -> String {
        let type = Strings.text(kind == .image ? "Image" : "Video", language: language)
        guard let size = preview?.pixelSize else { return type }
        let pixels = String(format: Strings.text("%1$ld × %2$ld", language: language), Int(size.width), Int(size.height))
        guard kind == .video, let duration = preview?.duration else { return String(format: Strings.text("%1$@ · %2$@", language: language), type, pixels) }
        let formatter = DateComponentsFormatter()
        (formatter.allowedUnits, formatter.unitsStyle, formatter.zeroFormattingBehavior) = (duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second], .positional, .pad)
        // Padded "00:42" becomes "0:42", as video players show it.
        let padded = formatter.string(from: duration.rounded()) ?? "", length = padded.hasPrefix("0") && padded.count > 4 ? String(padded.dropFirst()) : padded
        return String(format: Strings.text("%1$@ · %2$@ · %3$@", language: language), type, length, pixels)
    }
}
