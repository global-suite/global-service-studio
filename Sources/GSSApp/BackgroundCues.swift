import Foundation
import GSSCore

/// Where the program is, as background cues see it (ADR 0008): the plan item, the part of its song, and the backgrounds they name.
struct ProgramPosition: Equatable {
    /// The plan item's id, so edits that move items do not count as entering one.
    let item: String
    /// The part as an index into the item's parts, with its section id; a plain item is part 0 with no section.
    let part: Int
    let section: String
    let songBackground, partBackground: ThemeBackground?
}

/// The background to put on air when the program moves from one position to another, or nil to leave the current one.
/// Entering a song item cues its default; entering a part, forwards or backwards, cues the part's background, which wins.
func backgroundCue(previous: ProgramPosition?, current: ProgramPosition) -> ThemeBackground? {
    let enteredItem = previous?.item != current.item
    let enteredPart = enteredItem || previous?.part != current.part || previous?.section != current.section
    if enteredPart, let part = current.partBackground { return part }
    return enteredItem ? current.songBackground : nil
}

extension Program {
    /// The cue position of a program slide: its plan item, and for a song slide the part Program recorded on it with the backgrounds the song names.
    /// Presentation, plain and stop slides have no part, so they cue nothing; nil outside the program.
    func cuePosition(at index: Int) -> ProgramPosition? {
        guard slides.indices.contains(index) else { return nil }
        let slide = slides[index], item = plan.items[slide.item]
        guard item.kind == .song, let part = slide.partIndex, let section = slide.sectionID, let song = item.song.flatMap({ songs[$0] }) else {
            return ProgramPosition(item: item.id, part: 0, section: "", songBackground: nil, partBackground: nil)
        }
        return ProgramPosition(item: item.id, part: part, section: section, songBackground: song.backgrounds?.defaultBackground,
                               partBackground: song.backgrounds?.sections?[section])
    }
}

extension Background {
    /// The background a cue shows: a color, or an image or video of the library; nil when its file is missing or outside the library.
    init?(cue: ThemeBackground, library: URL) {
        if cue.kind == .color, let hex = cue.color { self = .color(hex); return }
        guard cue.kind == .image || cue.kind == .video, let media = cue.media, media.hasLibraryRelativePath else { return nil }
        let url = library.appendingPathComponent(media.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        self = cue.kind == .image ? .image(url) : .video(url)
    }
}
