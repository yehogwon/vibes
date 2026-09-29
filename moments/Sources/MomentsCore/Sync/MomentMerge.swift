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
        // Two entries with one id can only come from a mangled file; combine them.
        let moments = Dictionary(list.moments.map { ($0.id, $0) }, uniquingKeysWith: Moment.merged)
        self.init(moments: moments, deleted: deleted, unreadable: list.unreadable)
    }

    public var list: MomentList {
        MomentList(moments: Array(moments.values), unreadable: unreadable)
    }
}

/// Combines copies of the moments, e.g. this Mac's and the one in iCloud Drive.
///
/// Nothing is lost when several Macs changed things while apart:
/// - Moments added anywhere are kept.
/// - A moment changed in several places keeps, field by field, the change made last (see
///   ``Moment/stamp(of:)``), so edits to different fields all survive.
/// - A deletion wins over edits made before it; an edit made after it brings the moment back.
///   A moment missing from a copy is never taken as deleted; only a recorded deletion is.
///
/// Neither the order of the copies nor how they're grouped changes the result, so every Mac
/// settles on the same moments however their changes reach each other.
public enum MomentMerge {
    public static func merge(_ a: MomentSet, _ b: MomentSet) -> MomentSet {
        var deleted = a.deleted
        deleted.merge(b.deleted, uniquingKeysWith: max)

        var moments: [UUID: Moment] = [:]
        for id in Set(a.moments.keys).union(b.moments.keys) {
            let merged: Moment
            switch (a.moments[id], b.moments[id]) {
            case (let a?, let b?): merged = Moment.merged(a, b)
            case (let a?, nil): merged = a
            case (nil, let b?): merged = b
            case (nil, nil): continue
            }
            if let deletedAt = deleted[id], merged.updatedAt <= deletedAt {
                continue
            }
            moments[id] = merged
        }

        var unreadable = b.unreadable
        for value in a.unreadable where !unreadable.contains(value) {
            unreadable.append(value)
        }
        return MomentSet(moments: moments, deleted: deleted, unreadable: unreadable)
    }
}
