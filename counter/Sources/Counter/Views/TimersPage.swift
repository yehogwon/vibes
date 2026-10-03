import CounterCore
import SwiftUI

/// The timers, the one that ends first at the top. A lone timer shows larger.
struct TimersPage: View {
    @Environment(AppState.self) private var app
    /// The list's natural height, so the scroll view can be exactly as tall as its rows up to a
    /// limit, and the panel only as tall as it needs to be.
    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 420

    var body: some View {
        let timers = app.store.timers
        VStack(spacing: 0) {
            PageHeader(title: timers.count == 1 ? "Timer" : "Timers") {
                EmptyView()
            } trailing: {
                addButton
            }
            Banners()
            if timers.count == 1, let timer = timers.first {
                TimerRow(timer: timer, now: app.now, isLarge: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(timers) { TimerRow(timer: $0, now: app.now) }
                    }
                    .padding(.horizontal, 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: min(max(listHeight, 1), Self.maxListHeight))
                .padding(.bottom, 4)
            }
            Footer()
        }
    }

    private var addButton: some View {
        Button { app.route = .newTimer } label: {
            IconLabel(title: "New Timer", systemImage: "plus")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.plain)
        .help("Start a timer (⌘N)")
        // The symbol, not its hit area, lines up with the panel's edge inset.
        .padding(.trailing, -4)
    }
}

/// One timer: what's left, how long it was set for, and when it ends.
struct TimerRow: View {
    @Environment(AppState.self) private var app
    let timer: Countdown
    let now: Date
    var isLarge = false

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 8 : 0) {
            HStack(spacing: 8) {
                Text(timer.clock(at: now))
                    .font(
                        isLarge
                            ? .system(size: 44, weight: .semibold, design: .rounded)
                            : .system(.title2, design: .rounded, weight: .semibold)
                    )
                    .monospacedDigit()
                    .accessibilityLabel(spokenClock)
                Spacer(minLength: 8)
                Button { app.remove(timer) } label: {
                    IconLabel(title: "Remove Timer", systemImage: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this timer")
            }
            if isLarge {
                ProgressBar(fraction: timer.fractionLeft(at: now))
                    .frame(height: 4)
            }
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove Timer", role: .destructive) { app.remove(timer) }
        }
    }

    /// "25 min · Ends 3:45 PM", with the day when it isn't today.
    private var caption: String {
        let time = timer.endsAt.formatted(
            Calendar.current.isDate(timer.endsAt, inSameDayAs: now)
                ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
        return "\(timer.durationText) · \(timer.hasEnded(at: now) ? "Ended" : "Ends") \(time)"
    }

    /// "4 minutes, 59 seconds left", since VoiceOver would read "4:59" as a time of day.
    private var spokenClock: String {
        guard !timer.hasEnded(at: now) else { return "Done" }
        let left = Duration.seconds(timer.secondsLeft(at: now)).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return "\(left) left"
    }
}

/// How much of a timer is left, draining from full to empty.
struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.secondary)
                    .frame(width: max(geometry.size.height, geometry.size.width * fraction))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}
