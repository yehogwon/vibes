import Foundation

/// One entry in the list: a day to count down to or up from, a birthday to count an age from, or
/// a span of time to show progress through.
///
/// The fields and their JSON form follow the `moments.json` the original Moment keeps in iCloud
/// Drive, so both read the same file. Keys this version doesn't know are kept in `extras` and
/// written back unchanged.
public struct Moment: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: Kind
    public var name: String
    /// Shown in place of an icon; empty for none.
    public var emoji: String
    /// A photo shown in place of the emoji, as PNG.
    public var imageData: Data?
    /// `RRGGBB`, or empty for the default color.
    public var colorHex: String
    /// The day a date or birthday is about. Stored as the instant that day starts where it was
    /// picked, like the original app does.
    public var date: Date
    /// Where a custom progress span starts and ends.
    public var startDate: Date
    public var endDate: Date
    /// What a progress moment shows progress through.
    public var span: Span
    /// The largest unit a count is broken down into, e.g. "2 months 3 days".
    public var unit: Unit
    public var repeatCycle: RepeatCycle
    /// How many days ahead to send a reminder, or -1 for none.
    public var remindDays: Int
    /// Also shown as its own item in the menu bar.
    public var inMenubar: Bool
    /// Position in the list, smallest first.
    public var sortWeight: Int
    public var createdAt: Date
    /// When anything about the moment last changed. Syncing uses it to tell which of two versions
    /// is newer.
    public var updatedAt: Date
    /// Keys from another app or a newer version, written back unchanged.
    public var extras: [String: JSONValue]

    public init(
        id: UUID = UUID(),
        kind: Kind = .date,
        name: String = "",
        emoji: String = "",
        imageData: Data? = nil,
        colorHex: String = "",
        date: Date,
        startDate: Date? = nil,
        endDate: Date? = nil,
        span: Span = .year,
        unit: Unit = .day,
        repeatCycle: RepeatCycle = .none,
        remindDays: Int = -1,
        inMenubar: Bool = false,
        sortWeight: Int = 0,
        createdAt: Date,
        updatedAt: Date? = nil,
        extras: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.emoji = emoji
        self.imageData = imageData
        self.colorHex = colorHex
        self.date = date
        self.startDate = startDate ?? date
        self.endDate = endDate ?? date
        self.span = span
        self.unit = unit
        self.repeatCycle = repeatCycle
        self.remindDays = remindDays
        self.inMenubar = inMenubar
        self.sortWeight = sortWeight
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.extras = extras
        normalizeDates()
    }

    /// The file keeps whole seconds, so dates are rounded down to them. Otherwise a moment would
    /// differ from itself after a round trip through the file.
    public mutating func normalizeDates() {
        date = date.wholeSeconds
        startDate = startDate.wholeSeconds
        endDate = endDate.wholeSeconds
        createdAt = createdAt.wholeSeconds
        updatedAt = updatedAt.wholeSeconds
    }

    /// Whether everything but `updatedAt` matches, i.e. saving `other` over this changes nothing.
    public func hasSameContent(as other: Moment) -> Bool {
        var other = other
        other.updatedAt = updatedAt
        return self == other
    }
}

// MARK: - Kinds and options

extension Moment {
    // These keep the string from the file, so a value from a newer version survives a round trip.

    public struct Kind: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// A day to count down to or up from.
        public static let date = Kind(rawValue: "date")
        /// Someone's age, counted from their birthday.
        public static let life = Kind(rawValue: "life")
        /// How far along a span of time is.
        public static let progress = Kind(rawValue: "progress")
    }

    public struct Span: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let day = Span(rawValue: "day")
        public static let week = Span(rawValue: "week")
        public static let month = Span(rawValue: "month")
        public static let quarter = Span(rawValue: "quarter")
        public static let year = Span(rawValue: "year")
        /// From `startDate` to `endDate`.
        public static let custom = Span(rawValue: "custom")

        public static let allCases: [Span] = [.day, .week, .month, .quarter, .year, .custom]
    }

    public struct Unit: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let day = Unit(rawValue: "day")
        public static let week = Unit(rawValue: "week")
        public static let month = Unit(rawValue: "month")
        public static let year = Unit(rawValue: "year")

        public static let allCases: [Unit] = [.day, .week, .month, .year]
    }

    public struct RepeatCycle: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let none = RepeatCycle(rawValue: "none")
        public static let week = RepeatCycle(rawValue: "week")
        public static let month = RepeatCycle(rawValue: "month")
        public static let year = RepeatCycle(rawValue: "year")

        public static let allCases: [RepeatCycle] = [.none, .week, .month, .year]

        /// The calendar step between occurrences, or `nil` if the moment doesn't repeat.
        /// Accepts the "-ly" spellings too, in case another app writes them.
        public var step: (component: Calendar.Component, value: Int)? {
            switch rawValue {
            case "week", "weekly": (.day, 7)
            case "month", "monthly": (.month, 1)
            case "year", "yearly", "annually": (.year, 1)
            default: nil
            }
        }
    }
}

// MARK: - Coding

extension Moment: Codable {
    private struct Key: CodingKey, ExpressibleByStringLiteral {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init(stringLiteral value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static let knownKeys: Set<String> = [
        "id", "kind", "name", "emoji", "imageData", "color", "date", "startDate", "endDate", "span", "unit",
        "repeatCycle", "remindDays", "inMenubar", "sortWeight", "createdAt", "updatedAt",
    ]

    /// Reads a moment leniently: a missing or odd field falls back to a default instead of
    /// failing, since the file may come from another app. Only a missing `id` is an error.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
            try? container.decodeIfPresent(type, forKey: Key(key))
        }
        func int(_ key: String) -> Int? {
            decode(Int.self, key) ?? decode(Double.self, key).map { Int($0) }
        }
        func date(_ key: String) -> Date? {
            if let string = decode(String.self, key) {
                return ISODate.parse(string)
            }
            // JSONEncoder's default date strategy: seconds since 2001.
            return decode(Double.self, key).map(Date.init(timeIntervalSinceReferenceDate:))
        }

        guard let id = decode(String.self, "id").flatMap(UUID.init(uuidString:)) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A moment has no valid id."))
        }
        // Missing dates fall back to fixed values, never to now, so every Mac reads the same file
        // the same way.
        let updatedAt = date("updatedAt")
        let createdAt = date("createdAt") ?? updatedAt ?? Date(timeIntervalSince1970: 0)
        let day = date("date") ?? createdAt
        let color: String =
            if let object = decode([String: JSONValue].self, "color"), case .string(let hex)? = object["hex"] {
                hex
            } else {
                decode(String.self, "color") ?? ""
            }

        var extras: [String: JSONValue] = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            extras[key.stringValue] = try? container.decode(JSONValue.self, forKey: key)
        }

        self.init(
            id: id,
            kind: Kind(rawValue: decode(String.self, "kind") ?? Kind.date.rawValue),
            name: decode(String.self, "name") ?? "",
            emoji: decode(String.self, "emoji") ?? "",
            imageData: decode(String.self, "imageData").flatMap { Data(base64Encoded: $0) },
            colorHex: color,
            date: day,
            startDate: date("startDate"),
            endDate: date("endDate"),
            span: Span(rawValue: decode(String.self, "span") ?? Span.year.rawValue),
            unit: Unit(rawValue: decode(String.self, "unit") ?? Unit.day.rawValue),
            repeatCycle: RepeatCycle(rawValue: decode(String.self, "repeatCycle") ?? RepeatCycle.none.rawValue),
            remindDays: int("remindDays") ?? -1,
            inMenubar: decode(Bool.self, "inMenubar") ?? false,
            sortWeight: int("sortWeight") ?? 0,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            extras: extras)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in extras {
            try container.encode(value, forKey: Key(key))
        }
        try container.encode(["hex": colorHex], forKey: "color")
        try container.encode(ISODate.string(createdAt), forKey: "createdAt")
        try container.encode(ISODate.string(date), forKey: "date")
        try container.encode(emoji, forKey: "emoji")
        try container.encode(ISODate.string(endDate), forKey: "endDate")
        try container.encode(id.uuidString, forKey: "id")
        if let imageData {
            try container.encode(imageData.base64EncodedString(), forKey: "imageData")
        }
        try container.encode(inMenubar, forKey: "inMenubar")
        try container.encode(kind.rawValue, forKey: "kind")
        try container.encode(name, forKey: "name")
        try container.encode(remindDays, forKey: "remindDays")
        try container.encode(repeatCycle.rawValue, forKey: "repeatCycle")
        try container.encode(sortWeight, forKey: "sortWeight")
        try container.encode(span.rawValue, forKey: "span")
        try container.encode(ISODate.string(startDate), forKey: "startDate")
        try container.encode(unit.rawValue, forKey: "unit")
        try container.encode(ISODate.string(updatedAt), forKey: "updatedAt")
    }
}

// MARK: - Dates in the file

/// Dates as the file writes them: ISO 8601 in UTC, to the second ("2026-08-24T04:23:26Z").
public enum ISODate {
    public static func string(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// Also accepts fractional seconds, which some writers add; they're dropped.
    public static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601) {
            return date
        }
        return (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))?.wholeSeconds
    }
}

extension Date {
    /// This date without its fraction of a second.
    public var wholeSeconds: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970).rounded(.down))
    }
}
