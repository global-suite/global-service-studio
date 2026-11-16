import Foundation
import GSSCore

/// Helpers for editing the service plan: new items, moved indexes and lengths.
enum PlanEditing {
    /// The kinds the sidebar's Add menu creates, with the menu title and the new item's title.
    static let newKinds: [(kind: PlanItemKind, menu: String, title: String)] = [(.header, "Header", "New Header"), (.item, "Item, such as Sermon or Offering", "New Item"),
                                                                                (.presentation, "Presentation Placeholder", "Presentation"), (.media, "Video Placeholder", "Video")]

    /// A new item of a kind with a new id; a presentation or media item is a placeholder whose file is chosen later, which Live skips.
    static func newItem(_ kind: PlanItemKind) -> PlanItem {
        var item = PlanItem(id: UUID().uuidString.lowercased(), kind: kind, title: newKinds.first { $0.kind == kind }.map { Strings.text($0.title) })
        if kind == .presentation { item.presentation = UUID() }
        if kind == .media { item.media = MediaReference(path: "Media", sha256: "") }
        return item
    }

    /// An edit of a song item's sequence for this service only: add a section at the end, remove or move a part, or go back to the song order.
    enum SequenceEdit: Equatable { case add(String), remove(Int), move(from: Int, to: Int), useSongOrder }
    /// An edit of an item's team notes: add a Vocals note, remove one or replace one.
    enum NoteEdit: Equatable { case add, remove(Int), set(Int, PlanNote) }
    /// The team categories the note menu offers, saved in English as ADR 0005 writes them and shown in the interface language.
    static let teams = ["Vocals", "Band", "Media", "Lighting"]

    /// The order of a song item: its own sequence, else its arrangement's, else the song's default order.
    static func sequence(of item: PlanItem, song: Song) -> [String] {
        if let sequence = item.sequence { return sequence }
        let arrangements = song.arrangements ?? []
        let arrangement = arrangements.first { $0.id == item.arrangement } ?? arrangements.first { $0.id == song.defaultArrangement }
        return arrangement?.sequence ?? song.sections.map(\.id)
    }

    /// The item with its sequence edited; the song is never changed. Invalid edits and removing the last part leave the item as it is.
    static func edited(_ item: PlanItem, song: Song, _ edit: SequenceEdit) -> PlanItem {
        var order = sequence(of: item, song: song), edited = item
        switch edit {
        case .add(let id):
            guard song.sections.contains(where: { $0.id == id }) else { return item }
            order.append(id)
        case .remove(let index):
            guard order.indices.contains(index), order.count > 1 else { return item }
            order.remove(at: index)
        case .move(let from, let to):
            guard order.indices.contains(from), order.indices.contains(to), from != to else { return item }
            order.insert(order.remove(at: from), at: to)
        case .useSongOrder:
            edited.sequence = nil
            return edited
        }
        edited.sequence = order
        return edited
    }

    /// The item with its notes edited; no notes left saves none. Invalid indexes leave the item as it is.
    static func edited(_ item: PlanItem, _ edit: NoteEdit) -> PlanItem {
        var notes = item.notes ?? [], edited = item
        switch edit {
        case .add: notes.append(PlanNote(category: teams[0], text: ""))
        case .remove(let index):
            guard notes.indices.contains(index) else { return item }
            notes.remove(at: index)
        case .set(let index, let note):
            guard notes.indices.contains(index) else { return item }
            notes[index] = note
        }
        edited.notes = notes.isEmpty ? nil : notes
        return edited
    }

    /// A note category as shown: a team in the interface language, any other category as written.
    static func categoryText(_ category: String, language: String = Strings.language) -> String {
        teams.contains(category) ? Strings.text(category, language: language) : category
    }

    /// The category to save for a typed one: the team whose shown name it is, else the text as typed.
    static func category(typed text: String, language: String = Strings.language) -> String {
        teams.first { Strings.text($0, language: language) == text } ?? text
    }

    /// Where an item at `index` ends up after the item at `from` moves to the final place `to`.
    static func moved(_ index: Int, from: Int, to: Int) -> Int {
        if index == from { return to }
        let rest = index > from ? index - 1 : index
        return rest >= to ? rest + 1 : rest
    }

    /// A length in seconds as minutes:seconds, such as "5:30"; empty without one.
    static func lengthText(_ seconds: Double?) -> String {
        seconds.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? ""
    }

    /// The seconds of a length typed as minutes:seconds or as minutes; nil when it is not one.
    static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 >= 0 }
        guard (1...2).contains(parts.count), numbers.count == parts.count, numbers.count == 1 || numbers[1] < 60 else { return nil }
        return Double(numbers[0] * 60 + (numbers.count == 2 ? numbers[1] : 0))
    }
}
