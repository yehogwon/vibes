import Foundation
import MomentsCore
import UserNotifications

/// Schedules a notification for each moment with a reminder, `remindDays` before its next day,
/// at 9 in the morning.
@MainActor
final class Reminders {
    static let hour = 9

    private var scheduled: [String: Date] = [:]
    private var askedForPermission = false

    func update(_ moments: [Moment], now: Date, calendar: Calendar = .current) {
        var wanted: [String: (moment: Moment, fire: Date, target: Date)] = [:]
        for moment in moments where moment.remindDays >= 0 && moment.kind != .progress {
            if let (fire, target) = Self.nextReminder(for: moment, after: now, calendar: calendar) {
                wanted[moment.id.uuidString] = (moment, fire, target)
            }
        }
        let fireDates = wanted.mapValues(\.fire)
        guard fireDates != scheduled else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Array(scheduled.keys))
        scheduled = fireDates
        guard !wanted.isEmpty else { return }
        if !askedForPermission {
            askedForPermission = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        for (id, reminder) in wanted {
            let content = UNMutableNotificationContent()
            content.title = [reminder.moment.emoji, reminder.moment.displayName].filter { !$0.isEmpty }
                .joined(separator: " ")
            let day = reminder.target.formatted(.dateTime.weekday(.wide).month(.wide).day())
            content.body =
                switch reminder.moment.remindDays {
                case 0: "Today, \(day)"
                case 1: "Tomorrow, \(day)"
                default: "In \(reminder.moment.remindDays) days, on \(day)"
                }
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fire),
                repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// When to remind about `moment` next, and the day the reminder is for. For a repeating
    /// moment whose reminder for this time has passed, that's the one for next time.
    static func nextReminder(for moment: Moment, after now: Date, calendar: Calendar) -> (Date, Date)? {
        var day = now
        for _ in 0..<2 {
            let count = moment.dayCount(on: day, calendar: calendar)
            guard count.days >= 0,
                let reminderDay = calendar.date(byAdding: .day, value: -moment.remindDays, to: count.target),
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
