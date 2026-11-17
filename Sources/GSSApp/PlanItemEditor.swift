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
    private var deck: Presentation? { item.kind == .presentation ? item.presentation.flatMap { state.program.presentations[$0] } : nil }

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
                    if let deck { field("Scaling") { scaling(deck) } }
                    field("Position") {
                        Picker("", selection: Binding(get: { item.position }, set: { position in update { $0.position = position } })) {
                            ForEach([("Pre", PlanItemPosition.pre), ("During", .during), ("Post", .post)], id: \.0) { Text(Strings.text($0.0)).tag(Optional($0.1)) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
                if let song { sequence(song) }
                if deck != nil { slides }
                notes
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

    /// The parts of a song item for this service, as chips moved with ◀ ▶; the song order until one is changed.
    private func sequence(_ song: Song) -> some View {
        let order = PlanEditing.sequence(of: item, song: song)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.text("Sequence for this service")).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
                if item.sequence == nil { Text(Strings.text("Song order")).font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color) }
                if item.sequence != nil { Button(Strings.text("Use Song Order")) { edit(song, .useSongOrder) }.buttonStyle(.link).font(.system(size: 11)) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(order.enumerated()), id: \.offset) { index, id in
                        HStack(spacing: 4) {
                            chipButton("chevron.left", "Move Left", disabled: index == 0) { edit(song, .move(from: index, to: index - 1)) }
                            Text(song.sections.first { $0.id == id }.map { Strings.sectionName($0) } ?? id).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
                            chipButton("chevron.right", "Move Right", disabled: index == order.count - 1) { edit(song, .move(from: index, to: index + 1)) }
                            chipButton("xmark", "Remove from Order", disabled: order.count < 2) { edit(song, .remove(index)) }
                        }
                        .lineLimit(1).padding(.horizontal, 8).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Appearance.control.color))
                    }
                    Menu {
                        ForEach(song.sections, id: \.id) { section in Button(Strings.sectionName(section)) { edit(song, .add(section.id)) } }
                    } label: { Label(Strings.text("Add Part"), systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Appearance.control.color))
                }
            }
        }
    }

    /// How the whole presentation fills the screen, saved in its library file; Live follows at once.
    private func scaling(_ deck: Presentation) -> some View {
        let current = deck.slides.lazy.flatMap(\.elements).first { $0.kind == .image }?.effectiveScaling ?? .fit
        return VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: Binding(get: { current }, set: { state.perform(.setPresentationScaling(id: deck.id, $0)) })) {
                ForEach([("Fit", PresentationImageScaling.fit), ("Fill", .fill), ("Stretch", .stretch)], id: \.0) { Text(Strings.text($0.0)).tag($0.1) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Text(Strings.text("Fit shows the whole slide, with the background in the bands. Fill crops the edges. Stretch fills the screen without keeping the proportion."))
                .font(.system(size: 11)).foregroundColor(Appearance.labelSecondary.color).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 480, alignment: .leading)
        }
    }

    /// The presentation's slides, small, as Live shows them.
    private var slides: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.text("Slides")).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(Array(state.program.range(of: index)), id: \.self) { slide in
                    if let picture = state.presentationPicture(at: slide) {
                        PresentationSlideView(picture: picture, maxPixelSize: 480).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    /// The notes for each team: a category, typed or chosen from the teams, and the text.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.text("Notes")).font(.system(size: 13, weight: .semibold)).foregroundColor(Appearance.label.color)
            ForEach(Array((item.notes ?? []).enumerated()), id: \.offset) { index, note in
                HStack(spacing: 6) {
                    TextField(Strings.text("Team"), text: Binding(get: { PlanEditing.categoryText(note.category) },
                                                                 set: { text in setNote(index) { $0.category = PlanEditing.category(typed: text) } })).frame(width: 120)
                    Menu { ForEach(PlanEditing.teams, id: \.self) { team in Button(Strings.text(team)) { setNote(index) { $0.category = team } } } } label: { Image(systemName: "chevron.up.chevron.down") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(Strings.text("Team")).accessibilityLabel(Strings.text("Team"))
                    TextField(Strings.text("Note for this team"), text: Binding(get: { note.text }, set: { text in setNote(index) { $0.text = text } })).frame(maxWidth: 480)
                    chipButton("minus.circle", "Remove Note", disabled: false) { state.perform(.updatePlanItem(at: self.index, PlanEditing.edited(item, .remove(index)))) }
                }
            }
            Button { state.perform(.updatePlanItem(at: index, PlanEditing.edited(item, .add))) } label: { Label(Strings.text("Add Note"), systemImage: "plus") }
        }
    }

    /// Changes one note through `updatePlanItem`.
    private func setNote(_ at: Int, _ change: (inout PlanNote) -> Void) {
        guard let notes = item.notes, notes.indices.contains(at) else { return }
        var note = notes[at]
        change(&note)
        state.perform(.updatePlanItem(at: index, PlanEditing.edited(item, .set(at, note))))
    }

    private func edit(_ song: Song, _ edit: PlanEditing.SequenceEdit) { state.perform(.updatePlanItem(at: index, PlanEditing.edited(item, song: song, edit))) }

    private func chipButton(_ symbol: String, _ label: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }.buttonStyle(.borderless).disabled(disabled).help(Strings.text(label)).accessibilityLabel(Strings.text(label))
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
