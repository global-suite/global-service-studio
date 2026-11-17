import AppKit
import GSSLibrary
import SwiftUI
import UniformTypeIdentifiers

/// The tabs of the Live drawer over the slide grid: the program's slides, or the library's images and videos.
enum DrawerTab: CaseIterable, Equatable {
    case slides, media
    static let `default` = DrawerTab.slides

    func title(language: String = Strings.language) -> String { Strings.text(self == .slides ? "Slides" : "Images & Videos", language: language) }
}

/// Which kinds the bin shows.
enum MediaFilter: CaseIterable, Equatable {
    case all, images, videos
    var title: String { Strings.text(self == .all ? "All" : self == .images ? "Images" : "Videos") }
    func includes(_ kind: MediaFile.Kind) -> Bool { self == .all || (kind == .image) == (self == .images) }
}

/// What the bin shows: the empty state of a library without media, no matches for the filter and search, or the matching files.
enum MediaBinContent: Equatable {
    case empty, noMatches
    case items([MediaFile])

    init(files: [MediaFile], filter: MediaFilter, search: String) {
        let words = search.trimmingCharacters(in: .whitespaces)
        let shown = files.filter { filter.includes($0.kind) && (words.isEmpty || MediaBin.name(of: $0).localizedStandardContains(words)) }
        self = files.isEmpty ? .empty : shown.isEmpty ? .noMatches : .items(shown)
    }
}

/// The library's images and videos: filters, a name search, Import… and drop, and a grid where a click sets the background.
struct MediaBin: View {
    @ObservedObject var state: AppState
    @State private var filter = MediaFilter.all
    @State private var search = ""
    @State private var selected: String?
    @State private var isTargeted = false
    /// When set, as in Prepare's background picker, a click passes the file here instead of putting it on air, and nothing plays.
    var onChoose: ((MediaFile) -> Void)?

    static func name(of file: MediaFile) -> String { ((file.path as NSString).lastPathComponent as NSString).deletingPathExtension }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("", selection: $filter) { ForEach(MediaFilter.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                if state.isImportingMedia { ProgressView().controlSize(.small); Text(Strings.text("Importing…")).foregroundColor(Appearance.labelSecondary.color) }
                Spacer(minLength: 8)
                TextField(Strings.text("Search media names"), text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                importButton
            }
            .lineLimit(1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Appearance.accent.color, lineWidth: isTargeted ? 3 : 0))
                .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: drop)
        }
        // Return shows the selected item again, after Clear Background for example.
        .background(Button("") { selectedFile.map(choose) }.keyboardShortcut(.return, modifiers: []).opacity(0).accessibilityHidden(true))
        .onAppear { state.perform(.loadMedia) }
    }

    private var selectedFile: MediaFile? { state.mediaFiles.first { $0.path == selected } }

    private var importButton: some View {
        Button { importFiles() } label: { HStack(spacing: 6) { Text(Strings.text("Import…")); KeyCap(label: "⇧⌘I", fill: Appearance.controlHover.color) } }
            .keyboardShortcut("i", modifiers: [.command, .shift])
    }

    @ViewBuilder private var content: some View {
        switch MediaBinContent(files: state.mediaFiles, filter: filter, search: search) {
        case .empty:
            VStack(spacing: 10) {
                Image(systemName: "film").font(.system(size: 32, weight: .light)).foregroundColor(Appearance.labelSecondary.color).accessibilityHidden(true)
                Text(Strings.text("No images or videos yet")).font(.system(size: 15, weight: .semibold)).foregroundColor(Appearance.label.color)
                Text(Strings.text("Drag your images and videos here, or click Import…")).foregroundColor(Appearance.labelSecondary.color).multilineTextAlignment(.center)
            }
            .padding(24)
        case .noMatches:
            Text(Strings.text("No images or videos match your search.")).foregroundColor(Appearance.labelSecondary.color)
        case .items(let files):
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12)], alignment: .leading, spacing: 16) {
                    ForEach(files, id: \.path) { file in
                        let url = state.libraryFolder.appendingPathComponent(file.path)
                        MediaTile(file: file, url: url, onAir: onChoose == nil && state.isOnAir(file), selected: selected == file.path,
                                  playFullScreen: file.kind == .video && onChoose == nil ? { selected = file.path; state.perform(.playFullScreen(url)) } : nil) { choose(file) }
                    }
                }
                .padding(4)
            }
        }
    }

    private func choose(_ file: MediaFile) {
        selected = file.path
        if let onChoose { return onChoose(file) }
        state.perform(.setBackground(state.background(for: file)))
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        (panel.allowedContentTypes, panel.allowsMultipleSelection, panel.canChooseDirectories) = ([.image, .movie], true, false)
        if panel.runModal() == .OK { state.perform(.importMedia(panel.urls)) }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup(), lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [state] in if !urls.isEmpty { state.perform(.importMedia(urls)) } }
        return true
    }
}

/// One image or video: its preview, made off the main thread, its name, kind, length and size, and "On screen" with an accent ring when on air.
/// A video also has Play Full Screen, in its footer and its context menu.
struct MediaTile: View {
    let file: MediaFile, url: URL, onAir: Bool, selected: Bool
    var playFullScreen: (() -> Void)?
    let action: () -> Void
    @State private var preview: MediaPreview?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Color.black.aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { if let image = preview?.image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill) } else { Appearance.control.color } }
                    .overlay(alignment: .top) {
                        if onAir {
                            Text(Strings.text("On screen")).font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 20).background(Appearance.accent.color)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(onAir || selected ? Appearance.accent.color : Appearance.labelTertiary.color, lineWidth: onAir ? 3 : selected ? 2 : 1))
                Text(MediaBin.name(of: file)).fontWeight(.semibold).foregroundColor(Appearance.label.color)
                Text(MediaThumbnails.caption(kind: file.kind, preview: preview)).font(.system(size: 11, weight: .medium)).foregroundColor(Appearance.labelSecondary.color).monospacedDigit()
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if let playFullScreen {
                Button(action: playFullScreen) { Image(systemName: "play.rectangle.fill") }
                    .buttonStyle(.borderless).help(Strings.text("Play Full Screen")).accessibilityLabel(Strings.text("Play Full Screen"))
            }
        }
        .contextMenu { if let playFullScreen { Button(Strings.text("Play Full Screen"), action: playFullScreen) } }
        .task(id: "\(url.path)|\(file.modified.timeIntervalSinceReferenceDate)") {
            preview = await MediaThumbnails.shared.preview(of: url, kind: file.kind, modified: file.modified)
        }
    }
}
