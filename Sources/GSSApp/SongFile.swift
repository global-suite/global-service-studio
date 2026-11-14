import AppKit
import GSSCore
import UniformTypeIdentifiers

/// Opens songs from plain text files; the parsing is `PlainTextSongImporter` in GSSCore.
enum SongFile {
    /// Reads a text file as UTF-8, or in the encoding Foundation detects, and imports it with the file name as fallback title.
    static func read(_ url: URL) throws -> Song {
        var encoding = String.Encoding.utf8
        let text = try (try? String(contentsOf: url, encoding: .utf8)) ?? String(contentsOf: url, usedEncoding: &encoding)
        return try PlainTextSongImporter.song(from: text, fallbackTitle: url.deletingPathExtension().lastPathComponent)
    }

    /// The localized reason a song file could not be opened.
    static func message(for error: Error) -> String {
        Strings.text(error as? PlainTextSongImporter.ImportError == .noLyrics ? "This file has no lyrics." : "This file could not be read.")
    }
}

extension MainWindowController {
    /// File > Open Song…: chooses a plain text file and makes it the current song.
    @objc func openSong(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { self.state.perform(.loadSong(try SongFile.read(url))) } catch {
                let alert = NSAlert()
                (alert.messageText, alert.informativeText) = (Strings.text("The song could not be opened."), SongFile.message(for: error))
                alert.beginSheetModal(for: window)
            }
        }
    }

    /// File > Save Song: saves the current song in the library folder.
    @objc func saveSong(_ sender: Any?) { state.perform(.saveSong) }

    /// File > Choose Library Folder…: chooses a folder, or creates one, and makes it the library.
    @objc func chooseLibraryFolder(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        (panel.canChooseFiles, panel.canChooseDirectories, panel.canCreateDirectories) = (false, true, true)
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.state.perform(.chooseLibraryFolder(url)) }
        }
    }

    /// Shows a failure as an alert on the window.
    func show(_ failure: AppAlert) {
        let alert = NSAlert()
        (alert.messageText, alert.informativeText) = (failure.title, failure.message)
        if let window, window.isVisible { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
