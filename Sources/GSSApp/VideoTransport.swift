import SwiftUI

/// The transport of the full-screen video, under the On screen line: its name, Play or Pause, back and forward 10 seconds,
/// the position, the elapsed and remaining time, and Stop Video. Only the transport follows the clock.
struct VideoTransport: View {
    @ObservedObject var state: AppState
    @ObservedObject var clock: VideoClock

    /// A time such as "1:12", or "1:02:05" from one hour.
    static func time(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter(), hours = seconds >= 3600
        (formatter.unitsStyle, formatter.zeroFormattingBehavior) = (.positional, hours ? .default : .pad)
        formatter.allowedUnits = hours ? [.hour, .minute, .second] : [.minute, .second]
        let text = formatter.string(from: max(seconds, 0).rounded(.down)) ?? "0:00"
        // Padded minutes read "01:12"; the transport shows "1:12".
        return !hours && text.hasPrefix("0") ? String(text.dropFirst()) : text
    }

    var body: some View {
        let name = state.fullScreenVideo.map(OnScreenLine.name(of:)) ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Text(name).fontWeight(.semibold).foregroundColor(Appearance.label.color).lineLimit(1)
            HStack(spacing: 8) {
                button(state.isVideoPaused ? "Play" : "Pause", symbol: state.isVideoPaused ? "play.fill" : "pause.fill") { state.perform(.toggleVideoPause) }
                button("Back 10 Seconds", symbol: "gobackward.10") { state.perform(.seekVideo(by: -10)) }
                button("Forward 10 Seconds", symbol: "goforward.10") { state.perform(.seekVideo(by: 10)) }
                Text(Self.time(clock.elapsed)).monospacedDigit().accessibilityLabel(Strings.text("Elapsed time"))
                Slider(value: Binding(get: { clock.elapsed }, set: { state.perform(.setVideoPosition($0)) }), in: 0...max(clock.duration, 0.1))
                    .accessibilityLabel(String(format: Strings.text("Position in %@"), name))
                Text("−" + Self.time(clock.duration - clock.elapsed)).monospacedDigit().accessibilityLabel(Strings.text("Remaining time"))
                Button { state.perform(.stopVideo) } label: { Label(Strings.text("Stop Video"), systemImage: "stop.fill") }
            }
            .controlSize(.small)
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 8, trailing: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Appearance.control.color))
        .accessibilityElement(children: .contain)
    }

    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }.help(Strings.text(title)).accessibilityLabel(Strings.text(title))
    }
}
