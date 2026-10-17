import CountsCore
import SwiftUI
import WidgetKit

// The Timers widget: every timer as a ring that drains as it runs, like the Batteries widget. A
// lone timer gets the whole widget. It reads the timers the app keeps on this Mac, and the app
// asks it to read them again whenever they change.

@main
struct CountsWidgets: WidgetBundle {
    var body: some Widget {
        TimersWidget()
    }
}

struct TimersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Timers", provider: TimersProvider()) { entry in
            WidgetSize { TimersView(entry: entry, family: $0) }
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Timers")
        .description("See how long your timers have left.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TimersEntry: TimelineEntry {
    var date: Date
    /// In list order: the one that ends first, first.
    var timers: [Countdown]
}

struct TimersProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimersEntry {
        TimersEntry(date: .now, timers: Self.samples(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (TimersEntry) -> Void) {
        let timers = Self.timers()
        // The gallery shows the widget with timers running, even before there are any.
        completion(TimersEntry(date: .now, timers: context.isPreview && timers.isEmpty ? Self.samples(at: .now) : timers))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimersEntry>) -> Void) {
        let now = Date.now
        let timers = Self.timers()
        let schedule = Countdown.widgetSchedule(for: timers, from: now)
        completion(
            Timeline(
                entries: schedule.dates.map { TimersEntry(date: $0, timers: timers) },
                policy: schedule.next.map { .after($0) } ?? .never))
    }

    /// The timers in this Mac's library. Its entitlements let the widget read that folder.
    static func timers() -> [Countdown] {
        let url = TimerStore.defaultFolder.appendingPathComponent("Library.json")
        return (try? TimerFile.decode(Data(contentsOf: url)))?.sorted ?? []
    }

    static func samples(at now: Date) -> [Countdown] {
        [
            Countdown(duration: 5 * 60, endsAt: now.addingTimeInterval(3 * 60 + 5)),
            Countdown(duration: 25 * 60, endsAt: now.addingTimeInterval(18 * 60 + 42)),
        ]
    }
}

// MARK: - Views

/// Hands a widget's size to its view, which takes it as is so it can be drawn at each size outside
/// a widget too.
struct WidgetSize<Content: View>: View {
    @ViewBuilder var content: (WidgetFamily) -> Content
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content(family)
    }
}

struct TimersView: View {
    var entry: TimersEntry
    var family: WidgetFamily

    var body: some View {
        if let timer = entry.timers.first, entry.timers.count == 1 {
            lone(timer)
        } else if entry.timers.isEmpty {
            empty
        } else {
            // ponytail: up to four, the ones that end first, as the Batteries widget shows; the
            // rest wait their turn.
            grid(Array(entry.timers.prefix(4)))
        }
    }

    /// One timer, as large as the widget allows.
    private func lone(_ timer: Countdown) -> some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(spacing: 8) {
                    Dial(timer: timer, now: entry.date, diameter: 100, fontSize: 24)
                    Text("\(timer.durationText) · \(timer.endText(at: entry.date))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            case .systemMedium:
                HStack(spacing: 20) {
                    Dial(timer: timer, now: entry.date, diameter: 124, fontSize: 30)
                    details(timer)
                }
            default:
                VStack(spacing: 16) {
                    Dial(timer: timer, now: entry.date, diameter: 220, fontSize: 44)
                    details(timer, alignment: .center)
                }
            }
        }
        // VoiceOver reads a timer as one: what's left, then how long it was and when it ends.
        .accessibilityElement(children: .combine)
    }

    private func details(_ timer: Countdown, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(timer.durationText)
                .font(.headline)
            Text(timer.endText(at: entry.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Up to four timers: two by two, or side by side in the wide widget. The rings are the same
    /// size however many there are.
    private func grid(_ timers: [Countdown]) -> some View {
        let columns = family == .systemMedium ? timers.count : 2
        let (diameter, fontSize): (CGFloat, CGFloat) =
            switch family {
            case .systemSmall: (62, 13)
            case .systemMedium: (64, 13)
            default: (116, 22)
            }
        return Grid(horizontalSpacing: 12, verticalSpacing: family == .systemSmall ? 12 : 16) {
            ForEach(Array(stride(from: 0, to: timers.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(timers[start..<min(start + columns, timers.count)]) {
                        cell($0, diameter: diameter, fontSize: fontSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cell(_ timer: Countdown, diameter: CGFloat, fontSize: CGFloat) -> some View {
        VStack(spacing: 6) {
            Dial(timer: timer, now: entry.date, diameter: diameter, fontSize: fontSize)
            if family != .systemSmall {
                Text(family == .systemMedium ? timer.durationText : "\(timer.durationText) · \(timer.endText(at: entry.date))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: family == .systemSmall ? nil : .infinity)
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Click to start a timer.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// A timer's ring, draining as it runs, with what's left counting down inside.
struct Dial: View {
    var timer: Countdown
    var now: Date
    var diameter: CGFloat
    var fontSize: CGFloat

    var body: some View {
        let lineWidth = max(diameter / 14, 4)
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: timer.fractionLeft(at: now))
                .stroke(.secondary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            clock
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .lineLimit(1)
                // "1:05:00" is the widest; it shrinks to fit, but no smaller than 11 pt.
                .minimumScaleFactor(min(11 / fontSize, 1))
                .padding(.horizontal, lineWidth)
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
    }

    /// "4:59", "1:05:00", or "Done". The system counts it down between the widget's redraws.
    @ViewBuilder
    private var clock: some View {
        if timer.hasEnded(at: now) {
            Text("Done")
        } else {
            Text(timerInterval: now...timer.endsAt, countsDown: true)
        }
    }
}
