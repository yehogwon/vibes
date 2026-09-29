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
    /// The first and last days of a custom progress span.
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
    /// When anything about the moment last changed.
    public var updatedAt: Date
    /// When each field last changed, for fields changed since the moment was created (see
    /// ``stamp(of:)``). It's what lets two Macs' edits to different fields of one moment both
    /// survive a sync. Written as `fieldUpdatedAt`, and only once a field has changed, so moments
    /// this app never edits stay exactly as the original app wrote them.
    public var fieldUpdatedAt: [String: Date] = [:]
    /// Keys from another app or a newer version, written back unchanged.
    public var extras: [String: JSONValue]
    /// Known keys whose value wasn't of the expected type, e.g. `"inMenubar" : 1`. They're
    /// written back as they were, rather than as the default that stood in for them, until the
    /// field is edited.
    var unparsed: [String: JSONValue] = [:]

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
        fieldUpdatedAt = fieldUpdatedAt.mapValues(\.wholeSeconds)
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
        "repeatCycle", "remindDays", "inMenubar", "sortWeight", "createdAt", "updatedAt", "fieldUpdatedAt",
    ]

    /// Reads a moment leniently, since the file may come from another app: a missing field
    /// falls back to a default, and one of an unexpected type is kept as it was (see
    /// `unparsed`). Only a missing `id` is an error.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var unparsed: [String: JSONValue] = [:]
        /// The value of `key` as `parse` reads it, or `nil` if it's missing or `parse` can't.
        func read<T>(_ key: String, _ parse: (JSONValue) -> T?) -> T? {
            guard container.contains(Key(key)) else { return nil }
            // `decodeIfPresent` would take null for a missing key.
            let raw = (try? container.decodeNil(forKey: Key(key))) == true
                ? JSONValue.null : (try? container.decode(JSONValue.self, forKey: Key(key)))
            guard let raw else { return nil }
            if let value = parse(raw) {
                return value
            }
            unparsed[key] = raw
            return nil
        }
        func string(_ key: String) -> String? {
            read(key) { if case .string(let value) = $0 { value } else { nil } }
        }
        func int(_ key: String) -> Int? {
            read(key) { raw in
                switch raw {
                case .integer(let value): Int(exactly: value)
                case .number(let value): Int(exactly: value)
                default: nil
                }
            }
        }
        func date(_ key: String) -> Date? {
            read(key) { raw in
                switch raw {
                case .string(let value): ISODate.parse(value)
                // JSONEncoder's default date strategy: seconds since 2001.
                case .number(let value): Date(timeIntervalSinceReferenceDate: value)
                case .integer(let value): Date(timeIntervalSinceReferenceDate: TimeInterval(value))
                default: nil
                }
            }
        }

        guard let id = string("id").flatMap(UUID.init(uuidString:)) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A moment has no valid id."))
        }
        // Missing dates fall back to fixed values, never to now, so every Mac reads the same file
        // the same way.
        let updatedAt = date("updatedAt")
        let createdAt = date("createdAt") ?? updatedAt ?? Date(timeIntervalSince1970: 0)
        // Anything but {"hex": "…"} is kept whole, so keys beside "hex" aren't lost.
        let hex = read("color") { raw -> String? in
            guard case .object(let object) = raw, object.count == 1, case .string(let hex)? = object["hex"] else {
                return nil
            }
            return hex
        }
        let colorHex: String =
            switch unparsed["color"] {
            case .object(let object)?: if case .string(let hex)? = object["hex"] { hex } else { "" }
            case .string(let hex)?: hex
            default: hex ?? ""
            }
        let fieldUpdatedAt = read("fieldUpdatedAt") { raw -> [String: Date]? in
            guard case .object(let object) = raw else { return nil }
            return object.reduce(into: [:]) { result, entry in
                if case .string(let value) = entry.value, let date = ISODate.parse(value) {
                    result[entry.key] = date
                }
            }
        }

        var extras: [String: JSONValue] = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            extras[key.stringValue] = try? container.decode(JSONValue.self, forKey: key)
        }

        self.init(
            id: id,
            kind: Kind(rawValue: string("kind") ?? Kind.date.rawValue),
            name: string("name") ?? "",
            emoji: string("emoji") ?? "",
            imageData: read("imageData") { if case .string(let value) = $0 { Data(base64Encoded: value) } else { nil } },
            colorHex: colorHex,
            date: date("date") ?? createdAt,
            startDate: date("startDate"),
            endDate: date("endDate"),
            span: Span(rawValue: string("span") ?? Span.year.rawValue),
            unit: Unit(rawValue: string("unit") ?? Unit.day.rawValue),
            repeatCycle: RepeatCycle(rawValue: string("repeatCycle") ?? RepeatCycle.none.rawValue),
            remindDays: int("remindDays") ?? -1,
            inMenubar: read("inMenubar") { if case .bool(let value) = $0 { value } else { nil } } ?? false,
            sortWeight: int("sortWeight") ?? 0,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            extras: extras)
        self.fieldUpdatedAt = (fieldUpdatedAt ?? [:]).mapValues(\.wholeSeconds)
        // The id and the timestamps are this app's to keep straight, so an odd one isn't kept.
        for key in ["id", "createdAt", "updatedAt", "fieldUpdatedAt"] {
            unparsed[key] = nil
        }
        self.unparsed = unparsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        /// Writes `value`, or what the file had if that couldn't be read.
        func put<T: Encodable>(_ key: String, _ value: T) throws {
            if let raw = unparsed[key] {
                try container.encode(raw, forKey: Key(key))
            } else {
                try container.encode(value, forKey: Key(key))
            }
        }
        for (key, value) in extras {
            try container.encode(value, forKey: Key(key))
        }
        try put("color", ["hex": colorHex])
        try container.encode(ISODate.string(createdAt), forKey: "createdAt")
        try put("date", ISODate.string(date))
        try put("emoji", emoji)
        try put("endDate", ISODate.string(endDate))
        if !fieldUpdatedAt.isEmpty {
            try container.encode(fieldUpdatedAt.mapValues(ISODate.string), forKey: "fieldUpdatedAt")
        }
        try container.encode(id.uuidString, forKey: "id")
        if let imageData {
            try put("imageData", imageData.base64EncodedString())
        } else if let raw = unparsed["imageData"] {
            try container.encode(raw, forKey: "imageData")
        }
        try put("inMenubar", inMenubar)
        try put("kind", kind.rawValue)
        try put("name", name)
        try put("remindDays", remindDays)
        try put("repeatCycle", repeatCycle.rawValue)
        try put("sortWeight", sortWeight)
        try put("span", span.rawValue)
        try put("startDate", ISODate.string(startDate))
        try put("unit", unit.rawValue)
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
