import Foundation

/// How far along a progress moment's span is at some instant.
public struct SpanProgress: Equatable, Sendable {
    public var interval: DateInterval
    /// From 0 at the start to 1 at the end.
    public var fraction: Double
    /// "Day 272 of 365", "9h 24m left", "Starts in 3 days", "Ended".
    public var detail: String

    /// "74%", rounded down so it doesn't read 100% before the end.
    public var percent: String {
        "\(Int((fraction * 100).rounded(.down)))%"
    }
}

extension Moment {
    /// The stretch of time a progress moment covers at `now`, e.g. this week.
    public func progressInterval(at now: Date, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component
        switch span {
        case .custom:
            return DateInterval(start: min(startDate, endDate), end: max(startDate, endDate))
        case .quarter:
            // Calendar's own quarter support is unreliable, so count three months from the
            // quarter's first month.
            let parts = calendar.dateComponents([.year, .month], from: now)
            let firstMonth = ((parts.month ?? 1) - 1) / 3 * 3 + 1
            let start = calendar.date(from: DateComponents(year: parts.year, month: firstMonth, day: 1)) ?? now
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        default: component = .year
        }
        return calendar.dateInterval(of: component, for: now) ?? DateInterval(start: now, duration: 0)
    }

    public func progress(at now: Date, calendar: Calendar = .current) -> SpanProgress {
        let interval = progressInterval(at: now, calendar: calendar)
        let fraction =
            interval.duration > 0 ? min(max(now.timeIntervalSince(interval.start) / interval.duration, 0), 1) : 1
        let detail: String
        if now < interval.start {
            let days = calendar.days(from: now, to: interval.start)
            detail = days == 0 ? "Starts today" : "Starts in \(days) day\(days == 1 ? "" : "s")"
        } else if now >= interval.end {
            detail = "Ended"
        } else if span == .day {
            let minutes = Int(interval.end.timeIntervalSince(now) / 60)
            detail = "\(minutes / 60)h \(minutes % 60)m left"
        } else {
            // A span ending at midnight doesn't include the day that midnight starts.
            let lastDay = interval.end.addingTimeInterval(-1)
            let total = calendar.days(from: interval.start, to: lastDay) + 1
            let day = calendar.days(from: interval.start, to: now) + 1
            detail = "Day \(day) of \(total)"
        }
        return SpanProgress(interval: interval, fraction: fraction, detail: detail)
    }

    /// The name to show: the moment's own, or one that says what a progress bar measures.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch kind {
        case .progress:
            return switch span {
            case .day: "Today"
            case .week: "This Week"
            case .month: "This Month"
            case .quarter: "This Quarter"
            case .year: "This Year"
            default: "Progress"
            }
        case .life: return "Birthday"
        default: return "Untitled"
        }
    }
}
