import Foundation

/// This Mac's copy of the moments, kept in Application Support so the app works offline and
/// starts without waiting for iCloud.
public struct MomentLibrary: Equatable, Sendable {
    public var moments: [UUID: Moment] = [:]
    public var deleted: [UUID: Date] = [:]
    /// The sync folder whose `moments.json` was backed up before this Mac first wrote to it.
    public var backedUpFolder: String?

    public init() {}

    /// The moments in list order.
    public var sortedMoments: [Moment] {
        moments.values.sorted(by: Moment.listOrder)
    }

    public var set: MomentSet {
        MomentSet(moments: moments, deleted: deleted)
    }

    // MARK: - Edits

    // Every edit is stamped later than the version it changes, even if this Mac's clock is
    // behind the one that wrote that version, so an edit made after seeing another Mac's change
    // always counts as newer than it.

    /// Adds `moment`, or saves the fields that differ from `original` into the moment with its
    /// id. Saving unchanged content does nothing.
    ///
    /// - Parameter original: The moment as it was when editing began. Only the fields changed
    ///   since then are saved, so a change that arrived from another Mac meanwhile survives. If
    ///   `nil`, every field that differs from the current version is saved.
    public mutating func save(_ moment: Moment, from original: Moment? = nil, now: Date = .now) {
        var moment = moment
        moment.normalizeDates()
        guard let current = moments[moment.id] else {
            // New, or back after being deleted.
            moment.updatedAt = Self.stamp(now: now, after: deleted[moment.id])
            moment.fieldUpdatedAt = [:]
            moments[moment.id] = moment
            return
        }
        let changed = moment.changedFields(from: original ?? current)
        guard !changed.isEmpty else { return }
        var saved = current
        saved.take(changed, from: moment, at: Self.stamp(now: now, after: current.updatedAt))
        moments[moment.id] = saved
    }

    public mutating func delete(_ id: UUID, now: Date = .now) {
        guard let moment = moments.removeValue(forKey: id) else { return }
        deleted[id] = Self.stamp(now: now, after: moment.updatedAt)
    }

    /// Puts the moments in the order of `ids`.
    public mutating func reorder(_ ids: [UUID], now: Date = .now) {
        for (index, id) in ids.enumerated() {
            guard var moment = moments[id], moment.sortWeight != index else { continue }
            moment.sortWeight = index
            save(moment, now: now)
        }
    }

    /// The next weight, for adding a moment at the end of the list.
    public var nextSortWeight: Int {
        (moments.values.map(\.sortWeight).max() ?? -1) + 1
    }

    /// Forgets deletions older than `date`. A Mac that was away longer than that may bring such a
    /// moment back, but nothing is lost.
    public mutating func forgetDeletions(before date: Date) {
        deleted = deleted.filter { $0.value >= date }
    }

    private static func stamp(now: Date, after previous: Date?) -> Date {
        let now = now.wholeSeconds
        guard let previous else { return now }
        return max(now, previous.addingTimeInterval(1))
    }

    // MARK: - Syncing

    /// Merges another copy, e.g. the sync folder's, into this library.
    public func merging(_ other: MomentSet) -> (library: MomentLibrary, merged: MomentSet) {
        let merged = MomentMerge.merge(set, other)
        var library = self
        library.moments = merged.moments
        library.deleted = merged.deleted
        return (library, merged)
    }

    /// Folds in the result of a sync that started from an earlier copy of this library, keeping
    /// any edits made here since.
    public func integrating(_ result: MomentLibrary) -> MomentLibrary {
        guard self != result else { return self }
        var library = result.merging(set).library
        library.backedUpFolder = result.backedUpFolder ?? backedUpFolder
        return library
    }
}

// MARK: - Coding

extension MomentLibrary: Codable {
    private enum CodingKeys: String, CodingKey {
        case moments, deleted, backedUpFolder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let moments = try container.decodeIfPresent([Moment].self, forKey: .moments) ?? []
        let deleted = try container.decodeIfPresent([String: String].self, forKey: .deleted) ?? [:]
        self.moments = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: Moment.merged)
        self.deleted = deleted.reduce(into: [:]) { result, entry in
            if let id = UUID(uuidString: entry.key), let date = ISODate.parse(entry.value) {
                result[id] = date
            }
        }
        backedUpFolder = try container.decodeIfPresent(String.self, forKey: .backedUpFolder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sortedMoments, forKey: .moments)
        try container.encode(
            Dictionary(uniqueKeysWithValues: deleted.map { ($0.key.uuidString, ISODate.string($0.value)) }),
            forKey: .deleted)
        try container.encodeIfPresent(backedUpFolder, forKey: .backedUpFolder)
    }
}
