import Foundation
import GSSLibrary
import SwiftUI

/// A background of the prepared song as Prepare shows it: its name, kind and library file.
struct SongBackgroundChoice: Equatable {
    let name: String
    let kind: MediaFile.Kind
    let url: URL
}

extension AppState {
    /// The song default (nil section) or a part's own background, or nil when there is none; a part without one follows the song.
    /// Colors and files outside the library are not shown, as the picker cannot choose them.
    func songBackgroundChoice(section: String?) -> SongBackgroundChoice? {
        let backgrounds = song.backgrounds, background = section == nil ? backgrounds?.defaultBackground : section.flatMap { backgrounds?.sections?[$0] }
        guard let background, background.kind == .image || background.kind == .video, let media = background.media, media.hasLibraryRelativePath else { return nil }
        return SongBackgroundChoice(name: ((media.path as NSString).lastPathComponent as NSString).deletingPathExtension,
                                    kind: background.kind == .image ? .image : .video, url: libraryFolder.appendingPathComponent(media.path))
    }
}

/// Prepare's two background rows, saved with the song: the song's background and the selected part's. Change… opens the media bin
/// in a popover, where a click chooses; nothing chosen here goes on the screens.
struct SongBackgroundPicker: View {
    @ObservedObject var state: AppState
    let part: SongPart
    @State private var isPickingSong = false
    @State private var isPickingPart = false

    /// The name of a background, or what a row says without one.
    static func title(of choice: SongBackgroundChoice?, isPart: Bool, language: String = Strings.language) -> String {
        choice?.name ?? Strings.text(isPart ? "Same as the song" : "None · transparent", language: language)
    }

    var body: some View {
        let song = row(Strings.text("Song background"), section: nil, picking: $isPickingSong)
        let part = row(String(format: Strings.text("Background of %@"), part.name), section: part.section.id, picking: $isPickingPart)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 28) { song; part }
            VStack(alignment: .leading, spacing: 8) { song; part }
        }
    }

    private func row(_ label: String, section: String?, picking: Binding<Bool>) -> some View {
        let choice = state.songBackgroundChoice(section: section), isPart = section != nil
        let inherited = isPart && choice == nil ? state.songBackgroundChoice(section: nil) : nil
        return HStack(spacing: 10) {
            SongBackgroundPreview(choice: choice ?? inherited).frame(width: 64, height: 36).opacity(inherited == nil ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color)
                Text(Self.title(of: choice, isPart: isPart)).fontWeight(.semibold).foregroundColor(Appearance.label.color)
            }
            Button(Strings.text("Change…")) { picking.wrappedValue = true }
                .popover(isPresented: picking, arrowEdge: .bottom) {
                    MediaBin(state: state) { file in
                        picking.wrappedValue = false
                        state.perform(.setSongBackground(section: section, file: state.libraryFolder.appendingPathComponent(file.path)))
                    }
                    .padding(12).frame(width: 660, height: 440)
                }
            if choice != nil {
                Button(Strings.text(isPart ? "Use the song's background" : "Remove")) { state.perform(.setSongBackground(section: section, file: nil)) }.buttonStyle(.link)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A small preview of a background: its image or a video frame, made off the main thread, over the checkerboard of a transparent slide.
private struct SongBackgroundPreview: View {
    let choice: SongBackgroundChoice?
    @State private var image: CGImage?

    var body: some View {
        Checkerboard()
            .overlay { if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill) } }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Appearance.labelTertiary.color))
            .task(id: choice) {
                image = nil
                guard let choice else { return }
                let modified = (try? choice.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                image = await MediaThumbnails.shared.preview(of: choice.url, kind: choice.kind, modified: modified).image
            }
            .accessibilityHidden(true)
    }
}
