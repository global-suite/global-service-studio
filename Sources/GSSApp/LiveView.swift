import SwiftUI

extension RGBA {
    var color: Color { Color(nsColor: nsColor) }
}

/// Live mode: the live slide, the next one, the buttons to move, every slide of the program by plan item and the outputs, laid out by size class.
struct LiveView: View {
    @ObservedObject var state: AppState
    let appearance: Appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = SizeClass(contentWidth: proxy.size.width)
            let main = GeometryReader { content(size, width: $0.size.width - 64, height: $0.size.height - 32) }
            if size == .compact {
                VStack(spacing: 0) {
                    main
                    appearance.separator.color.frame(height: 1)
                    bottomBar
                }
            } else {
                HStack(spacing: 0) {
                    main
                    appearance.separator.color.frame(width: 1)
                    outputsColumn(width: size == .wide ? wideOutputsWidth(proxy.size) : 300, height: proxy.size.height)
                }
            }
        }
        .font(.system(size: 13))
        .background(appearance.window.color)
    }

    private func content(_ size: SizeClass, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            // Live and the Next column fill the width and end at the same height:
            // Next's slide plus its label (28) and the buttons (68) match Live's slide plus its band (28).
            // When the height caps Live, Regular and Wide give the width left over to Next, up to Live's width.
            let liveWidth = min(1280, max(min((width + 101) / 2, (height * 0.55 - 28) * 16 / 9), 360))
            let liveHeight = 28 + liveWidth * 9 / 16
            let fillWidth = (liveHeight - 96) * 16 / 9
            let leftover = max(fillWidth, width - liveWidth - 20)
            let nextWidth = size == .compact ? min(760, fillWidth) : size == .wide ? leftover : min(liveWidth, leftover)
            HStack(alignment: .top, spacing: 20) {
                livePanel(width: liveWidth).frame(width: liveWidth, height: liveHeight)
                VStack(alignment: .leading, spacing: 12) { nextPanel(width: nextWidth); buttons(width: nextWidth) }.frame(width: nextWidth)
            }
            .frame(height: max(liveHeight, 96 + nextWidth * 9 / 16))
            allSlides(size)
        }
        .padding(EdgeInsets(top: 18, leading: 32, bottom: 14, trailing: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// In Wide, the outputs column takes the width the top row leaves over (Live at its cap, Next as wide as Live), from 440 to 640.
    private func wideOutputsWidth(_ size: CGSize) -> CGFloat {
        let liveCap = min(1280, ((size.height - 32) * 0.55 - 28) * 16 / 9)
        return min(640, max(440, size.width - 85 - 2 * liveCap))
    }

    private func outputsColumn(width: CGFloat, height: CGFloat) -> some View {
        // Monitors fill the column width, or shrink to fit four in the height; height left over spreads between them.
        let monitorWidth = min(width - 44, max(120, (height - 420) / 4 * 16 / 9))
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle
            ForEach(LiveOutput.samples) { OutputMonitor(output: $0, state: state, width: monitorWidth).frame(maxWidth: .infinity); Spacer(minLength: 6) }
            ClearActions(state: state, stacked: true)
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 16, trailing: 22))
        .frame(width: width)
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle
                HStack(alignment: .top, spacing: 14) { ForEach(LiveOutput.samples) { OutputMonitor(output: $0, state: state, width: 136) } }
            }
            Spacer(minLength: 0)
            ClearActions(state: state, stacked: false).padding(.bottom, 20)
        }
        .padding(EdgeInsets(top: 14, leading: 32, bottom: 16, trailing: 32))
    }

    /// The title of the live item, or of the previewed item with a label that it is not on air and a way back.
    private var header: some View {
        HStack(spacing: 12) {
            Text((state.previewItem ?? state.liveItem).map { state.program.title(of: $0) } ?? "").font(.system(size: 15, weight: .semibold)).foregroundColor(Appearance.label.color)
            if state.previewItem != nil {
                Text(Strings.text("Previewing · not on air")).fontWeight(.semibold).foregroundColor(Appearance.next.color)
                Button(Strings.text("Back to Live Item")) { state.perform(.previewItem(nil)) }.controlSize(.small)
            }
        }.lineLimit(1).frame(height: 20)
    }

    private var sectionTitle: some View {
        Text(Strings.text("Outputs")).font(.system(size: 11, weight: .medium)).foregroundColor(Appearance.labelSecondary.color)
    }

    private func livePanel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().frame(width: 8, height: 8)
                Text(Strings.text("LIVE")).font(.system(size: 13, weight: .heavy))
                Text(Strings.text(state.isCleared ? "Cleared" : state.isOnAir ? "On screen now" : "Nothing on air")).font(.system(size: 13, weight: .bold))
                Spacer(minLength: 8)
                Text(state.isCleared || !state.isOnAir ? "" : state.liveSlide.position).font(.system(size: 11))
            }
            .lineLimit(1)
            .foregroundColor(appearance.window.color)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Appearance.live.color)
            SlideFace(lines: state.shownLines, size: max(24, width / 20))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Appearance.live.color, lineWidth: 3))
        .shadow(color: Appearance.live.color.opacity(0.24), radius: 18)
    }

    private func nextPanel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().strokeBorder(Appearance.next.color, lineWidth: 2).frame(width: 8, height: 8)
                Text(Strings.text("NEXT")).font(.system(size: 11, weight: .semibold)).foregroundColor(Appearance.next.color)
                Spacer(minLength: 8)
                Text(state.nextSlide?.position ?? "").font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color).lineLimit(1)
            }
            .frame(height: 20)
            SlideFace(lines: state.nextSlide?.lines ?? [Strings.text("End of service")], size: max(19, width / 30))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Appearance.next.color, lineWidth: 2))
        }
        .opacity(0.92)
    }

    private func buttons(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            Button { state.perform(.previousSlide) } label: {
                HStack(spacing: 8) {
                    KeyCap(label: "←", fill: appearance.window.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.text("Previous")).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
                        Text(state.previousSlide?.position ?? Strings.text("Start of service")).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Appearance.control.color))
            }
            .disabled(state.previousSlide == nil)
            .opacity(state.previousSlide == nil ? 0.45 : 1)
            .frame(width: min(220, width * 0.38))
            Button { state.perform(.nextSlide) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.text("Next")).font(.system(size: 17, weight: .bold))
                        Text(state.nextSlide?.position ?? Strings.text("End of service")).font(.system(size: 11)).opacity(0.85)
                    }
                    Spacer(minLength: 6)
                    KeyCap(label: Strings.text("Space"), fill: appearance.window.color)
                    KeyCap(label: "→", fill: appearance.window.color)
                    Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Appearance.accent.color))
            }
            .disabled(state.nextSlide == nil)
            .opacity(state.nextSlide == nil ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .lineLimit(1)
        .frame(height: 56)
    }

    private func allSlides(_ size: SizeClass) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.text("All slides")).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
            GeometryReader { grid in ScrollViewReader { proxy in
                let columns = size.gridColumns(slides: state.program.slides.count, width: grid.size.width, height: grid.size.height)
                let textSize = min(16, max(11, (grid.size.width - 10 * CGFloat(columns - 1)) / CGFloat(columns) / 21))
                ScrollView {
                    if state.program.slides.isEmpty { Text(Strings.text("Add songs to the service from the Library.")).foregroundColor(Appearance.labelTertiary.color) }
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(state.program.plan.items.indices, id: \.self) { item in
                            let range = state.program.range(of: item)
                            if state.program.plan.items[item].kind == .header || !range.isEmpty {
                                Text(state.program.title(of: item)).font(.system(size: 12, weight: .semibold)).foregroundColor(Appearance.labelSecondary.color).id("item\(item)")
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                                ForEach(range, id: \.self) { index in thumbnail(index, textSize: textSize).id(index) }
                            }
                        }
                    }
                    .padding(3)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: state.programIndex) { index in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .top) }
                }
                .onChange(of: state.previewItem) { item in withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    if let item { proxy.scrollTo("item\(item)", anchor: .top) } else { proxy.scrollTo(state.programIndex, anchor: .top) }
                } }
            } }
        }
    }

    private func thumbnail(_ index: Int, textSize: CGFloat) -> some View {
        let isLive = index == state.programIndex, isNext = index == state.programIndex + 1
        return SlideThumbnail(number: index + 1, slide: state.program.slides[index].slide, textSize: textSize, ring: isLive ? Appearance.live : isNext ? Appearance.next : appearance.separator,
                              ringWidth: isLive ? 3 : isNext ? 2 : 1, badge: isLive ? "LIVE" : isNext ? "NEXT" : nil, dimmed: index < state.programIndex) { state.perform(.goToSlide(index)) }
    }
}

/// A slide in a grid: its face with a ring, its number and section, and an optional label in the ring color.
struct SlideThumbnail: View {
    let number: Int, slide: LiveSlide, textSize: CGFloat, ring: RGBA, ringWidth: CGFloat, badge: String?, dimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                SlideFace(lines: slide.lines, size: textSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(dimmed ? 0.6 : 1)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(ring.color, lineWidth: ringWidth))
                HStack(spacing: 6) {
                    Text(String(number)).monospacedDigit()
                    Text(slide.section)
                    if let mark = slide.repetitionMark { Text(mark).monospacedDigit() }
                    Spacer(minLength: 0)
                    if let badge { Text(Strings.text(badge)).fontWeight(.semibold).foregroundColor(ring.color) }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Appearance.labelSecondary.color)
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A 16:9 black slide with its lines centered in white.
struct SlideFace: View {
    let lines: [String]
    let size: CGFloat

    var body: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(Text(lines.joined(separator: "\n")).font(.system(size: size, weight: .semibold)).foregroundColor(.white).multilineTextAlignment(.center).padding(6))
    }
}

/// A small key cap next to the action it triggers.
struct KeyCap: View {
    let label: String
    let fill: Color

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Appearance.label.color)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(fill))
    }
}
