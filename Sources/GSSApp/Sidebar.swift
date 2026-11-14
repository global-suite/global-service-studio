import GSSLibrary
import SwiftUI

/// The sidebar: the items of the service, with the live and next ones marked in words, and the library's songs with a search field.
/// The search field is a `TextField`, not `.searchable`, which on macOS 13 goes to the toolbar instead of the section.
struct Sidebar: View {
    @ObservedObject var state: AppState
    private let tertiary = Color(nsColor: Appearance.labelTertiary.nsColor)

    var body: some View {
        List(selection: Binding(get: { state.openSongFile }, set: { url in url.map { state.perform(.openLibrarySong($0)) } })) {
            Section(Strings.text("Service")) {
                if state.program.plan.items.isEmpty { Text(Strings.text("Nothing here yet")).foregroundColor(tertiary) }
                ForEach(state.program.plan.items.indices, id: \.self) { serviceRow($0) }
            }
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

    /// A plan item: headers in secondary text; clicking an item previews its slides in Live without putting them on air.
    private func serviceRow(_ item: Int) -> some View {
        let isHeader = state.program.plan.items[item].kind == .header, mark = item == state.liveItem ? "LIVE" : item == state.nextItem ? "NEXT" : nil
        return Button { state.perform(.previewItem(item)) } label: { HStack(spacing: 6) {
            Text(state.program.title(of: item)).fontWeight(isHeader ? .semibold : .regular).foregroundColor(isHeader ? .secondary : .primary).lineLimit(1)
            Spacer(minLength: 4)
            if let mark { Text(Strings.text(mark)).font(.system(size: 10, weight: .bold)).foregroundColor((mark == "LIVE" ? Appearance.live : Appearance.next).color) }
        }.contentShape(Rectangle()) }.buttonStyle(.plain)
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
