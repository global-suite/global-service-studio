import GSSCore
import SwiftUI

/// Prepare mode: the selected plan item, for this service only. A song item's arrangement and key never change the song.
struct PlanItemEditor: View {
    @ObservedObject var state: AppState
    let appearance: Appearance
    let index: Int
    /// The length as typed; it is saved whenever it reads as minutes:seconds, or cleared when empty.
    @State private var length = ""

    private var item: PlanItem { state.program.plan.items[index] }
    private var song: Song? { item.kind == .song ? item.song.flatMap { state.program.songs[$0] } : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text(state.program.title(of: index)).font(.system(size: 15, weight: .semibold)).foregroundColor(Appearance.label.color).lineLimit(1)
                    Spacer(minLength: 12)
                    Button(Strings.text("Remove from Service")) { state.perform(.removePlanItem(at: index)) }.disabled(index == state.liveItem)
                    Button(Strings.text("Back to Song")) { state.perform(.selectPlanItem(nil)) }
                }
                if song != nil {
                    Text(Strings.text("Arrangement and key here are for this service only. The song in the Library stays as it is."))
                        .font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color).fixedSize(horizontal: false, vertical: true)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    if let song {
                        field("Arrangement") {
                            Picker("", selection: Binding(get: { item.arrangement ?? "" }, set: { id in update { ($0.arrangement, $0.sequence) = (id.isEmpty ? nil : id, nil) } })) {
                                Text(Strings.text("Song Default")).tag("")
                                ForEach(song.arrangements ?? [], id: \.id) { Text($0.name).tag($0.id) }
                            }
                            .labelsHidden().fixedSize()
                        }
                        field("Key of this song") { TextField("", text: text(\.key)).frame(width: 72) }
                    } else {
                        field("Title") { TextField("", text: text(\.title)).frame(maxWidth: 360) }
                    }
                    field("Length") {
                        TextField("0:00", text: $length).frame(width: 72)
                        Text(Strings.text("Minutes:seconds")).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color)
                    }
                    field("Position") {
                        Picker("", selection: Binding(get: { item.position }, set: { position in update { $0.position = position } })) {
                            ForEach([("Pre", PlanItemPosition.pre), ("During", .during), ("Post", .post)], id: \.0) { Text(Strings.text($0.0)).tag(Optional($0.1)) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
            }
            .padding(EdgeInsets(top: 18, leading: 24, bottom: 16, trailing: 24))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .background(appearance.window.color)
        .onAppear { length = PlanEditing.lengthText(item.length) }
        .onChange(of: index) { _ in length = PlanEditing.lengthText(item.length) }
        .onChange(of: length) { text in
            if text.isEmpty { update { $0.length = nil } } else if let seconds = PlanEditing.seconds(text) { update { $0.length = seconds } }
        }
    }

    private func update(_ change: (inout PlanItem) -> Void) {
        var edited = item
        change(&edited)
        state.perform(.updatePlanItem(at: index, edited))
    }

    private func text(_ path: WritableKeyPath<PlanItem, String?>) -> Binding<String> {
        Binding(get: { item[keyPath: path] ?? "" }, set: { value in update { $0[keyPath: path] = value.isEmpty ? nil : value } })
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        GridRow {
            Text(Strings.text(label)).foregroundColor(Appearance.labelSecondary.color).gridColumnAlignment(.trailing)
            HStack(spacing: 8) { content() }
        }
    }
}
