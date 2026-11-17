import GSSCore
import SwiftUI

/// The whole service at a glance: when each item starts, its length, position and team notes, with section and service totals.
struct RunSheet: Equatable {
    struct Row: Equatable {
        let item: Int
        /// Seconds from midnight when the service has a start time, else from the start of the service.
        let start: Double
        let title: String
        let kind: PlanItemKind
        let key: String?
        /// The item's length; nil when it has none, which counts as 0.
        let length: Double?
        let position: PlanItemPosition?
        let notes: [PlanNote]
        /// For a header, the total length of the items until the next header.
        let sectionLength: Double?
    }
    let rows: [Row]
    /// The first start time of the plan in seconds from midnight; nil without one, when starts are elapsed time from 0:00.
    let start: Double?
    let total: Double
    var end: Double { (start ?? 0) + total }

    init(plan: Plan, title: (Int) -> String) {
        start = plan.times?.first.flatMap { Self.seconds(clock: $0.start) }
        var at = start ?? 0, rows: [Row] = []
        for (index, item) in plan.items.enumerated() {
            let section = item.kind == .header ? plan.items[(index + 1)...].prefix { $0.kind != .header }.reduce(0) { $0 + ($1.length ?? 0) } : nil
            rows.append(Row(item: index, start: at, title: title(index), kind: item.kind, key: item.key, length: item.length,
                            position: item.position, notes: item.notes ?? [], sectionLength: section))
            at += item.length ?? 0
        }
        (self.rows, total) = (rows, at - (start ?? 0))
    }

    /// The seconds from midnight of a 24-hour `HH:MM` time.
    static func seconds(clock: String) -> Double? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? Double(parts[0] * 3600 + parts[1] * 60) : nil
    }

    /// A moment of the service: a clock time in the interface language with a start time, else elapsed minutes:seconds.
    func timeText(_ seconds: Double, language: String = Strings.language) -> String {
        guard start != nil else { return PlanEditing.lengthText(seconds) }
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: language),
                                     calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC") ?? .current)
        return Date(timeIntervalSince1970: seconds).formatted(style)
    }

    /// A length as minutes:seconds, or "—" for an item without one.
    static func lengthText(_ length: Double?) -> String { length.map(PlanEditing.lengthText) ?? "—" }
}

/// Prepare's switch between the selected item and the whole service as a run sheet.
struct PrepareViewBar: View {
    @Binding var showsRunSheet: Bool

    var body: some View {
        HStack {
            Picker("", selection: $showsRunSheet) {
                Text(Strings.text("Item")).tag(false)
                Text(Strings.text("Run Sheet")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().help(Strings.text("Show the selected item or the whole service as a run sheet"))
            Spacer()
        }
        .padding(.horizontal, 24).frame(height: 44)
    }
}

/// The run sheet: one read-only row per plan item, headers with their section total, and the total length and end in the footer.
/// Clicking a row selects the item; the Item view edits it.
struct RunSheetView: View {
    @ObservedObject var state: AppState
    let appearance: Appearance
    private let secondary = Appearance.labelSecondary.color

    var body: some View {
        let sheet = RunSheet(plan: state.program.plan, title: state.program.title(of:))
        VStack(spacing: 0) {
            columns("Start", "Item", "Key of this song", "Length", "Position", "Notes")
                .font(.system(size: 11, weight: .medium)).foregroundColor(secondary).frame(height: 30)
            Rectangle().fill(appearance.separator.color).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) { ForEach(sheet.rows, id: \.item) { row($0, sheet) } }.padding(.vertical, 6)
            }
            Rectangle().fill(appearance.separator.color).frame(height: 1)
            HStack(spacing: 16) {
                Spacer()
                total("Total Length", RunSheet.lengthText(sheet.total))
                total("Ends", sheet.timeText(sheet.end))
            }
            .frame(height: 36)
        }
        .font(.system(size: 13)).padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(appearance.window.color)
    }

    private func row(_ row: RunSheet.Row, _ sheet: RunSheet) -> some View {
        let isHeader = row.kind == .header, isSelected = row.item == state.selectedPlanItem
        let notes = row.notes.map { PlanEditing.categoryText($0.category) + "  " + $0.text }.joined(separator: "\n")
        let length = isHeader ? row.sectionLength.map(RunSheet.lengthText) ?? "" : RunSheet.lengthText(row.length)
        return Button { state.perform(.selectPlanItem(row.item)) } label: {
            HStack(spacing: 8) {
                Text(sheet.timeText(row.start)).foregroundColor(isSelected ? .white : secondary).frame(width: 64, alignment: .leading)
                Text(row.title).fontWeight(isHeader ? .semibold : .medium).frame(maxWidth: .infinity, alignment: .leading)
                Text(row.key ?? "").frame(width: 44, alignment: .leading)
                Text(length).foregroundColor(row.length == nil && !isHeader && !isSelected ? secondary : nil).frame(width: 60, alignment: .trailing)
                Text(row.position.map { position in ["pre": "Pre", "during": "During", "post": "Post"][position.rawValue].map { Strings.text($0) } ?? position.rawValue } ?? "").frame(width: 84, alignment: .leading)
                Text(notes).font(.system(size: 12)).frame(width: 300, alignment: .leading).help(notes)
            }
            .lineLimit(isHeader ? 1 : 2).monospacedDigit().padding(.horizontal, 6).padding(.vertical, isHeader ? 6 : 7)
            .foregroundColor(isSelected ? .white : Appearance.label.color)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Appearance.accent.color.opacity(0.6) : isHeader ? Appearance.control.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func columns(_ titles: String...) -> some View {
        HStack(spacing: 8) {
            Text(Strings.text(titles[0])).frame(width: 64, alignment: .leading)
            Text(Strings.text(titles[1])).frame(maxWidth: .infinity, alignment: .leading)
            Text(Strings.text(titles[2])).frame(width: 44, alignment: .leading)
            Text(Strings.text(titles[3])).frame(width: 60, alignment: .trailing)
            Text(Strings.text(titles[4])).frame(width: 84, alignment: .leading)
            Text(Strings.text(titles[5])).frame(width: 300, alignment: .leading)
        }
        .lineLimit(1).padding(.horizontal, 6)
    }

    private func total(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(Strings.text(label)).foregroundColor(secondary)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
    }
}
