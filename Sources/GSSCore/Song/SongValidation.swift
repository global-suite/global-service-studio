import Foundation

extension Song {
    /// Checks unique ids, references, primary-language text and chord offsets.
    public func validate() throws {
        func fail(_ reason: String, _ path: String) -> FormatError { .validation(reason: reason, at: path) }
        var sectionIds = Set<String>()
        for (s, section) in sections.enumerated() {
            guard sectionIds.insert(section.id).inserted else { throw fail("duplicateSectionId", "sections[\(s)].id") }
            for (l, line) in section.lines.enumerated() {
                let path = "sections[\(s)].lines[\(l)]"
                guard let text = line.text[language] else {
                    throw fail("missingPrimaryText", "\(path).text.\(language)")
                }
                let offsets = 0...text.unicodeScalars.count
                for (c, chord) in (line.chords ?? []).enumerated() where !offsets.contains(chord.at) {
                    throw fail("chordOutOfRange", "\(path).chords[\(c)].at")
                }
            }
        }
        var arrangementIds = Set<String>()
        for (a, arrangement) in (arrangements ?? []).enumerated() {
            guard arrangementIds.insert(arrangement.id).inserted else {
                throw fail("duplicateArrangementId", "arrangements[\(a)].id")
            }
            if let e = arrangement.sequence.firstIndex(where: { !sectionIds.contains($0) }) {
                throw fail("unknownSection", "arrangements[\(a)].sequence[\(e)]")
            }
        }
        if let defaultArrangement, !arrangementIds.contains(defaultArrangement) {
            throw fail("unknownArrangement", "defaultArrangement")
        }
    }
}
