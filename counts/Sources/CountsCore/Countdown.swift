import Foundation

/// One timer: how long it was set for, and when it ends.
///
/// A timer never changes once it starts, so two Macs can only disagree about whether it's still
/// there (see ``TimerList/merge(_:_:)``).
public struct Countdown: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// How long it was set for, in seconds.
    public var duration: Int
    /// When it ends. The file keeps it in UTC, to the second ("2026-10-04T06:25:00Z").
    public var endsAt: Date

    public init(id: UUID = UUID(), duration: Int, endsAt: Date) {
        self.id = id
        self.duration = duration
        // The file keeps whole seconds, so a timer is the same after a round trip through it.
        self.endsAt = endsAt.wholeSeconds
    }

    /// A timer of `duration` seconds that starts at `now`.
    public init(duration: Int, startingAt now: Date) {
        self.init(duration: duration, endsAt: now.addingTimeInterval(TimeInterval(duration)))
    }

    public func hasEnded(at now: Date) -> Bool {
        now >= endsAt
    }

    /// Whole seconds left, rounded up, so it reads 0 only once the timer has ended.
    public func secondsLeft(at now: Date) -> Int {
        max(Int(endsAt.timeIntervalSince(now).rounded(.up)), 0)
    }

    /// How much of it is left, from 1 when it starts to 0 when it ends.
    public func fractionLeft(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(endsAt.timeIntervalSince(now) / Double(duration), 0), 1)
    }

    /// What it reads at `now`: "4:59", "1:05:00", or "Done".
    public func clock(at now: Date) -> String {
        hasEnded(at: now) ? "Done" : Self.clock(secondsLeft(at: now))
    }

    /// "0:05", "4:59", "1:05:00".
    public static func clock(_ total: Int) -> String {
        let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }

    /// How long it was set for, in words: "25 min", "1 hr, 30 min".
    public var durationText: String {
        Self.durationText(duration)
    }

    public static func durationText(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    /// The list's order: the one that ends (or ended) first, first. Ties go by id, so every Mac
    /// lists them the same way.
    public static func order(_ a: Countdown, _ b: Countdown) -> Bool {
        (a.endsAt, a.id.uuidString) < (b.endsAt, b.id.uuidString)
    }
}

extension Date {
    /// This date without its fraction of a second.
    public var wholeSeconds: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
