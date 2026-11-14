import Foundation
import GSSCore

/// A plan file of the library, with the time it was last modified.
public struct StoredPlan: Equatable, Sendable {
    public let url: URL
    public let modified: Date
    public let plan: Plan
}

/// The plans of a library: the valid ones in file name order, and the files that could not be read with their error.
public struct PlanListing: Sendable {
    public let plans: [StoredPlan]
    public let problems: [(url: URL, error: Error)]
    /// The plans with a date, newest first; plans of the same day by title.
    public var services: [StoredPlan] {
        plans.filter { !$0.plan.isTemplate }.sorted { first, second in
            first.plan.date == second.plan.date ? Self.byTitle(first, second) : first.plan.date ?? "" > second.plan.date ?? ""
        }
    }
    /// The templates, plans without a date, by title ignoring case and accents.
    public var templates: [StoredPlan] { plans.filter(\.plan.isTemplate).sorted(by: Self.byTitle) }

    private static func byTitle(_ first: StoredPlan, _ second: StoredPlan) -> Bool {
        let order = first.plan.title.compare(second.plan.title, options: [.caseInsensitive, .diacriticInsensitive])
        return order == .orderedSame ? first.url.lastPathComponent < second.url.lastPathComponent : order == .orderedAscending
    }
}

/// Why a plan item cannot be used as written (ADR 0009). It is reported for the item, never for the whole plan.
public enum PlanItemProblem: Equatable, Sendable {
    /// No song file of the library holds this `id`.
    case missingSong(UUID)
    /// The song was found but has no arrangement with this id.
    case missingArrangement(String)
}

/// A plan item with the song it refers to, when it is a song item that was found, and its problem, if any.
public struct ResolvedPlanItem: Equatable, Sendable {
    public let item: PlanItem
    public let song: StoredSong?
    public let problem: PlanItemProblem?
}

/// A plan with every item resolved against the library, in plan order.
public struct PlanResolution: Equatable, Sendable {
    public let plan: Plan
    public let items: [ResolvedPlanItem]
}

extension Library {
    public var plansFolder: URL { folder.appendingPathComponent("Plans") }

    /// Writes a valid plan atomically to the file found to hold its `id`, or else to
    /// `Plans/<slug>-<8 hex of id>.plan.json`. An invalid plan throws and nothing is written.
    @discardableResult
    public func save(_ plan: Plan) throws -> URL {
        try plan.validate()
        let name = "\(Self.slug(plan.title, fallback: "plan"))-\(plan.id.uuidString.lowercased().prefix(8)).plan.json"
        let found = try file(holding: plan.id, in: plansFolder, kind: "plan", expected: name, holdsAnotherID: { _ in false }) {
            (try? Plan.decode(from: $0))?.id
        }
        let url = plansFolder.appendingPathComponent(found ?? name)
        try plan.encoded().write(to: url, options: .atomic)
        return url
    }

    /// Reads and validates the plan file at `url`.
    public func loadPlan(at url: URL) throws -> Plan {
        try Plan.decode(from: Data(contentsOf: url))
    }

    /// Reads every `*.plan.json` in `Plans/`, in file name order.
    public func plans() throws -> PlanListing {
        let read = try readAll(in: plansFolder, kind: "plan", decode: Plan.decode)
        return PlanListing(plans: read.items.map { StoredPlan(url: $0.url, modified: $0.modified, plan: $0.item) }, problems: read.problems)
    }

    /// Finds the song of every song item: through `index` when it knows a file that holds the song, else by reading the
    /// song files. A missing song or arrangement is reported on its item; other items are returned without a song.
    public func resolve(_ plan: Plan, index: LibraryIndex? = nil) throws -> PlanResolution {
        var scanned: [UUID: StoredSong]?
        func song(_ id: UUID) throws -> StoredSong? {
            for url in try index?.files(holding: id) ?? [] {
                if let found = try? storedSong(at: url), found.song.id == id { return found }
            }
            if scanned == nil {
                scanned = Dictionary(try songs().songs.map { ($0.song.id, $0) }) { first, _ in first }
            }
            return scanned?[id]
        }
        let items = try plan.items.map { item -> ResolvedPlanItem in
            guard item.kind == .song, let id = item.song else { return ResolvedPlanItem(item: item, song: nil, problem: nil) }
            guard let found = try song(id) else { return ResolvedPlanItem(item: item, song: nil, problem: .missingSong(id)) }
            let arrangements = found.song.arrangements ?? []
            if let arrangement = item.arrangement, !arrangements.contains(where: { $0.id == arrangement }) {
                return ResolvedPlanItem(item: item, song: found, problem: .missingArrangement(arrangement))
            }
            return ResolvedPlanItem(item: item, song: found, problem: nil)
        }
        return PlanResolution(plan: plan, items: items)
    }

    /// The song read from `url`, with its modification time.
    private func storedSong(at url: URL) throws -> StoredSong {
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return StoredSong(url: url, modified: modified, song: try Song.decode(from: Data(contentsOf: url)))
    }
}
