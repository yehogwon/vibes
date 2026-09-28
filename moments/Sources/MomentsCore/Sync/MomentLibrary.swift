import Foundation

/// This Mac's copy of the moments, kept in Application Support so the app works offline, starts
/// without waiting for iCloud, and remembers what it last synced.
public struct MomentLibrary: Equatable, Sendable {
    public var moments: [UUID: Moment] = [:]
    public var deleted: [UUID: Date] = [:]
    /// The moments as the sync folder had them after this Mac last synced with it: the base a
    /// sync compares both sides against to tell who changed what.
    public var synced: [UUID: Moment] = [:]
    /// The sync folder `synced` belongs to.
    public var syncedFolder: String?
    /// Whether the folder's `moments.json` was backed up before this Mac first wrote to it.
    public var backedUp = false

    public init() {}

    /// The moments in list order.
    public var sortedMoments: [Moment] {
        moments.values.sorted(by: Moment.listOrder)
    }

    public var set: MomentSet {
        MomentSet(moments: moments, deleted: deleted)
    }

    // MARK: - Edits

    // Every edit stamps `updatedAt` later than the version it replaces, even if this Mac's clock
    // is behind the one that wrote that version. So an edit made after seeing another Mac's
    // change always counts as newer than it.

    /// Adds `moment`, or replaces the moment with its id. Saving unchanged content does nothing.
    public mutating func save(_ moment: Moment, now: Date = .now) {
        var moment = moment
        moment.normalizeDates()
        let previous = moments[moment.id]
        if let previous, previous.hasSameContent(as: moment) {
            return
        }
        let replaced = previous?.updatedAt ?? deleted[moment.id]
        moment.updatedAt = Self.stamp(now: now, after: replaced)
        moments[moment.id] = moment
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

    /// Merges what the sync folder has into this library.
    ///
    /// - Returns: The merged library, whose `synced` is the merge (the folder should be updated
    ///   to match it), and the merged moments and deletions.
    public func merging(folder remote: MomentSet, folderPath: String) -> (library: MomentLibrary, merged: MomentSet) {
        // A base from another folder says nothing about this one.
        let base = syncedFolder == folderPath ? synced : [:]
        let merged = MomentMerge.merge(set, remote, base: base)
        var library = self
        library.moments = merged.moments
        library.deleted = merged.deleted
        library.synced = merged.moments
        library.syncedFolder = folderPath
        return (library, merged)
    }

    /// Folds in a sync that started from `snapshot`, keeping any edits made here since.
    public func integrating(_ result: MomentLibrary, from snapshot: MomentLibrary) -> MomentLibrary {
        guard self != snapshot else { return result }
        // Both this library and the result grew from the snapshot, so it's their common base.
        let merged = MomentMerge.merge(set, result.set, base: snapshot.moments)
        var library = result
        library.moments = merged.moments
        library.deleted = merged.deleted
        return library
    }
}

// MARK: - Coding

extension MomentLibrary: Codable {
    private enum CodingKeys: String, CodingKey {
        case moments, deleted, synced, syncedFolder, backedUp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let moments = try container.decodeIfPresent([Moment].self, forKey: .moments) ?? []
        let synced = try container.decodeIfPresent([Moment].self, forKey: .synced) ?? []
        let deleted = try container.decodeIfPresent([String: String].self, forKey: .deleted) ?? [:]
        self.moments = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: MomentMerge.newer)
        self.synced = Dictionary(synced.map { ($0.id, $0) }, uniquingKeysWith: MomentMerge.newer)
        self.deleted = deleted.reduce(into: [:]) { result, entry in
            if let id = UUID(uuidString: entry.key), let date = ISODate.parse(entry.value) {
                result[id] = date
            }
        }
        syncedFolder = try container.decodeIfPresent(String.self, forKey: .syncedFolder)
        backedUp = try container.decodeIfPresent(Bool.self, forKey: .backedUp) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sortedMoments, forKey: .moments)
        try container.encode(synced.values.sorted(by: Moment.listOrder), forKey: .synced)
        try container.encode(
            Dictionary(uniqueKeysWithValues: deleted.map { ($0.key.uuidString, ISODate.string($0.value)) }),
            forKey: .deleted)
        try container.encodeIfPresent(syncedFolder, forKey: .syncedFolder)
        try container.encode(backedUp, forKey: .backedUp)
    }
}
