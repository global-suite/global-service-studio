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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(state.song.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Appearance.label.color)
                if let key = state.song.key, let tempo = state.song.tempo {
                    Text(String(format: Strings.text("Key %1$@ · %2$ld bpm"), key, Int(tempo))).foregroundColor(Appearance.labelSecondary.color)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                livePanel.frame(minWidth: 300, maxWidth: 392)
                nextPanel.frame(minWidth: 220, maxWidth: 288)
                buttons.frame(minWidth: 240)
            }
            allSlides
        }
        .font(.system(size: 13))
        .padding(EdgeInsets(top: 18, leading: 32, bottom: 14, trailing: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(appearance.window.color)
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

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { state.perform(.previousSlide) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Strings.text("Previous")).font(.system(size: 15, weight: .semibold)).foregroundColor(Appearance.label.color)
                    Text(state.previousSlide?.position ?? Strings.text("Start of song")).foregroundColor(Appearance.labelSecondary.color)
                    Spacer(minLength: 0)
                    KeyCap(label: "←", fill: Appearance.control.color)
                }
                .padding(16)
                .frame(maxWidth: 170, maxHeight: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Appearance.control.color))
            }
            .disabled(state.previousSlide == nil)
            .opacity(state.previousSlide == nil ? 0.45 : 1)
            Button { state.perform(.nextSlide) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(Strings.text("Next")).font(.system(size: 22, weight: .bold))
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right").font(.system(size: 24, weight: .semibold))
                    }
                    Text(state.nextSlide?.position ?? Strings.text("End of song"))
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        KeyCap(label: Strings.text("Space"), fill: appearance.window.color)
                        KeyCap(label: "→", fill: appearance.window.color)
                    }
                }
                .foregroundColor(.white)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Appearance.accent.color))
            }
            .disabled(state.nextSlide == nil)
            .opacity(state.nextSlide == nil ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .lineLimit(1)
        .frame(height: 221)
        .padding(.top, 28)
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
