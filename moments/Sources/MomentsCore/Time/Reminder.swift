import Foundation

extension Moment {
    /// When to remind about the moment next: at `hour` o'clock, `remindDays` before its day.
    /// For a repeating moment (birthdays always repeat), that's for the first occurrence whose
    /// reminder is still ahead.
    ///
    /// - Returns: When the reminder fires and the day it's about, or `nil` if there's nothing
    ///   left to remind about.
    public func nextReminder(after now: Date, hour: Int = 9, calendar: Calendar = .current) -> (
        fire: Date, day: Date
    )? {
        guard remindDays >= 0, kind != .progress,
            // No day before this one can have a reminder still to come.
            var earliest = calendar.date(byAdding: .day, value: remindDays, to: calendar.startOfDay(for: now))
        else { return nil }
        // The reminder for the day found first may already have fired today; then it's the next
        // occurrence's.
        for _ in 0..<2 {
            let count = dayCount(on: earliest, calendar: calendar)
            guard count.days >= 0,
                let reminderDay = calendar.date(byAdding: .day, value: -remindDays, to: count.target),
                let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: reminderDay)
            else { return nil }
            if fire > now {
                return (fire, count.target)
            }
            guard count.occurrence != nil, let next = calendar.date(byAdding: .day, value: 1, to: count.target) else {
                return nil
            }
            earliest = next
        }
        return nil
    }
}
