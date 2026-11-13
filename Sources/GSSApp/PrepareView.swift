import GSSCore
import SwiftUI
import UniformTypeIdentifiers

/// Prepare mode: the guided song builder (song order, words of the selected part, its slides) and the whole song.
struct PrepareView: View {
    @ObservedObject var state: AppState
    let appearance: Appearance
    /// The editor keeps its own text so that a line being typed is not trimmed away; changes are committed with `setLines`.
    @State private var words = ""
    /// The part being dragged to a new place in the song order.
    @State private var dragged: Int?
    /// Parts are dragged as a private type, so a part dropped on the words editor or another app inserts nothing.
    private static let partType = UTType(exportedAs: "org.globalsuite.gss.song-part")

    private var part: SongPart { state.parts[state.selectedPart] }

    var body: some View {
        GeometryReader { proxy in
            let size = SizeClass(contentWidth: proxy.size.width)
            VStack(alignment: .leading, spacing: 20) {
                SongHeader(song: state.song)
                VStack(alignment: .leading, spacing: 8) {
                    step(1, Strings.text("Song order"), hint: Strings.text("The parts of the song, in the order they are sung. Click a part to work on it."))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(state.parts.indices, id: \.self) { chip($0) }; addPartMenu }.padding(4)
                    }
                }
                if size == .compact {
                    HStack(alignment: .top, spacing: 24) { wordsStep.frame(width: (proxy.size.width - 72) / 2); partSlides(columns: 2, width: (proxy.size.width - 72) / 2, fixed: false) }.frame(height: 300)
                    wholeSong(size)
                } else {
                    // The editor gets at least 8 lines and any height step 3 leaves; step 3 shows one slide per row when that still fits.
                    let column: CGFloat = size == .regular ? 520 : 600
                    HStack(alignment: .top, spacing: 24) {
                        GeometryReader { left in
                            VStack(alignment: .leading, spacing: 22) {
                                wordsStep
                                partSlides(columns: gridHeight(1, column) <= left.size.height - 338 ? 1 : 2, width: column, fixed: true)
                            }
                        }
                        .frame(width: column)
                        wholeSong(size)
                    }
                }
            }
            .padding(EdgeInsets(top: 18, leading: 24, bottom: 16, trailing: 24))
        }
        .font(.system(size: 13))
        .background(appearance.window.color)
        .onAppear { words = text(of: part) }
        .onChange(of: part.section.id) { _ in words = text(of: part) }
        .onChange(of: words) { state.perform(.setLines(sectionID: part.section.id, lines: $0.components(separatedBy: .newlines))) }
    }

    private func text(of part: SongPart) -> String { part.section.lines.map { $0.text[state.song.language] ?? "" }.joined(separator: "\n") }

    private func step(_ number: Int, _ title: String, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(number)).font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 20).background(Circle().fill(Appearance.controlHover.color))
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(hint).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color)
        }
        .foregroundColor(Appearance.label.color).lineLimit(1)
    }

    @ViewBuilder private func chip(_ index: Int) -> some View {
        let item = state.parts[index], isSelected = index == state.selectedPart, isLive = index == state.livePart && !state.isCleared
        if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundColor(Appearance.labelTertiary.color) }
        Button { state.perform(.selectPart(index)) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(item.section.kind == .verse ? Appearance.accent.color : item.section.kind == .chorus ? Appearance.label.color : Appearance.labelSecondary.color).frame(width: 8, height: 8)
                    Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
                }
                .padding(.trailing, 18)
                HStack(spacing: 4) {
                    Text(Strings.slideCount(item.slides.count))
                    if let mark = Strings.orderMark(item) { Text("·"); Text(mark) }
                }
                HStack(spacing: 6) {
                    if isSelected { Text(Strings.text("Editing")).fontWeight(.semibold).foregroundColor(Appearance.label.color) }
                    if isLive { Circle().frame(width: 6, height: 6); Text(Strings.text("On screen now")).fontWeight(.semibold) }
                }
                .foregroundColor(Appearance.live.color)
                .frame(height: 13)
            }
            .font(.system(size: 11))
            .foregroundColor(Appearance.labelSecondary.color)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(minWidth: 92, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Appearance.controlHover.color : Appearance.control.color))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Appearance.accent.color : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            Menu { partActions(index) } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.top, 6).padding(.trailing, 6)
                .help(Strings.text("Part Actions")).accessibilityLabel(Strings.text("Part Actions"))
        }
        .contextMenu { partActions(index) }
        .onDrag {
            dragged = index
            return NSItemProvider(item: Data() as NSData, typeIdentifier: Self.partType.identifier)
        }
        .onDrop(of: [Self.partType], isTargeted: nil) { _ in
            defer { dragged = nil }
            guard let from = dragged else { return false }
            state.perform(.moveArrangementItem(from: from, to: index))
            return true
        }
    }

    /// The actions of a part, in its context menu and its … button.
    @ViewBuilder private func partActions(_ index: Int) -> some View {
        Button(Strings.text("Repeat After This")) { state.perform(.insertArrangementItem(sectionID: state.parts[index].section.id, at: index + 1)) }
        Button(Strings.text("Move Left")) { state.perform(.moveArrangementItem(from: index, to: index - 1)) }.disabled(index == 0)
        Button(Strings.text("Move Right")) { state.perform(.moveArrangementItem(from: index, to: index + 1)) }.disabled(index == state.parts.count - 1)
        Divider()
        Button(Strings.text("Remove from Order")) { state.perform(.removeArrangementItem(at: index)) }.disabled(state.parts.count < 2)
    }

    /// The button at the end of the song order: a new section of a kind, or one more time of an existing section.
    private var addPartMenu: some View {
        Menu {
            ForEach(Strings.newSectionKinds, id: \.title) { item in
                Button(Strings.text(item.title)) { state.perform(.addSection(kind: item.kind, at: state.parts.count)) }
            }
            Divider()
            ForEach(state.song.sections, id: \.id) { section in
                Button(String(format: Strings.text("Repeat %@"), Strings.sectionName(section))) { state.perform(.insertArrangementItem(sectionID: section.id, at: state.parts.count)) }
            }
        } label: { Label(Strings.text("Add Part"), systemImage: "plus") }
        .menuStyle(.borderlessButton).fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Appearance.control.color))
        .padding(.leading, 6)
    }

    private var wordsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(2, String(format: Strings.text("Words of %@"), part.name), hint: Strings.text("Type or paste the words, one line per row."))
            TextEditor(text: $words)
                .font(.system(size: 15)).lineSpacing(8).foregroundColor(Appearance.label.color)
                .scrollContentBackground(.hidden).padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(appearance.contentRaised.color))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(appearance.separator.color))
                .frame(minHeight: 200, maxHeight: .infinity)
                .accessibilityLabel(String(format: Strings.text("Words of %@"), part.name))
            Text(Strings.text("Slides are made for you: a new slide starts every 2 lines.")).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color)
        }
    }

    /// Slide width for a number of columns in step 3, at most 420, and the height of those slides with their captions.
    private func slideWidth(_ columns: Int, _ width: CGFloat) -> CGFloat { min(420, (width - 6 - 14 * CGFloat(columns - 1)) / CGFloat(columns)) }
    private func gridHeight(_ columns: Int, _ width: CGFloat) -> CGFloat {
        let rows = CGFloat((part.slides.count + columns - 1) / columns)
        return rows * (slideWidth(columns, width) * 9 / 16 + 26) + 14 * (rows - 1) + 6
    }

    private func partSlides(columns: Int, width: CGFloat, fixed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            step(3, String(format: Strings.text("Slides of %@"), part.name), hint: Strings.slideCount(part.slides.count))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(slideWidth(columns, width)), spacing: 14), count: columns), alignment: .leading, spacing: 14) {
                    ForEach(part.slides.indices, id: \.self) { thumbnail(part.firstSlide + $0, textSize: max(11, slideWidth(columns, width) / 22)) }
                }
                .padding(3)
            }
            .frame(height: fixed ? gridHeight(columns, width) : nil)
            HStack(alignment: .top, spacing: 14) {
                Text(Strings.text("This is how the audience will see them.")).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color)
                Spacer(minLength: 0)
                Button(Strings.text("Edit the look…")) {}.disabled(true).help(Strings.text("Available with the theme editor"))
            }
        }
    }

    /// Every slide of the song with the columns of the Live grid; it takes the space the steps leave.
    private func wholeSong(_ size: SizeClass) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.text("Whole song")).font(.system(size: 15, weight: .semibold)).foregroundColor(Appearance.label.color)
            GeometryReader { grid in
                let layout = Self.songGrid(slides: state.slides.count, standard: size == .compact ? 5 : 6, size: grid.size)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.width), spacing: 10), count: layout.columns), spacing: 10) {
                        ForEach(state.slides.indices, id: \.self) { thumbnail($0, textSize: min(16, max(11, layout.width / 21))) }
                    }
                    .padding(3)
                }
            }
        }
    }

    /// The Live grid's 4 to `standard` columns: the count with the largest slides that all fit the height, or `standard`, scrolling, when that is larger.
    static func songGrid(slides: Int, standard: Int, size: CGSize) -> (columns: Int, width: CGFloat) {
        func width(_ columns: Int) -> CGFloat { (size.width - 6 - 10 * CGFloat(columns - 1)) / CGFloat(columns) }
        let rows = { (columns: Int) in CGFloat((slides + columns - 1) / columns) }
        let fitted: (columns: Int, width: CGFloat) = (4...standard).map { ($0, min(width($0), ((size.height - 6 - 10 * (rows($0) - 1)) / rows($0) - 20) * 16 / 9)) }.max { $0.1 < $1.1 } ?? (standard, 0)
        return fitted.1 >= width(standard) ? fitted : (standard, width(standard))
    }

    /// A slide of the song: the live one has a red ring and LIVE, the selected part's an accent ring and Editing; clicking selects its part.
    private func thumbnail(_ index: Int, textSize: CGFloat) -> some View {
        let isLive = index == state.liveIndex && !state.isCleared, isEditing = part.slideRange.contains(index)
        return SlideThumbnail(number: index + 1, slide: state.slides[index], textSize: textSize, ring: isLive ? Appearance.live : isEditing ? Appearance.accent : appearance.separator,
                              ringWidth: isLive || isEditing ? 3 : 1, badge: isLive ? "LIVE" : isEditing ? "Editing" : nil, dimmed: false) { state.perform(.selectPart(state.part(containing: index))) }
    }
}

/// The song title with its key and tempo, at the top of both modes.
struct SongHeader: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            Text(song.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Appearance.label.color)
            if let key = song.key, let tempo = song.tempo {
                Text(String(format: Strings.text("Key %1$@ · %2$ld bpm"), key, Int(tempo))).foregroundColor(Appearance.labelSecondary.color)
            }
        }
    }
}
