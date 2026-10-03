import Foundation

/// Every timer one copy knows, and the ones removed: what `timers.json` in the sync folder holds,
/// and this Mac's own copy.
///
/// Removals are kept so that a timer removed on one Mac doesn't come back from another that still
/// has it.
public struct TimerList: Equatable, Sendable {
    public var timers: [UUID: Countdown] = [:]
    /// When each removed timer was removed.
    public var deleted: [UUID: Date] = [:]

    public init(timers: [Countdown] = [], deleted: [UUID: Date] = [:]) {
        // Two entries with one id can only come from a mangled file; keep one, the same one everywhere.
        self.timers = Dictionary(timers.map { ($0.id, $0) }, uniquingKeysWith: Self.pick)
        self.deleted = deleted
    }

    /// The timers in list order.
    public var sorted: [Countdown] {
        timers.values.sorted(by: Countdown.order)
    }

    public mutating func add(_ timer: Countdown) {
        timers[timer.id] = timer
    }

    public mutating func remove(_ id: UUID, now: Date) {
        guard timers.removeValue(forKey: id) != nil else { return }
        deleted[id] = now.wholeSeconds
    }

    /// How long a removal is remembered. A Mac that was away longer than that may bring a removed
    /// timer back, but nothing is lost.
    public static let deletionMemory: TimeInterval = 30 * 24 * 60 * 60

    public mutating func forgetDeletions(at now: Date) {
        let cutoff = now.addingTimeInterval(-Self.deletionMemory)
        deleted = deleted.filter { $0.value >= cutoff }
    }

    /// Combines two copies, e.g. this Mac's and the one in iCloud Drive. Timers added on either
    /// side are kept, and a removal on either side wins, since a timer never changes once it
    /// starts. Neither the order of the copies nor how they're grouped changes the result, so
    /// every Mac settles on the same timers.
    public static func merge(_ a: TimerList, _ b: TimerList) -> TimerList {
        var merged = TimerList()
        merged.deleted = a.deleted.merging(b.deleted, uniquingKeysWith: max)
        merged.timers = a.timers.merging(b.timers, uniquingKeysWith: pick)
        for id in merged.deleted.keys {
            merged.timers[id] = nil
        }
        return merged
    }

    /// One of two different timers with the same id, picked the same way whichever comes first.
    private static func pick(_ a: Countdown, _ b: Countdown) -> Countdown {
        (a.endsAt, a.duration) >= (b.endsAt, b.duration) ? a : b
    }
}

// MARK: - The file

extension TimerList: Codable {
    private enum CodingKeys: String, CodingKey {
        case timers, deleted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timers = try container.decodeIfPresent([Countdown].self, forKey: .timers) ?? []
        let deleted = try container.decodeIfPresent([String: Date].self, forKey: .deleted) ?? [:]
        self.init(
            timers: timers,
            deleted: deleted.reduce(into: [:]) { result, entry in
                if let id = UUID(uuidString: entry.key) {
                    result[id] = max(result[id] ?? entry.value, entry.value)
                }
            })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sorted, forKey: .timers)
        try container.encode(
            Dictionary(uniqueKeysWithValues: deleted.map { ($0.key.uuidString, $0.value) }), forKey: .deleted)
    }
}

/// Reads and writes `timers.json`: pretty-printed JSON with sorted keys, its dates in ISO 8601
/// UTC.
public enum TimerFile {
    public static let name = "timers.json"

    public static func encode(_ list: TimerList) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(list)
    }

    /// An empty file reads as no timers.
    public static func decode(_ data: Data) throws -> TimerList {
        guard !data.isEmpty else { return TimerList() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimerList.self, from: data)
    }
}
