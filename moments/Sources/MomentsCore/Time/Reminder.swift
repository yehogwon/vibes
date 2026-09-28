import Foundation

extension Moment {
    /// When to remind about the moment next: at `hour` o'clock, `remindDays` before its day.
    /// For a repeating moment (birthdays always repeat) whose reminder for this time has passed,
    /// that's the reminder for next time.
    ///
    /// - Returns: When the reminder fires and the day it's about, or `nil` if there's nothing
    ///   left to remind about.
    public func nextReminder(after now: Date, hour: Int = 9, calendar: Calendar = .current) -> (
        fire: Date, day: Date
    )? {
        guard remindDays >= 0, kind != .progress else { return nil }
        var day = now
        for _ in 0..<2 {
            let count = dayCount(on: day, calendar: calendar)
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
            day = next
        }
        return nil
    }
}
