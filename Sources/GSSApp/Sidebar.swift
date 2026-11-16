import GSSLibrary
import SwiftUI

/// The sidebar: the items of the service, with the live and next ones marked in words, and the library's songs with a search field.
/// The search field is a `TextField`, not `.searchable`, which on macOS 13 goes to the toolbar instead of the section.
struct Sidebar: View {
    @ObservedObject var state: AppState
    private let tertiary = Color(nsColor: Appearance.labelTertiary.nsColor)

    var body: some View {
        List(selection: Binding(get: { state.openSongFile }, set: { url in url.map { state.perform(.openLibrarySong($0)); state.perform(.selectPlanItem(nil)) } })) {
            Section {
                if state.program.plan.items.isEmpty { Text(Strings.text("Nothing here yet")).foregroundColor(tertiary) }
                ForEach(state.program.plan.items.indices, id: \.self) { serviceRow($0) }
                    .onMove { from, to in from.first.map { state.perform(.movePlanItem(from: $0, to: to > $0 ? to - 1 : to)) } }
            } header: { serviceHeader }
            Section(Strings.text("Library")) {
                TextField(Strings.text("Search Songs"), text: Binding(get: { state.librarySearch }, set: { state.perform(.setLibrarySearch($0)) }))
                    .textFieldStyle(.roundedBorder)
                Text(Strings.songCount(state.librarySongs.count)).font(.system(size: 11)).foregroundColor(.secondary)
                if state.librarySongs.isEmpty && !state.isLibraryLoading {
                    let searching = state.librarySearch.contains { $0.isLetter || $0.isNumber }
                    Text(Strings.text(searching ? "No songs match your search." : "Save a song with ⌘S or open a song file with ⌘O."))
                        .foregroundColor(tertiary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(state.librarySongs, id: \.url) { song in
                    // The open song is the selected row: accent fill from the list, and bold so it does not rely on color.
                    Label(song.title, systemImage: "music.note").fontWeight(song.url == state.openSongFile ? .semibold : .regular).lineLimit(1).tag(song.url)
                        .contextMenu {
                            Button(Strings.text("Add as Next Item")) { state.perform(.addToService(song.url, position: .next)) }
                            Button(Strings.text("Add to End of Service")) { state.perform(.addToService(song.url, position: .end)) }
                        }
                }
                if !state.libraryProblems.isEmpty { problems }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 28)
    }

    /// A plan item: headers in secondary text; clicking an item edits it in Prepare, and in Live previews its slides without putting them on air.
    private func serviceRow(_ item: Int) -> some View {
        let isHeader = state.program.plan.items[item].kind == .header, mark = item == state.liveItem ? "LIVE" : item == state.nextItem ? "NEXT" : nil
        let isSelected = state.mode == .prepare && item == state.selectedPlanItem
        return Button { state.perform(state.mode == .prepare ? .selectPlanItem(item) : .previewItem(item)) } label: { HStack(spacing: 6) {
            Text(state.program.title(of: item)).fontWeight(isHeader || isSelected ? .semibold : .regular).foregroundColor(isHeader ? .secondary : .primary).lineLimit(1)
            Spacer(minLength: 4)
            if let mark { Text(Strings.text(mark)).font(.system(size: 10, weight: .bold)).foregroundColor((mark == "LIVE" ? Appearance.live : Appearance.next).color) }
        }.contentShape(Rectangle()) }.buttonStyle(.plain)
        .listRowBackground(isSelected ? RoundedRectangle(cornerRadius: 5).fill(Appearance.controlHover.color).padding(.horizontal, 8) : nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(Strings.text("Move Up")) { state.perform(.movePlanItem(from: item, to: item - 1)) }.disabled(item == 0)
            Button(Strings.text("Move Down")) { state.perform(.movePlanItem(from: item, to: item + 1)) }.disabled(item == state.program.plan.items.count - 1)
            Divider()
            Button(Strings.text("Remove from Service")) { state.perform(.removePlanItem(at: item)) }.disabled(item == state.liveItem)
        }
    }

    /// The Add menu of the Service section: a new item after the item being edited, or at the end, opened in Prepare's editor.
    private var addMenu: some View {
        Menu {
            ForEach(PlanEditing.newKinds, id: \.menu) { kind in
                Button(Strings.text(kind.menu)) {
                    let index = (state.mode == .prepare ? state.selectedPlanItem : nil).map { $0 + 1 } ?? state.program.plan.items.count
                    state.perform(.insertPlanItem(PlanEditing.newItem(kind.kind), at: index))
                    if state.mode == .prepare { state.perform(.selectPlanItem(index)) }
                }
            }
        } label: { Image(systemName: "plus") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(Strings.text("Add to Service")).accessibilityLabel(Strings.text("Add to Service"))
    }

    /// The service's title and date, and "Unsaved" in words while it has unsaved changes.
    private var serviceHeader: some View {
        HStack(spacing: 6) {
            Text(state.program.plan.title).lineLimit(1).truncationMode(.tail)
            if let date = ServiceDate.display(state.program.plan.date) { Text(date).foregroundColor(.secondary).lineLimit(1).layoutPriority(1) }
            if state.hasUnsavedServiceChanges { Text(Strings.text("Unsaved")).foregroundColor(.secondary).lineLimit(1).layoutPriority(1) }
            Spacer(minLength: 4)
            addMenu
        }
    }

    private var problems: some View {
        DisclosureGroup(Strings.problemsTitle(state.libraryProblems.count)) {
            ForEach(state.libraryProblems, id: \.file) { problem in
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.file).lineLimit(1).truncationMode(.middle)
                    Text(problem.reason).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
