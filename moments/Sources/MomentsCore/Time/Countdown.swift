import Foundation

/// Where a date or birthday moment stands on a given day.
public struct DayCount: Equatable, Sendable {
    /// Whole days from today to `target`: positive before it, 0 on the day, negative after.
    public var days: Int
    /// The day counted to: the moment's own day, or its next occurrence if it repeats.
    public var target: Date
    /// For a moment that repeats (birthdays always do), how many times its day has come round by
    /// `target`: the age turned on that birthday, or 5 for a fifth anniversary. `nil` otherwise.
    public var occurrence: Int?
}

extension Moment {
    /// Counts whole days, by the calendar, from `now`'s day to the moment's.
    public func dayCount(on now: Date, calendar: Calendar = .current) -> DayCount {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let step = kind == .life ? (component: Calendar.Component.year, value: 1) : repeatCycle.step
        guard let step, day < today else {
            return DayCount(days: calendar.days(from: today, to: day), target: day, occurrence: step.map { _ in 0 })
        }

        // The first occurrence on or after today. Each one is counted from the original day, so
        // a moment on the 31st lands on the last day of shorter months without drifting earlier.
        func occurrence(_ n: Int) -> Date {
            let date = calendar.date(byAdding: step.component, value: n * step.value, to: day) ?? day
            return calendar.startOfDay(for: date)
        }
        let elapsed =
            switch step.component {
            case .year: calendar.dateComponents([.year], from: day, to: today).year ?? 0
            case .month: calendar.dateComponents([.month], from: day, to: today).month ?? 0
            default: calendar.days(from: day, to: today) / step.value
            }
        var n = max(elapsed, 0)
        while occurrence(n) < today {
            n += 1
        }
        while n > 0, occurrence(n - 1) >= today {
            n -= 1
        }
        let target = occurrence(n)
        return DayCount(days: calendar.days(from: today, to: target), target: target, occurrence: n)
    }

    /// For a birthday: the age on `now`'s day.
    public func age(on now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let birthday = calendar.startOfDay(for: date)
        guard birthday < today else { return 0 }
        return calendar.dateComponents([.year], from: birthday, to: today).year ?? 0
    }
}

/// A length of time in calendar units, e.g. 2 months and 3 days.
public struct Breakdown: Equatable, Sendable, CustomStringConvertible {
    public var years = 0
    public var months = 0
    public var weeks = 0
    public var days = 0

    public init(years: Int = 0, months: Int = 0, weeks: Int = 0, days: Int = 0) {
        self.years = years
        self.months = months
        self.weeks = weeks
        self.days = days
    }

    /// The time between two days, in `unit` and the units below it: for `.month`, "14 months
    /// 3 days" rather than "1 year 2 months 3 days". The order of the days doesn't matter.
    public init(from a: Date, to b: Date, unit: Moment.Unit, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: min(a, b))
        let end = calendar.startOfDay(for: max(a, b))
        switch unit {
        case .year:
            let parts = calendar.dateComponents([.year, .month, .day], from: start, to: end)
            self.init(years: parts.year ?? 0, months: parts.month ?? 0, days: parts.day ?? 0)
        case .month:
            let parts = calendar.dateComponents([.month, .day], from: start, to: end)
            self.init(months: parts.month ?? 0, days: parts.day ?? 0)
        case .week:
            let days = calendar.days(from: start, to: end)
            self.init(weeks: days / 7, days: days % 7)
        default:
            self.init(days: calendar.days(from: start, to: end))
        }
    }

    /// "1 year 2 months 3 days", leaving out zeros; "0 days" for nothing.
    public var description: String {
        let parts = [(years, "year"), (months, "month"), (weeks, "week"), (days, "day")]
            .filter { $0.0 != 0 }
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return parts.isEmpty ? "0 days" : parts.joined(separator: " ")
    }
}

/// How a date or birthday moment reads on a given day.
public struct CountSummary: Equatable, Sendable {
    /// The big text: "D-12", "D-Day", "D+34", or an age.
    public var headline: String
    /// Under it: "12 days left", "Today", "1 month 3 days ago", "years old".
    public var caption: String
}

extension Moment {
    public func summary(on now: Date, calendar: Calendar = .current) -> CountSummary {
        if kind == .life {
            let age = age(on: now, calendar: calendar)
            return CountSummary(headline: "\(age)", caption: age == 1 ? "year old" : "years old")
        }
        let count = dayCount(on: now, calendar: calendar)
        let distance = Breakdown(from: now, to: count.target, unit: unit, calendar: calendar)
        return switch count.days {
        case 0: CountSummary(headline: "D-Day", caption: "Today")
        case 1...: CountSummary(headline: Self.dDay(count.days), caption: "\(distance) left")
        default: CountSummary(headline: Self.dDay(count.days), caption: "\(distance) ago")
        }
    }

    /// "D-12" twelve days before, "D-Day" on the day, "D+34" thirty-four days after.
    public static func dDay(_ days: Int) -> String {
        switch days {
        case 0: "D-Day"
        case 1...: "D-\(days)"
        default: "D+\(-days)"
        }
    }

    /// The number the list shows, to `decimals` places, rounded down so its whole part stays the
    /// list's: a progress bar's percent, a birthday's age and how far into the year since, or a
    /// day's count and the part of today left before it ("D-12.37500") or gone since it
    /// ("D+34.62500"). "D-Day" has no number to refine.
    public func preciseHeadline(
        at now: Date, decimals: Int, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        switch kind {
        case .progress:
            let style = FloatingPointFormatStyle<Double>.Percent(locale: locale)
            return progress(at: now, calendar: calendar).fraction.formatted(
                style.precision(.fractionLength(decimals)).rounded(rule: .down).grouping(.never))
        case .life:
            let age = age(on: now, calendar: calendar)
            let birthday = calendar.startOfDay(for: date)
            guard birthday < now, let last = calendar.date(byAdding: .year, value: age, to: birthday),
                let next = calendar.date(byAdding: .year, value: age + 1, to: birthday)
            else { return Self.decimal(Double(age), decimals, locale) }
            let year = DateInterval(start: calendar.startOfDay(for: last), end: calendar.startOfDay(for: next))
            return Self.decimal(Self.part(age, of: year, at: now), decimals, locale)
        default:
            let days = dayCount(on: now, calendar: calendar).days
            guard days != 0, let today = calendar.dateInterval(of: .day, for: now) else { return Self.dDay(days) }
            // Counting down, today's part is what's left of it; counting up, what's gone.
            let value =
                days > 0 ? Self.part(days, of: today, at: now, left: true) : Self.part(-days, of: today, at: now)
            return (days > 0 ? "D-" : "D+") + Self.decimal(value, decimals, locale)
        }
    }

    /// `whole` plus the part of `interval` gone (or left) at `now`, kept below `whole + 1`.
    private static func part(_ whole: Int, of interval: DateInterval, at now: Date, left: Bool = false) -> Double {
        let gone = interval.duration > 0 ? now.timeIntervalSince(interval.start) / interval.duration : 0
        let part = min(max(left ? 1 - gone : gone, 0), 1)
        return min(Double(whole) + part, Double(whole + 1).nextDown)
    }

    private static func decimal(_ value: Double, _ decimals: Int, _ locale: Locale) -> String {
        value.formatted(
            FloatingPointFormatStyle<Double>(locale: locale).precision(.fractionLength(decimals)).rounded(rule: .down)
                .grouping(.never))
    }
}

extension Calendar {
    /// Whole days between the starts of two days.
    func days(from a: Date, to b: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: a), to: startOfDay(for: b)).day ?? 0
    }
}
