import SwiftUI

/// How the Live view uses the content width, from the Window sizes section of design/system.md.
enum SizeClass: Equatable, Sendable {
    case compact, regular, wide

    init(contentWidth: Double) {
        self = contentWidth < 1600 ? .compact : contentWidth < 2400 ? .regular : .wide
    }

    /// Slides per row: the class default, or down to 4 for larger thumbnails when the whole song still fits the grid without scrolling.
    func gridColumns(slides: Int, width: Double, height: Double) -> Int {
        let standard = self == .compact ? 5 : 6
        func fits(_ columns: Int) -> Bool {
            let rows = Double((slides + columns - 1) / columns)
            let rowHeight = ((width - 6 - 10 * Double(columns - 1)) / Double(columns)) * 9 / 16 + 20
            return rows * rowHeight + 10 * (rows - 1) + 6 <= height
        }
        return fits(standard) ? (4..<standard).first(where: fits) ?? standard : standard
    }
}

/// An output drawn from sample data until the outputs model exists.
struct LiveOutput: Equatable, Identifiable {
    enum Kind { case audience, stage, key }
    let name, role: String
    let kind: Kind
    var id: String { name }

    static let samples = [
        LiveOutput(name: "Center", role: "Audience", kind: .audience),
        LiveOutput(name: "Sides", role: "Audience", kind: .audience),
        LiveOutput(name: "Stage", role: "Teleprompter", kind: .stage),
        LiveOutput(name: "Key", role: "Lower third · switcher", kind: .key),
    ]
}

/// A 16:9 preview of what one output shows, with its name, role and status.
struct OutputMonitor: View {
    let output: LiveOutput
    @ObservedObject var state: AppState
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            screen
                .frame(width: width, height: width * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Appearance.labelTertiary.color, lineWidth: 1))
            HStack(spacing: 6) {
                Text(Strings.text(output.name)).fontWeight(.semibold).foregroundColor(Appearance.label.color)
                Spacer(minLength: 4)
                Circle().fill(Appearance.live.color).frame(width: 6, height: 6)
                Text(Strings.text("Live")).font(.system(size: 11, weight: .medium)).foregroundColor(Appearance.live.color)
            }
            .lineLimit(1)
            Text(Strings.text(output.role)).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color).lineLimit(1)
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var screen: some View {
        let lines = state.shownLines.joined(separator: "\n")
        switch output.kind {
        case .audience:
            AudienceOutputView(state: state)
        case .stage:
            VStack(alignment: .leading, spacing: width / 60) {
                HStack {
                    Text(state.isCleared ? "" : state.liveSlide.heading())
                    Spacer()
                    TimelineView(.everyMinute) { Text($0.date, style: .time).font(.system(size: width / 20, weight: .semibold)).monospacedDigit().foregroundColor(.white) }
                }
                .foregroundColor(Appearance.labelSecondary.color)
                Spacer(minLength: 0)
                Text(lines).font(.system(size: width / 18, weight: .bold)).foregroundColor(.white)
                Spacer(minLength: 0)
                Text(state.nextSlide?.lines.joined(separator: " / ") ?? Strings.text("End of song")).foregroundColor(Appearance.labelSecondary.color)
            }
            .font(.system(size: width / 30))
            .padding(width / 25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.black)
        case .key:
            KeyOutputView(state: state)
        }
    }
}

/// Clear Slide (F1), Clear Background (F2) and Clear All (F3), in a row or a column; Clear Background needs a background.
struct ClearActions: View {
    @ObservedObject var state: AppState
    let stacked: Bool

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        let pair = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            pair {
                button("Clear Slide", "F1", danger: false) { state.perform(.clearSlide) }
                button("Clear Background", "F2", danger: false) { state.perform(.clearBackground) }
                    .disabled(state.background == .none)
                    .opacity(state.background == .none ? 0.45 : 1)
            }
            button("Clear All", "F3", danger: true) { state.perform(.clearAll) }
        }
        .buttonStyle(.plain)
        .lineLimit(1)
    }

    private func button(_ title: String, _ key: String, danger: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(Strings.text(title)).fontWeight(.medium).foregroundColor(Appearance.label.color)
                KeyCap(label: key, fill: Appearance.control.color)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: stacked ? .infinity : nil, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(danger ? Appearance.live.color.opacity(0.16) : Appearance.control.color))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(danger ? Appearance.live.color.opacity(0.24) : .clear))
        }
    }
}
