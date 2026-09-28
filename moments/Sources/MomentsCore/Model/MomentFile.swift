import Foundation

/// What `moments.json` holds: the moments, plus any entries that couldn't be read as one. Those
/// are kept and written back, so saving never deletes something just because this version
/// doesn't understand it.
public struct MomentList: Equatable, Sendable {
    public var moments: [Moment]
    public var unreadable: [JSONValue]

    public init(moments: [Moment] = [], unreadable: [JSONValue] = []) {
        self.moments = moments
        self.unreadable = unreadable
    }
}

/// Reads and writes the files in the sync folder.
///
/// `moments.json` is a JSON array of moments, pretty-printed with sorted keys, the way the
/// original Moment writes it. Deletions go in `deleted-moments.json` beside it, as a map from
/// each deleted moment's id to when it was deleted: without them, a moment deleted on one Mac
/// would come back from another that still has it.
public enum MomentFile {
    public static let name = "moments.json"
    public static let deletionsName = "deleted-moments.json"

    public static func encode(_ list: MomentList) throws -> Data {
        let entries = list.moments.sorted(by: Moment.listOrder).map(Entry.moment) + list.unreadable.map(Entry.raw)
        return try encoder.encode(entries)
    }

    /// An empty file reads as no moments. Anything but a JSON array is an error.
    public static func decode(_ data: Data) throws -> MomentList {
        guard !data.isEmpty else { return MomentList() }
        var list = MomentList()
        for entry in try JSONDecoder().decode([Entry].self, from: data) {
            switch entry {
            case .moment(let moment): list.moments.append(moment)
            case .raw(let value): list.unreadable.append(value)
            }
        }
        return list
    }

    public static func encodeDeletions(_ deleted: [UUID: Date]) throws -> Data {
        let strings = Dictionary(uniqueKeysWithValues: deleted.map { ($0.key.uuidString, ISODate.string($0.value)) })
        return try encoder.encode(strings)
    }

    /// Entries that can't be read are skipped: at worst a deleted moment comes back.
    public static func decodeDeletions(_ data: Data) throws -> [UUID: Date] {
        guard !data.isEmpty else { return [:] }
        let strings = try JSONDecoder().decode([String: String].self, from: data)
        var deleted: [UUID: Date] = [:]
        for (key, value) in strings {
            if let id = UUID(uuidString: key), let date = ISODate.parse(value) {
                deleted[id] = max(deleted[id] ?? date, date)
            }
        }
        return deleted
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private enum Entry: Codable {
        case moment(Moment)
        case raw(JSONValue)

        init(from decoder: Decoder) throws {
            if let moment = try? Moment(from: decoder) {
                self = .moment(moment)
            } else {
                self = .raw(try JSONValue(from: decoder))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .moment(let moment): try moment.encode(to: encoder)
            case .raw(let value): try value.encode(to: encoder)
            }
        }
    }
}

extension Moment {
    /// The list's order: by `sortWeight`, then oldest first, then by id so that every Mac lists
    /// moments with the same weight the same way.
    public static func listOrder(_ a: Moment, _ b: Moment) -> Bool {
        if a.sortWeight != b.sortWeight { return a.sortWeight < b.sortWeight }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    /// The moment as the file would store it, for comparing two versions byte by byte.
    var canonicalData: Data {
        (try? MomentFile.encoder.encode(self)) ?? Data()
    }
}
