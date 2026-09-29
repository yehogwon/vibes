import MomentsCore
import SwiftUI

/// The list of moments, in the order they were arranged.
struct MomentListPage: View {
    @Environment(AppState.self) private var app
    /// The list's natural height, so the scroll view can be exactly as tall as its rows up to a
    /// limit, and the panel only as tall as it needs to be.
    @State private var listHeight: CGFloat = 0
    @State private var dropTarget: UUID?

    private static let maxListHeight: CGFloat = 470

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Moments", subtitle: app.now.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                EmptyView()
            } trailing: {
                addMenu
            }
            banners
            if app.store.moments.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
                .padding(.top, 4)
            footer
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(app.store.moments) { moment in
                    MomentRow(moment: moment, now: app.now)
                        .overlay(alignment: .top) {
                            if dropTarget == moment.id {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .offset(y: -2)
                            }
                        }
                        .onTapGesture { app.edit(moment) }
                        .contextMenu { menu(for: moment) }
                        .draggable(moment.id.uuidString) {
                            MomentRow(moment: moment, now: app.now)
                                .frame(width: PanelController.width - 20)
                        }
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                            withAnimation(.snappy) { app.move(id, before: moment.id) }
                            return true
                        } isTargeted: { targeted in
                            if targeted {
                                dropTarget = moment.id
                            } else if dropTarget == moment.id {
                                dropTarget = nil
                            }
                        }
                }
            }
            .padding(.horizontal, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .scrollIndicators(.automatic)
        .frame(height: min(max(listHeight, 1), Self.maxListHeight))
    }

    @ViewBuilder
    private func menu(for moment: Moment) -> some View {
        Button("Edit…") { app.edit(moment) }
        Button(moment.inMenubar ? "Hide from Menu Bar" : "Show in Menu Bar") { app.toggleMenuBar(moment) }
        Divider()
        Button("Delete", role: .destructive) { app.store.delete(moment.id) }
    }

    private var addMenu: some View {
        Menu {
            Button("New D-Day", systemImage: "calendar") { app.newMoment(.date) }
            Button("New Birthday", systemImage: "birthday.cake") { app.newMoment(.life) }
            Button("New Progress Bar", systemImage: "chart.bar.fill") { app.newMoment(.progress) }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Add a moment")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Count down to the days that matter.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Add a D-Day") { app.newMoment(.date) }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private var banners: some View {
        if let notice = app.store.notice {
            Banner(systemImage: "info.circle", message: notice) { app.store.dismissNotice() }
        }
        if let error = app.store.lastError {
            Banner(systemImage: "exclamationmark.triangle", message: error)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            SyncStatusLabel(status: app.store.status)
            Spacer()
            Button("Settings", systemImage: "gearshape") { app.route = .settings }
                .labelStyle(.iconOnly)
                .help("Settings")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct SyncStatusLabel: View {
    var status: MomentStore.Status

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
