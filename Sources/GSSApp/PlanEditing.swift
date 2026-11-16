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
