import CountsCore
import SwiftUI

/// Everything the panel shows: the timers, the new timer page, or settings. It reports its
/// natural height so the panel can follow it.
struct PanelView: View {
    @Environment(AppState.self) private var app
    var onHeightChange: (CGFloat) -> Void

    var body: some View {
        Group {
            switch app.route {
            case .timers where app.store.timers.isEmpty, .newTimer:
                NewTimerPage()
            case .timers:
                TimersPage()
            case .settings:
                SettingsPage()
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        .frame(width: PanelController.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The top of each page: a title and its controls.
struct PageHeader<Leading: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Text(title)
                .font(.headline)
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 24)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// The header's Back button, which lines its symbol up with the panel's edge inset.
struct BackButton: View {
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            IconLabel(title: "Back", systemImage: "chevron.left")
        }
        .buttonStyle(.borderless)
        .padding(.leading, -4)
        .help(help)
    }
}

/// A short notice, e.g. that an unreadable file was set aside. Its text starts at the panel's
/// edge inset, like everything else.
struct Banner: View {
    var systemImage: String
    /// Warnings color their symbol; the text stays legible in the label colors.
    var symbolColor: Color = .secondary
    var message: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(symbolColor)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("OK", action: dismiss)
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

/// The store's notice and save error, above a page's content.
struct Banners: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let notice = app.store.notice {
            Banner(systemImage: "info.circle", message: notice) { app.store.dismissNotice() }
        }
        if let error = app.store.lastError {
            Banner(systemImage: "exclamationmark.triangle.fill", symbolColor: .orange, message: error)
        }
    }
}

/// The bottom of the timers and new timer pages: where the timers sync, and Settings.
struct Footer: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                SyncStatusLabel(status: app.store.status)
                Spacer()
                Button { app.route = .settings } label: {
                    IconLabel(title: "Settings", systemImage: "gearshape")
                }
                .help("Hover, login, and sync options (⌘,)")
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
        }
    }
}

/// An icon-only button's label, with a hit area bigger than its symbol.
struct IconLabel: View {
    var title: String
    var systemImage: String
    var side: CGFloat = 24

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .frame(width: side, height: side)
            .contentShape(Rectangle())
    }
}

struct SyncStatusLabel: View {
    var status: TimerStore.Status

    var body: some View {
        Label(text, systemImage: symbol)
            .help(help)
    }

    private var text: String {
        switch status {
        case .off: "On this Mac"
        case .connecting: "Connecting to iCloud…"
        case .synced: "Synced with iCloud"
        case .downloading: "Downloading from iCloud…"
        case .failed: "Couldn't sync"
        }
    }

    private var symbol: String {
        switch status {
        case .off: "laptopcomputer"
        case .connecting: "icloud"
        case .synced: "checkmark.icloud"
        case .downloading: "icloud.and.arrow.down"
        case .failed: "exclamationmark.icloud"
        }
    }

    private var help: String {
        switch status {
        case .synced(let date): "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let message): message
        case .off: "Sign in to iCloud and turn on iCloud Drive to sync between Macs."
        default: ""
        }
    }
}
