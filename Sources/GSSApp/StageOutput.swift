import GSSCore
import SwiftUI

/// What singers and the band see: the part and a clock at the top, the live lines large, the next lines below.
/// On a presentation slide it shows only the speaker notes (issue #137).
/// Black, never backgrounds (ADR 0008); while cleared it shows only the clock, as during a full-screen video over a presentation slide.
struct StageOutputView: View {
    @ObservedObject var state: AppState
    static let background = RGBA(hex: 0x000000)

    /// Whether the live slide is a presentation's.
    private static func isPresentation(_ state: AppState) -> Bool { state.liveProgramSlide.map(state.isPresentation) ?? false }
    /// The live presentation slide, except while cleared or hidden by a full-screen video.
    private static func shownPresentation(_ state: AppState) -> LiveSlide? {
        let hidden = state.isCleared || (state.shownImage == nil && state.fullScreenVideo != nil)
        return isPresentation(state) && !hidden ? state.liveSlide : nil
    }
    /// A slide's speaker notes as lines; none when it has none.
    private static func notes(_ slide: ProgramSlide?) -> [String] {
        let notes = slide?.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? [] : notes.components(separatedBy: .newlines)
    }

    /// The live slide's part and repetition, or the presentation and slide number; empty while cleared or with nothing on air.
    static func heading(_ state: AppState) -> String {
        if let slide = shownPresentation(state) {
            return String(format: Strings.text("%1$@ · Slide %2$ld of %3$ld"), slide.section, slide.part, slide.partCount)
        }
        return state.isCleared || isPresentation(state) ? "" : state.liveSlide.heading()
    }
    /// The live lines, or a presentation slide's notes; none while cleared.
    static func lines(_ state: AppState) -> [String] { shownPresentation(state) == nil ? state.shownLines : notes(state.liveProgramSlide) }
    /// A presentation slide without notes: its title, its number and a hint, centered; nil otherwise.
    static func placeholder(_ state: AppState) -> [String]? {
        guard let slide = shownPresentation(state), lines(state).isEmpty else { return nil }
        return [slide.section, String(format: Strings.text("Slide %1$ld of %2$ld"), slide.part, slide.partCount), Strings.text("No notes")]
    }
    /// The next slide's notes or lines, its heading when it has none, or "End of service" after the last slide of the program;
    /// none while cleared or while a full-screen video hides a presentation slide.
    static func next(_ state: AppState) -> [String] {
        guard !state.isCleared, !isPresentation(state) || shownPresentation(state) != nil else { return [] }
        guard let next = state.nextProgramSlide else { return [Strings.text("End of service")] }
        let notes = notes(next)
        return !notes.isEmpty ? notes : next.slide.lines.isEmpty ? [next.slide.heading()] : next.slide.lines
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
                if let placeholder = Self.placeholder(state) {
                    VStack(spacing: height / 40) {
                        Text(placeholder[0]).font(.system(size: height / 12, weight: .bold)).foregroundColor(.white)
                        Text(placeholder[1]).font(.system(size: height / 16, weight: .semibold)).foregroundColor(secondary)
                        Text(placeholder[2]).font(.system(size: height / 20)).foregroundColor(Appearance.labelTertiary.color)
                    }
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(Self.lines(state).joined(separator: "\n"))
                        .font(.system(size: height / 9, weight: .bold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
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
