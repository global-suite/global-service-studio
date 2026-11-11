import SwiftUI

extension RGBA {
    var color: Color { Color(nsColor: nsColor) }
}

/// Live mode: the live slide, the next one, the buttons to move and every slide of the song.
struct LiveView: View {
    @ObservedObject var state: AppState
    let appearance: Appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in content(contentWidth: proxy.size.width - 64) }
            .background(appearance.window.color)
    }

    private func content(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(state.song.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Appearance.label.color)
                if let key = state.song.key, let tempo = state.song.tempo {
                    Text(String(format: Strings.text("Key %1$@ · %2$ld bpm"), key, Int(tempo))).foregroundColor(Appearance.labelSecondary.color)
                }
            }
            // The panels share the width; the buttons keep a fixed, compact column.
            let panels = max(contentWidth - Self.buttonsWidth - 40, 400)
            let liveWidth = min(panels * 0.57, Self.maxLiveWidth)
            let height = 28 + liveWidth * 9 / 16
            HStack(alignment: .top, spacing: 20) {
                livePanel.frame(width: liveWidth)
                nextPanel.frame(width: liveWidth * 0.75)
                buttons.frame(width: Self.buttonsWidth).padding(.top, 28)
            }
            .frame(height: height, alignment: .top)
            allSlides
        }
        .font(.system(size: 13))
        .padding(EdgeInsets(top: 18, leading: 32, bottom: 14, trailing: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var livePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().frame(width: 8, height: 8)
                Text(Strings.text("LIVE")).font(.system(size: 13, weight: .heavy))
                Text(Strings.text("On screen now")).font(.system(size: 13, weight: .bold))
                Spacer(minLength: 8)
                Text(state.liveSlide.position).font(.system(size: 11))
            }
            .lineLimit(1)
            .foregroundColor(appearance.window.color)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Appearance.live.color)
            SlideFace(lines: state.liveSlide.lines, size: 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Appearance.live.color, lineWidth: 3))
        .shadow(color: Appearance.live.color.opacity(0.24), radius: 18)
    }

    private var nextPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().strokeBorder(Appearance.next.color, lineWidth: 2).frame(width: 8, height: 8)
                Text(Strings.text("NEXT")).font(.system(size: 11, weight: .semibold)).foregroundColor(Appearance.next.color)
                Spacer(minLength: 8)
                Text(state.nextSlide?.position ?? "").font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color).lineLimit(1)
            }
            .frame(height: 20)
            SlideFace(lines: state.nextSlide?.lines ?? [Strings.text("End of song")], size: 19)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Appearance.next.color, lineWidth: 2))
        }
        .opacity(0.92)
    }

    static let buttonsWidth: CGFloat = 200
    static let maxLiveWidth: CGFloat = 640

    private var buttons: some View {
        VStack(spacing: 8) {
            Button { state.perform(.nextSlide) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Strings.text("Next")).font(.system(size: 17, weight: .bold))
                        Spacer(minLength: 6)
                        Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold))
                    }
                    Text(state.nextSlide?.position ?? Strings.text("End of song")).font(.system(size: 11)).opacity(0.85)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        KeyCap(label: Strings.text("Space"), fill: appearance.window.color)
                        KeyCap(label: "→", fill: appearance.window.color)
                    }
                }
                .foregroundColor(.white)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 96)
                .background(RoundedRectangle(cornerRadius: 8).fill(Appearance.accent.color))
            }
            .disabled(state.nextSlide == nil)
            .opacity(state.nextSlide == nil ? 0.45 : 1)
            Button { state.perform(.previousSlide) } label: {
                HStack(spacing: 8) {
                    KeyCap(label: "←", fill: appearance.window.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.text("Previous")).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
                        Text(state.previousSlide?.position ?? Strings.text("Start of song")).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 8).fill(Appearance.control.color))
            }
            .disabled(state.previousSlide == nil)
            .opacity(state.previousSlide == nil ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .lineLimit(1)
    }

    private var allSlides: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.text("All slides")).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(state.slides.indices, id: \.self) { index in thumbnail(index).id(index) }
                    }
                    .padding(3)
                }
                .frame(height: 292)
                .onChange(of: state.liveIndex) { index in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(index / 5 * 5, anchor: .top) }
                }
            }
        }
    }

    private func thumbnail(_ index: Int) -> some View {
        let isLive = index == state.liveIndex, isNext = index == state.liveIndex + 1
        let ring = isLive ? Appearance.live : isNext ? Appearance.next : appearance.separator
        return Button { state.perform(.goToSlide(index)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                SlideFace(lines: state.slides[index].lines, size: 11)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(index < state.liveIndex ? 0.6 : 1)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(ring.color, lineWidth: isLive ? 3 : isNext ? 2 : 1))
                HStack(spacing: 6) {
                    Text(String(index + 1)).monospacedDigit()
                    Text(state.slides[index].section)
                    Spacer(minLength: 0)
                    if isLive || isNext { Text(Strings.text(isLive ? "LIVE" : "NEXT")).fontWeight(.semibold).foregroundColor(ring.color) }
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
