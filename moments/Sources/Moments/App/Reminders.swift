import Foundation
import MomentsCore
import UserNotifications

/// Schedules a notification for each moment with a reminder, `remindDays` before its next day,
/// at 9 in the morning.
@MainActor
final class Reminders {
    private var scheduled: [String: Date] = [:]
    private var askedForPermission = false

    func update(_ moments: [Moment], now: Date, calendar: Calendar = .current) {
        var wanted: [String: (moment: Moment, fire: Date, day: Date)] = [:]
        for moment in moments {
            if let reminder = moment.nextReminder(after: now, calendar: calendar) {
                wanted[moment.id.uuidString] = (moment, reminder.fire, reminder.day)
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
            let day = reminder.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
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
}
