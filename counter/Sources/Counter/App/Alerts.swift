import CounterCore
import Foundation
import UserNotifications

/// Schedules a notification, with a sound, for when each timer ends.
@MainActor
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    /// The ids of the timers alerts were scheduled for.
    private var scheduled: Set<String> = []
    private var askedForPermission = false

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Ones left from the last launch may be for timers removed since; `update` adds back the
        // rest.
        center.removeAllPendingNotificationRequests()
    }

    func update(_ timers: [Countdown], now: Date) {
        let ids = Set(timers.map(\.id.uuidString))
        guard ids != scheduled else { return }
        let center = UNUserNotificationCenter.current()
        // A removed timer takes its alert with it, sent or not. One that just ended stays in
        // `ids`, so its alert isn't withdrawn as it goes off.
        let removed = Array(scheduled.subtracting(ids))
        center.removePendingNotificationRequests(withIdentifiers: removed)
        center.removeDeliveredNotifications(withIdentifiers: removed)
        for timer in timers where !scheduled.contains(timer.id.uuidString) && !timer.hasEnded(at: now) {
            if !askedForPermission {
                askedForPermission = true
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
            let content = UNMutableNotificationContent()
            content.title = "Time’s Up"
            let duration = Duration.seconds(timer.duration).formatted(
                .units(allowed: [.hours, .minutes, .seconds], width: .wide))
            content.body = "The timer you set for \(duration) has ended."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(timer.endsAt.timeIntervalSince(now), 0.1), repeats: false)
            center.add(UNNotificationRequest(identifier: timer.id.uuidString, content: content, trigger: trigger))
        }
        scheduled = ids
    }

    /// Shows the alert even while Counter's panel is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
