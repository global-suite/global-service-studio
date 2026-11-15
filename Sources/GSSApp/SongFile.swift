import AppKit
import GSSCore
import UniformTypeIdentifiers

/// Opens songs from OpenLyrics or plain text files; the parsing is `OpenLyricsImporter` and `PlainTextSongImporter` in GSSCore.
enum SongFile {
    /// Reads a song file and lists the verses left out; see `importSong(data:fileName:)`.
    static func open(_ url: URL) throws -> (song: Song, skipped: [OpenLyricsImporter.SkippedVerse]) {
        try importSong(data: Data(contentsOf: url), fileName: url.deletingPathExtension().lastPathComponent)
    }

    /// Reads a song file, without the verses left out.
    static func read(_ url: URL) throws -> Song { try open(url).song }

    /// Picks the importer by content: data that starts, after a byte order mark and white space, with `<` followed by a
    /// letter, `?` or `!` is XML and goes to the OpenLyrics importer, which rejects a root element other than `song`;
    /// anything else, even a line such as "<3", is plain text, read as UTF-8 or in the encoding Foundation detects.
    /// `fileName` is the fallback title.
    static func importSong(data: Data, fileName: String) throws -> (song: Song, skipped: [OpenLyricsImporter.SkippedVerse]) {
        let start = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        let head = Array(start.drop(while: { [0x20, 0x09, 0x0A, 0x0D].contains($0) }).prefix(2))
        let opensTag = head.count == 2 && head[0] == UInt8(ascii: "<") && (Character(UnicodeScalar(head[1])).isLetter || head[1] == UInt8(ascii: "?") || head[1] == UInt8(ascii: "!"))
        if opensTag {
            let imported = try OpenLyricsImporter.read(data, fallbackTitle: fileName)
            return (imported.song, imported.skipped)
        }
        var detected: NSString?
        if String(data: data, encoding: .utf8) == nil {
            _ = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &detected, usedLossyConversion: nil)
        }
        guard let text = String(data: data, encoding: .utf8) ?? detected.map({ $0 as String }) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return (try PlainTextSongImporter.song(from: text, fallbackTitle: fileName), [])
    }

    /// The localized reason a song file could not be opened.
    static func message(for error: Error, language: String = Strings.language) -> String {
        switch error {
        case PlainTextSongImporter.ImportError.noLyrics, OpenLyricsImporter.ImportError.noVerses:
            return Strings.text("This file has no lyrics.", language: language)
        case OpenLyricsImporter.ImportError.malformedXML(let line):
            return String(format: Strings.text("This file is not valid XML (line %ld).", language: language), locale: Locale(identifier: language), line)
        case OpenLyricsImporter.ImportError.notOpenLyrics:
            return Strings.text("This XML file is not an OpenLyrics song.", language: language)
        default:
            return Strings.text("This file could not be read.", language: language)
        }
    }

    /// The informational alert listing the verses the importer left out, one line per verse; nil when there are none.
    static func skippedAlert(_ skipped: [OpenLyricsImporter.SkippedVerse], language: String = Strings.language) -> AppAlert? {
        guard !skipped.isEmpty else { return nil }
        let format = Strings.text("%1$@ (language: %2$@)", language: language)
        let lines = skipped.map { String(format: format, $0.name, $0.language) }
        return AppAlert(title: Strings.text("Some verses were not imported.", language: language), message: lines.joined(separator: "\n"))
    }
}

extension MainWindowController {
    /// File > Open Song…: chooses an OpenLyrics or plain text file and makes it the current song; lists skipped verses.
    @objc func openSong(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .xml]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let opened = try SongFile.open(url)
                self.state.perform(.loadSong(opened.song))
                if let skipped = SongFile.skippedAlert(opened.skipped) { self.show(skipped) }
            } catch {
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
