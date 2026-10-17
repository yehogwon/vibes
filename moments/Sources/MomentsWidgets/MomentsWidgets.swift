import AppIntents
import MomentsCore
import SwiftUI
import WidgetKit

// Two widgets: Moments lists the moments in the app's order, and Moment shows one, picked in the
// widget's settings, until it's deleted, when it lists them all instead. Both read the moments
// the app keeps on this Mac, and the app asks them to read again whenever the moments change.

@main
struct MomentsWidgets: WidgetBundle {
    var body: some Widget {
        MomentsWidget()
        MomentWidget()
    }
}

struct MomentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Moments", provider: ListProvider()) { entry in
            WidgetSize { MomentList(moments: entry.moments, now: entry.date, family: $0) }
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Moments")
        .description("Count down to the days that matter.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // The rows bring their own padding, as they do in the app's list.
        .contentMarginsDisabled()
    }
}

struct MomentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Moment", intent: ChooseMoment.self, provider: MomentProvider()) { entry in
            WidgetSize { family in
                if let moment = entry.moment {
                    MomentCard(moment: moment, now: entry.date, family: family)
                } else {
                    MomentList(moments: entry.moments, now: entry.date, family: family)
                }
            }
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Moment")
        .description("Count down to one day that matters.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct MomentsEntry: TimelineEntry {
    var date: Date
    /// In list order.
    var moments: [Moment]
    /// The one a Moment widget shows, or `nil` to list them all.
    var moment: Moment?
}

// MARK: - Timelines

struct ListProvider: TimelineProvider {
    func placeholder(in context: Context) -> MomentsEntry {
        MomentsEntry(date: .now, moments: Library.samples(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (MomentsEntry) -> Void) {
        completion(MomentsEntry(date: .now, moments: Library.moments(preview: context.isPreview)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MomentsEntry>) -> Void) {
        let moments = Library.moments()
        completion(Library.timeline { MomentsEntry(date: $0, moments: moments) })
    }
}

struct MomentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MomentsEntry {
        let samples = Library.samples(at: .now)
        return MomentsEntry(date: .now, moments: samples, moment: samples.first)
    }

    func snapshot(for configuration: ChooseMoment, in context: Context) async -> MomentsEntry {
        let moments = Library.moments(preview: context.isPreview)
        return MomentsEntry(date: .now, moments: moments, moment: chosen(configuration, in: moments))
    }

    func timeline(for configuration: ChooseMoment, in context: Context) async -> Timeline<MomentsEntry> {
        let moments = Library.moments()
        let moment = chosen(configuration, in: moments)
        return Library.timeline { MomentsEntry(date: $0, moments: moments, moment: moment) }
    }

    /// The moment picked in the widget's settings, or the first if none has been; `nil` once the
    /// picked one is deleted, so the widget lists the rest.
    private func chosen(_ configuration: ChooseMoment, in moments: [Moment]) -> Moment? {
        guard let id = configuration.moment?.id else { return moments.first }
        return moments.first { $0.id == id }
    }
}

enum Library {
    /// The moments in this Mac's library. Its entitlements let the widget read that folder.
    static func moments() -> [Moment] {
        let url = MomentStore.defaultFolder.appendingPathComponent("Library.json")
        return (try? JSONDecoder().decode(MomentLibrary.self, from: Data(contentsOf: url)))?.sortedMoments ?? []
    }

    /// The gallery shows the widget with moments in it, even before there are any.
    static func moments(preview: Bool) -> [Moment] {
        let moments = moments()
        return preview && moments.isEmpty ? samples(at: .now) : moments
    }

    /// The moments as they'll stand at each redraw. Counts move on at midnight and progress bars
    /// all day, so the widget redraws every quarter hour, and asks again two hours on.
    static func timeline(_ entry: (Date) -> MomentsEntry) -> Timeline<MomentsEntry> {
        Timeline(entries: Moment.widgetDates(from: .now).map(entry), policy: .atEnd)
    }

    static func samples(at now: Date) -> [Moment] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ days: Int, years: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(year: years, day: days), to: today) ?? today
        }
        return [
            Moment(name: "Trip to Jeju", emoji: "✈️", colorHex: "0A84FF", date: day(12), createdAt: now),
            Moment(kind: .life, name: "Mom", emoji: "🎂", colorHex: "FF375F", date: day(40, years: -58), createdAt: now),
            Moment(kind: .progress, colorHex: "32D74B", date: today, span: .year, createdAt: now),
        ]
    }
}

// MARK: - Settings

/// What a Moment widget shows, picked in its settings.
struct ChooseMoment: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Moment"

    @Parameter(title: "Moment")
    var moment: MomentEntity?
}

struct MomentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Moment"
    static let defaultQuery = MomentQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct MomentQuery: EntityQuery {
    /// A deleted moment is still found, by its id, so the widget can tell it was picked and then
    /// deleted, rather than never picked.
    func entities(for identifiers: [UUID]) async throws -> [MomentEntity] {
        let moments = Library.moments()
        return identifiers.map { id in
            MomentEntity(id: id, name: moments.first { $0.id == id }?.displayName ?? "Deleted Moment")
        }
    }

    func suggestedEntities() async throws -> [MomentEntity] {
        Library.moments().map { MomentEntity(id: $0.id, name: $0.displayName) }
    }
}
