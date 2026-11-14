import Foundation

/// A service plan file (`gss.plan`): the order of service, by reference to songs, presentations and media.
public struct Plan: Equatable, Sendable {
    public static let format = "gss.plan"
    public static let supportedVersion = 1
    public var id: UUID
    public var title: String
    /// The day of the service as `YYYY-MM-DD`; a plan without one is a template.
    public var date: String?
    public var times: [PlanTime]?
    public var theme: UUID?
    public var items: [PlanItem]
    public var externalIds: [String: JSONValue]?
    public var extensions: [String: JSONValue]?
    public var unknown: [String: JSONValue] = [:]
    public init(id: UUID = UUID(), title: String, date: String? = nil, theme: UUID? = nil, items: [PlanItem]) {
        (self.id, self.title, self.date, self.theme, self.items) = (id, title, date, theme, items)
    }
    /// Whether this plan is a template, which it is when it has no date.
    public var isTemplate: Bool { date == nil }

    /// Reads and validates a plan file.
    public static func decode(from data: Data) throws -> Plan {
        var (id, reader) = try Envelope.open(data, format: format, supportedVersion: supportedVersion)
        var plan = try Plan(id: id, title: reader.required("title"), date: reader.optional("date"),
                            theme: reader.optional("theme"), items: reader.required("items"))
        (plan.times, plan.externalIds) = try (reader.optional("times"), reader.optional("externalIds"))
        plan.extensions = try reader.optional("extensions")
        plan.unknown = reader.unknown
        try plan.validate()
        return plan
    }

    /// The canonical bytes of the plan file.
    public func encoded() throws -> Data {
        let fields: [String: JSONValue?] = [
            "title": title.json, "date": date?.json, "times": times?.json, "theme": theme?.json,
            "items": items.json, "externalIds": externalIds?.json, "extensions": extensions?.json,
        ]
        let envelope = Envelope.fields(format: Self.format, version: Self.supportedVersion, id: id)
        return try JSONValue.object(fields.merging(envelope) { $1 }, unknown: unknown).canonicalData()
    }
}
