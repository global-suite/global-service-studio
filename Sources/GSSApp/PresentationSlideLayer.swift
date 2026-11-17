import GSSCore
import SwiftUI

/// What an output's slide layer draws: the live lines, or a presentation slide's image with its scaling (issue #137).
enum SlideContent: Equatable {
    case lines([String])
    case image(MediaReference, PresentationImageScaling)

    /// The shown presentation image with the live slide's scaling, else the shown lines; empty while cleared or during a full-screen video.
    init(_ state: AppState, scaling: (PresentationImageScaling) -> PresentationImageScaling = { $0 }) {
        if let image = state.shownImage, let slide = state.liveProgramSlide {
            self = .image(image, scaling(slide.scaling))
        } else {
            self = .lines(state.shownLines)
        }
    }
}

/// The slide layer of an output: the lines in the theme slot, or the presentation image.
struct SlideContentLayer: View {
    let content: SlideContent
    let slot: ThemeSlot
    let libraryFolder: URL
    var shadow = false

    var body: some View {
        switch content {
        case .lines(let lines): SlideLayer(lines: lines, slot: slot, shadow: shadow)
        case .image(let reference, let scaling): PresentationSlideLayer(reference: reference, scaling: scaling, libraryFolder: libraryFolder)
        }
    }
}

/// A presentation slide's image inside the output with its scaling: fit leaves transparent bands, fill crops, stretch distorts (ADR 0010).
/// The image comes decoded from `SlideImageCache`, never in the view body; while the next one loads the previous one stays, and a failed load draws nothing.
struct PresentationSlideLayer: View {
    let reference: MediaReference
    let scaling: PresentationImageScaling
    let libraryFolder: URL
    var cache = SlideImageCache.shared
    @State private var image: CGImage?

    /// Where the image goes in the output: centered, scaled to fit or fill keeping its proportions, or the whole output for stretch.
    /// An unknown scaling is displayed as fit.
    static func scaledRect(imageSize: CGSize, outputSize: CGSize, scaling: PresentationImageScaling) -> CGRect {
        guard scaling != .stretch, imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: outputSize) }
        let (wide, high) = (outputSize.width / imageSize.width, outputSize.height / imageSize.height)
        let scale = scaling == .fill ? max(wide, high) : min(wide, high)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (outputSize.width - size.width) / 2, y: (outputSize.height - size.height) / 2, width: size.width, height: size.height)
    }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                let rect = Self.scaledRect(imageSize: CGSize(width: image.width, height: image.height), outputSize: geometry.size, scaling: scaling)
                Image(decorative: image, scale: 1).resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .clipped()
        .task(id: reference) {
            let loaded = await cache.image(for: reference, libraryFolder: libraryFolder)
            if !Task.isCancelled { image = loaded }
        }
    }
}

extension AppState {
    /// The program slide after the live one; nil at the end of the program.
    var nextProgramSlide: ProgramSlide? { program.slides.indices.contains(programIndex + 1) ? program.slides[programIndex + 1] : nil }

    /// Whether a program slide is a presentation's.
    func isPresentation(_ slide: ProgramSlide) -> Bool {
        program.plan.items.indices.contains(slide.item) && program.plan.items[slide.item].kind == .presentation
    }

    /// Starts decoding the next slide's image at full size in the cache, off the main thread, so moving on shows it at once.
    func preloadNextSlideImage(cache: SlideImageCache = .shared) {
        guard let image = nextProgramSlide?.image else { return }
        let folder = libraryFolder
        Task { await cache.preload(image, libraryFolder: folder) }
    }
}
