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
    /// The cue position of a program slide, from its plan item's song as Program builds it; nil outside the program.
    func cuePosition(at index: Int, mode: RepetitionMode) -> ProgramPosition? {
        guard slides.indices.contains(index) else { return nil }
        let itemIndex = slides[index].item, item = plan.items[itemIndex], offset = index - range(of: itemIndex).lowerBound
        guard item.kind == .song, var song = item.song.flatMap({ songs[$0] }) else {
            return ProgramPosition(item: item.id, part: 0, section: "", songBackground: nil, partBackground: nil)
        }
        // The same order for this service as Program's slides: the item's sequence or arrangement.
        if let sequence = item.sequence {
            (song.arrangements, song.defaultArrangement) = ([SongArrangement(id: "", name: "", sequence: sequence)], "")
        } else if let arrangement = item.arrangement, song.arrangements?.contains(where: { $0.id == arrangement }) == true {
            song.defaultArrangement = arrangement
        }
        let parts = SongPart.parts(of: song, mode: mode), part = parts.firstIndex { $0.slideRange.contains(offset) } ?? 0
        let section = parts.indices.contains(part) ? parts[part].section.id : ""
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
