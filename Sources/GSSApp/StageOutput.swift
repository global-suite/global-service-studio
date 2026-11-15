import GSSCore
import SwiftUI

/// What singers and the band see: the part and a clock at the top, the live lines large, the next lines below.
/// Black, never backgrounds (ADR 0008); while cleared it shows only the clock.
struct StageOutputView: View {
    @ObservedObject var state: AppState
    static let background = RGBA(hex: 0x000000)

    /// The live slide's part and repetition; empty while cleared or with nothing on air.
    static func heading(_ state: AppState) -> String { state.isCleared ? "" : state.liveSlide.heading() }
    /// The live lines; none while cleared.
    static func lines(_ state: AppState) -> [String] { state.shownLines }
    /// The next slide's lines, its heading when it has none, or "End of service" after the last slide of the program; none while cleared.
    static func next(_ state: AppState) -> [String] {
        guard !state.isCleared else { return [] }
        guard let next = state.nextSlide else { return [Strings.text("End of service")] }
        return next.lines.isEmpty ? [next.heading()] : next.lines
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height, secondary = Appearance.labelSecondary.color
            VStack(alignment: .leading, spacing: height / 40) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.heading(state)).font(.system(size: height / 16, weight: .semibold)).foregroundColor(secondary)
                    Spacer(minLength: height / 20)
                    TimelineView(.everyMinute) { Text($0.date, style: .time).font(.system(size: height / 11, weight: .semibold)).monospacedDigit() }
                        .foregroundColor(.white)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                Text(Self.lines(state).joined(separator: "\n"))
                    .font(.system(size: height / 9, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                Text(Self.next(state).joined(separator: " / "))
                    .font(.system(size: height / 16))
                    .foregroundColor(secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }
            .padding(height / 18)
            .frame(width: geometry.size.width, height: height, alignment: .topLeading)
        }
        .background(Self.background.color)
    }
}
