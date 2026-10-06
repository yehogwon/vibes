import CountsCore
import SwiftUI

/// Sets a duration and starts a timer. With no timers, it's what the panel shows.
struct NewTimerPage: View {
    @Environment(AppState.self) private var app
    /// The duration in the fields, in seconds, kept for next time.
    @AppStorage(SettingsKey.customDuration) private var duration = 5 * 60
    @FocusState private var focused: Int?

    /// One click starts one of these.
    private static let presets = [60, 3 * 60, 5 * 60, 10 * 60, 15 * 60, 30 * 60, 45 * 60, 60 * 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "New Timer") {
                if !app.store.timers.isEmpty {
                    BackButton(help: "Back to the timers (Esc)") { app.route = .timers }
                }
            } trailing: {
                Button("Start") { app.startTimer(seconds: duration) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(duration == 0)
                    .help("Start a \(Countdown.durationText(duration)) timer (↩)")
            }
            Banners()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    field("Hours", unit: 3600, limit: 99, suffix: "h")
                    field("Minutes", unit: 60, limit: 59, suffix: "m")
                    field("Seconds", unit: 1, limit: 59, suffix: "s")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.presets, id: \.self) { seconds in
                        Button { app.startTimer(seconds: seconds) } label: {
                            Text(Countdown.durationText(seconds))
                                .frame(maxWidth: .infinity)
                        }
                        .help("Start a \(Countdown.durationText(seconds)) timer")
                    }
                }
            }
            .font(.callout)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            Footer()
        }
        .onAppear { focused = 60 }
    }

    /// A field for one part of the duration, which follows every keystroke so Return never starts
    /// a timer without the last digit typed.
    private func field(_ name: String, unit: Int, limit: Int, suffix: String) -> some View {
        let part = Binding {
            duration / unit % (limit + 1)
        } set: { value in
            duration += (min(value, limit) - duration / unit % (limit + 1)) * unit
        }
        return HStack(spacing: 4) {
            TextField(
                name,
                text: Binding {
                    String(part.wrappedValue)
                } set: { text in
                    // The last two digits typed, like a microwave's keypad.
                    part.wrappedValue = Int(String(text.filter(\.isNumber).suffix(2))) ?? 0
                }
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 40)
            .focused($focused, equals: unit)
            .accessibilityLabel(name)
            Text(suffix)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
