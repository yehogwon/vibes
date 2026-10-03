import MomentsCore
import SwiftUI

/// One moment in the list: a countdown, an age, or a progress bar. The editor shows it at its top
/// too, focused: with an avatar of its own, and the number to as many decimals as fit.
struct MomentRow<Avatar: View>: View {
    let moment: Moment
    let now: Date
    var isFocused = false
    @ViewBuilder var avatar: Avatar
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            avatar
            if moment.kind == .progress {
                progressBody(moment.progress(at: now))
            } else {
                countBody
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovered && !isFocused ? 0.07 : 0))
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
                headline(summary.headline)
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
                headline(progress.percent)
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

    /// The list's number; focused, the same to as many decimals as fit, up to 5, moving with the
    /// clock. Its last digits can change faster than the eye follows, so it redraws at most
    /// 20 times a second, or once a second with Reduce Motion on.
    @ViewBuilder
    private func headline(_ text: String) -> some View {
        if isFocused {
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.05)) { context in
                ViewThatFits(in: .horizontal) {
                    ForEach([5, 4, 3, 2, 1, 0], id: \.self) { decimals in
                        Text(moment.preciseHeadline(at: context.date, decimals: decimals))
                    }
                }
            }
        } else {
            Text(text)
        }
    }
}

extension MomentRow where Avatar == AvatarView {
    init(moment: Moment, now: Date) {
        self.init(moment: moment, now: now) { AvatarView(moment: moment, now: now) }
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
