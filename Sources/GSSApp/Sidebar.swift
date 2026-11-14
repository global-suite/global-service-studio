import GSSLibrary
import SwiftUI

/// The sidebar: the service, still a placeholder, and the library's songs with a search field.
/// The search field is a `TextField`, not `.searchable`, which on macOS 13 goes to the toolbar instead of the section.
struct Sidebar: View {
    @ObservedObject var state: AppState
    private let tertiary = Color(nsColor: Appearance.labelTertiary.nsColor)

    var body: some View {
        List(selection: Binding(get: { state.openSongFile }, set: { url in url.map { state.perform(.openLibrarySong($0)) } })) {
            Section(Strings.text("Service")) { Text(Strings.text("Nothing here yet")).foregroundColor(tertiary) }
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
                }
                if !state.libraryProblems.isEmpty { problems }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 28)
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
