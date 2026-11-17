import CoreGraphics
import GSSCore
import SwiftUI

/// What a preview of a presentation slide draws: its image, which may be missing, and how it fills the screen.
struct PresentationPicture: Equatable {
    let image: MediaReference?
    let scaling: PresentationImageScaling
    let libraryFolder: URL
}

extension AppState {
    /// The picture of a program slide of a presentation item; nil for other slides, which show their lines, and outside the program.
    func presentationPicture(at index: Int) -> PresentationPicture? {
        guard program.slides.indices.contains(index) else { return nil }
        let slide = program.slides[index]
        guard program.plan.items[slide.item].kind == .presentation else { return nil }
        return PresentationPicture(image: slide.image, scaling: slide.scaling, libraryFolder: libraryFolder)
    }
}

/// A 16:9 presentation slide over the preview backdrop. The image is decoded off the main thread through the shared cache at
/// `maxPixelSize`; until then, or when it cannot be read, a quiet line says so.
struct PresentationSlideView: View {
    let picture: PresentationPicture
    let maxPixelSize: Int
    @Environment(\.previewBackdrop) private var backdrop
    @State private var loaded: CGImage?
    @State private var isLoading = true

    var body: some View {
        PreviewBackdropView(backdrop: backdrop)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(GeometryReader { proxy in face(proxy.size) })
            .clipped()
            .task(id: picture.image) { await load() }
    }

    @ViewBuilder private func face(_ size: CGSize) -> some View {
        if let loaded {
            let rect = PresentationSlideLayer.scaledRect(imageSize: CGSize(width: loaded.width, height: loaded.height), outputSize: size, scaling: picture.scaling)
            Image(decorative: loaded, scale: 1).resizable().frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        } else {
            Text(Strings.text(isLoading ? "Loading slide…" : "Slide image not found"))
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.7)).lineLimit(1).padding(6)
                .frame(width: size.width, height: size.height)
        }
    }

    private func load() async {
        (loaded, isLoading) = (nil, picture.image != nil)
        guard let image = picture.image else { return }
        let decoded = await SlideImageCache.shared.image(for: image, libraryFolder: picture.libraryFolder, maxPixelSize: maxPixelSize)
        guard !Task.isCancelled else { return }
        (loaded, isLoading) = (decoded, false)
    }
}
