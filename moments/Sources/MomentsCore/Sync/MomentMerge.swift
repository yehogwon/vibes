import Foundation

/// Everything one copy knows: its moments, when moments were deleted, and any entries of the file
/// that couldn't be read.
public struct MomentSet: Equatable, Sendable {
    public var moments: [UUID: Moment]
    /// When each deleted moment was deleted. A moment edited after that counts as alive again.
    public var deleted: [UUID: Date]
    public var unreadable: [JSONValue]

    public init(moments: [UUID: Moment] = [:], deleted: [UUID: Date] = [:], unreadable: [JSONValue] = []) {
        self.moments = moments
        self.deleted = deleted
        self.unreadable = unreadable
    }

    public init(list: MomentList, deleted: [UUID: Date] = [:]) {
        // Two entries with one id can only come from a mangled file; keep the newer.
        let moments = Dictionary(list.moments.map { ($0.id, $0) }, uniquingKeysWith: MomentMerge.newer)
        self.init(moments: moments, deleted: deleted, unreadable: list.unreadable)
    }

    public var list: MomentList {
        MomentList(moments: Array(moments.values), unreadable: unreadable)
    }
}

/// Combines two copies of the moments, e.g. this Mac's and the one in iCloud Drive.
///
/// Nothing is lost when both sides changed:
/// - Moments added on either side are kept.
/// - A moment changed on both sides keeps the fields each side changed; a field both changed
///   takes the newer version's value.
/// - A deletion wins over edits made before it; an edit made after it brings the moment back.
///   A moment missing from one side is never taken as deleted, only a recorded deletion is.
///
/// The result doesn't depend on which side is which, so every Mac settles on the same moments.
public enum MomentMerge {
    /// - Parameter base: The moments as both sides last had them in common (what this Mac last
    ///   synced). It tells which side changed which field; without it, the newer version of a
    ///   moment wins whole.
    public static func merge(_ local: MomentSet, _ remote: MomentSet, base: [UUID: Moment]) -> MomentSet {
        var deleted = local.deleted
        deleted.merge(remote.deleted, uniquingKeysWith: max)

        var moments: [UUID: Moment] = [:]
        for id in Set(local.moments.keys).union(remote.moments.keys) {
            let merged: Moment
            switch (local.moments[id], remote.moments[id]) {
            case (let local?, let remote?): merged = mergeMoment(local, remote, base: base[id])
            case (let local?, nil): merged = local
            case (nil, let remote?): merged = remote
            case (nil, nil): continue
            }
            if let deletedAt = deleted[id], merged.updatedAt <= deletedAt {
                continue
            }
            moments[id] = merged
        }

        var unreadable = remote.unreadable
        for value in local.unreadable where !unreadable.contains(value) {
            unreadable.append(value)
        }
        return MomentSet(moments: moments, deleted: deleted, unreadable: unreadable)
    }

    /// Picks what to keep of a moment that differs between two copies.
    static func mergeMoment(_ local: Moment, _ remote: Moment, base: Moment?) -> Moment {
        if local == remote { return local }
        guard let base else { return newer(local, remote) }
        if remote == base { return local }
        if local == base {
            // A remote copy older than what was last synced is a stale copy resurfacing, e.g. an
            // old conflict version, not a newer edit.
            return remote.updatedAt >= base.updatedAt ? remote : local
        }
        guard local.updatedAt >= base.updatedAt, remote.updatedAt >= base.updatedAt else {
            return newer(local, remote)
        }

        // Both sides edited the moment since the base. Start from the newer edit and add the
        // fields only the other side changed.
        let winner = newer(local, remote)
        let loser = winner == local ? remote : local
        var merged = winner
        func keepLoserChange<Value: Equatable>(_ field: WritableKeyPath<Moment, Value>) {
            if loser[keyPath: field] != base[keyPath: field], winner[keyPath: field] == base[keyPath: field] {
                merged[keyPath: field] = loser[keyPath: field]
            }
        }
        keepLoserChange(\.kind)
        keepLoserChange(\.name)
        keepLoserChange(\.emoji)
        keepLoserChange(\.imageData)
        keepLoserChange(\.colorHex)
        keepLoserChange(\.date)
        keepLoserChange(\.startDate)
        keepLoserChange(\.endDate)
        keepLoserChange(\.span)
        keepLoserChange(\.unit)
        keepLoserChange(\.repeatCycle)
        keepLoserChange(\.remindDays)
        keepLoserChange(\.inMenubar)
        keepLoserChange(\.sortWeight)
        keepLoserChange(\.createdAt)
        for key in Set(loser.extras.keys).union(winner.extras.keys).union(base.extras.keys)
        where loser.extras[key] != base.extras[key] && winner.extras[key] == base.extras[key] {
            merged.extras[key] = loser.extras[key]
        }
        return merged
    }

    /// The more recently updated of two versions. A tie is broken by content, so every Mac
    /// picks the same one.
    static func newer(_ a: Moment, _ b: Moment) -> Moment {
        if a.updatedAt != b.updatedAt {
            return a.updatedAt > b.updatedAt ? a : b
        }
        return a.canonicalData.lexicographicallyPrecedes(b.canonicalData) ? b : a
    }
}
