import MomentsCore
import SwiftUI

/// One moment in the list: a countdown, an age, or a progress bar.
struct MomentRow: View {
    let moment: Moment
    let now: Date
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if moment.kind == .progress {
                let progress = moment.progress(at: now)
                AvatarView(moment: moment, fraction: progress.fraction)
                progressBody(progress)
            } else {
                AvatarView(moment: moment)
                countBody
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var countBody: some View {
        let summary = moment.summary(on: now)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(moment.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                subtitleText
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(summary.headline)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(moment.ink)
                Text(summary.caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        let count = moment.dayCount(on: now)
        if moment.kind == .life {
            let turning = count.occurrence ?? 0
            return switch count.days {
            case 0: "Turns \(turning) today 🎉"
            case 1: "Turns \(turning) tomorrow"
            default: "Turns \(turning) in \(count.days) days"
            }
        }
        var parts = [count.target.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())]
        switch moment.repeatCycle.step?.component {
        case .day?: parts.append("Every week")
        case .month?: parts.append("Every month")
        case .year?: parts.append("Every year")
        default: break
        }
        return parts.joined(separator: " · ")
    }

    /// The subtitle, with a bell if there's a reminder.
    private var subtitleText: Text {
        guard moment.remindDays >= 0 else { return Text(subtitle) }
        return Text("\(subtitle)  \(Image(systemName: "bell.fill"))")
    }

    private func progressBody(_ progress: SpanProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(moment.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(progress.percent)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(moment.ink)
            }
            ProgressBar(fraction: progress.fraction, track: moment.tint.opacity(0.16), bar: moment.ink)
                .frame(height: 5)
            Text(progress.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ProgressBar: View {
    var fraction: Double
    var track: Color
    var bar: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(bar)
                    .frame(width: max(geometry.size.height, geometry.size.width * fraction))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
    }
}
