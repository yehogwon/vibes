import CountsCore
import ServiceManagement
import SwiftUI

/// Settings live in the panel too; Counts has no windows of its own.
struct SettingsPage: View {
    @Environment(AppState.self) private var app
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Settings") {
                BackButton(help: "Back to the timers (Esc)") { app.route = .timers }
            } trailing: {
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show timers when the pointer rests on the menu bar item", isOn: $app.opensOnHover)
                Toggle("Open Counts at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in updateLoginItem(enabled) }
                if let loginItemMessage {
                    HStack {
                        Text(loginItemMessage)
                            .foregroundStyle(.secondary)
                        Button("Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Divider()
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    SyncStatusLabel(status: app.store.status)
                        .font(.callout.weight(.medium))
                    Text(app.syncDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .failed(let message) = app.store.status {
                        Label {
                            Text(message)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                HStack {
                    Button("Sync Now") { app.store.sync() }
                        .disabled(app.store.folderURL == nil)
                    Button("Show in Finder") { app.showSyncFolder() }
                        .disabled(app.store.folderURL == nil)
                }
                Divider()
                    .padding(.vertical, 2)
                Button("Quit Counts") { NSApp.terminate(nil) }
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .onAppear(perform: refreshLoginItem)
    }

    private func updateLoginItem(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            loginItemMessage = error.localizedDescription
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled || status == .requiresApproval
        loginItemMessage =
            status == .requiresApproval ? "Allow Counts in System Settings to finish turning this on." : nil
    }
}
