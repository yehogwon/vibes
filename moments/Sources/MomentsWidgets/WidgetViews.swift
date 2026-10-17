import MomentsCore
import MomentsUI
import SwiftUI
import WidgetKit

/// Hands a widget's size to its view, which takes it as is so it can be drawn at each size outside
/// a widget too.
struct WidgetSize<Content: View>: View {
    @ViewBuilder var content: (WidgetFamily) -> Content
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content(family)
    }
}

/// The moments in the app's order, as many as fit: the app's own rows, or in the small widget,
/// each moment's name over its count. A lone moment gets the whole widget.
struct MomentList: View {
    var moments: [Moment]
    var now: Date
    var family: WidgetFamily

    var body: some View {
        if moments.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Click to add a moment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        } else if let moment = moments.first, moments.count == 1 {
            // A list of one would leave most of the widget empty.
            MomentCard(moment: moment, now: now, family: family)
        } else if family == .systemSmall {
            fitting(spacing: 8) { CompactRow(moment: $0, now: now) }
                .padding(16)
        } else {
            // The rows' own inset brings their content to the 16 pt edge, as in the app.
            fitting(spacing: 2) { MomentRow(moment: $0, now: now) }
                .padding(8)
        }
    }

    /// As many rows as fit, from the top of the list.
    private func fitting(spacing: CGFloat, @ViewBuilder row: @escaping (Moment) -> some View) -> some View {
        ViewThatFits(in: .vertical) {
            ForEach((1...min(moments.count, 10)).reversed(), id: \.self) { count in
                VStack(spacing: spacing) {
                    ForEach(moments.prefix(count)) { moment in
                        row(moment)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A moment in the small list: its name over its count.
struct CompactRow: View {
    var moment: Moment
    var now: Date

    var body: some View {
        HStack(spacing: 8) {
            AvatarView(moment: moment, now: now, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(moment.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(moment.kind == .progress ? moment.progress(at: now).percent : moment.summary(on: now).headline)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(moment.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// One moment, as large as the widget allows: its count, what it is, and when.
struct MomentCard: View {
    var moment: Moment
    var now: Date
    var family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            AvatarView(moment: moment, now: now, size: 36)
            Spacer(minLength: 4)
            number(size: 34)
            bar
            name(.callout.weight(.medium))
            secondary(caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    AvatarView(moment: moment, now: now, size: 40)
                    Spacer(minLength: 4)
                    name(.headline)
                    secondary(subtitle ?? caption)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    number(size: 48)
                    if subtitle != nil {
                        secondary(caption)
                    }
                }
            }
            bar
        }
    }

    private var large: some View {
        VStack(spacing: 4) {
            AvatarView(moment: moment, now: now, size: 64)
            name(.title3.weight(.semibold))
                .padding(.top, 4)
            Spacer(minLength: 8)
            number(size: 72)
            secondary(caption)
            bar
                .padding(.horizontal, 24)
                .padding(.top, 8)
            Spacer(minLength: 8)
            if let subtitle {
                secondary(subtitle)
            }
        }
    }

    // MARK: - Parts

    private var isProgress: Bool { moment.kind == .progress }

    /// The count, or how far along a progress bar is: "D-12", "34", "74%".
    private func number(size: CGFloat) -> some View {
        Text(isProgress ? moment.progress(at: now).percent : moment.summary(on: now).headline)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(moment.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// "12 days left", "years old", "Day 272 of 365".
    private var caption: String {
        isProgress ? moment.progress(at: now).detail : moment.summary(on: now).caption
    }

    /// The day and how it repeats, or the age a birthday brings. Progress bars have none.
    private var subtitle: String? {
        isProgress ? nil : moment.subtitle(on: now)
    }

    @ViewBuilder
    private var bar: some View {
        if isProgress {
            ProgressBar(fraction: moment.progress(at: now).fraction, track: moment.tint.opacity(0.16), bar: moment.ink)
                .frame(height: family == .systemLarge ? 8 : 5)
                .padding(.vertical, 4)
        }
    }

    private func name(_ font: Font) -> some View {
        Text(moment.displayName)
            .font(font)
            .lineLimit(1)
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
