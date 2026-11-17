import SwiftUI

/// What the audience screens show right now, in plain words, such as
/// "On screen: Lyrics · Chorus · 2 of 2 · Background: Waves (video, muted, looping)".
func onScreenText(_ state: AppState, language: String = Strings.language) -> String {
    let text = { Strings.text($0, language: language) }
    let lyrics = !state.shownLines.isEmpty, part = state.liveSlide.position(language: language)
    let background: String?
    switch state.background {
    case .none: background = nil
    case .color(let hex): background = String(format: text("Background: %@ (color)"), hex)
    case .image(let url): background = String(format: text("Background: %@ (image)"), OnScreenLine.name(of: url))
    case .video(let url): background = OnScreenLine.videoBackground(OnScreenLine.name(of: url), language: language)
    }
    switch (lyrics, background) {
    case (true, let background?): return String(format: text("On screen: Lyrics · %1$@ · %2$@"), part, background)
    case (false, let background?): return String(format: text("On screen: %@ · no lyrics (cleared; Next shows them again)"), background)
    case (true, nil): return String(format: text("On screen: Lyrics · %@ · no background (black behind the lyrics)"), part)
    case (false, nil): return text("On screen: Nothing · the audience screens are black")
    }
}

/// The "On screen" line above the outputs, with Clear Background (F2) while a background is on.
struct OnScreenLine: View {
    @ObservedObject var state: AppState
    /// The button goes under the text in a narrow column.
    let stacked: Bool

    static func name(of url: URL) -> String { url.deletingPathExtension().lastPathComponent }
    static func videoBackground(_ name: String, language: String = Strings.language) -> String {
        String(format: Strings.text("Background: %@ (video, muted, looping)", language: language), name)
    }

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "display").foregroundColor(Appearance.label.color).accessibilityHidden(true)
                Text(onScreenText(state)).foregroundColor(Appearance.label.color).fixedSize(horizontal: false, vertical: true)
            }
            if !stacked { Spacer(minLength: 0) }
            if state.background != .none {
                Button { state.perform(.clearBackground) } label: {
                    HStack(spacing: 6) { Text(Strings.text("Clear Background")); KeyCap(label: "F2", fill: Appearance.controlHover.color) }
                }
                .controlSize(.small)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Appearance.control.color))
        .accessibilityElement(children: .contain)
    }
}
