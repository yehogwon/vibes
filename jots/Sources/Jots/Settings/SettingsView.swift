import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// Settings live in the panel, in place of the scratchpad; Jots has no windows of its own.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.fontFamily) private var fontFamily = EditorFontFamily.system
    @AppStorage(SettingsKey.fontSize) private var fontSize = 14.0
    @AppStorage(SettingsKey.hidesSyntax) private var hidesSyntax = true
    @AppStorage(SettingsKey.opensOnHover) private var opensOnHover = true

    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { app.showsSettings = false } label: {
                    IconLabel(title: "Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .padding(.leading, -4)
                .help("Back to the scratchpad (Esc)")
                Text("Settings")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Open Jots from anywhere") {
                    HotKeyRecorder(shortcut: $app.hotKey, onRecordingChange: app.pauseHotKey)
                }
                .fixedSize()
                if let error = app.hotKeyError {
                    Label {
                        Text(error)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Toggle("Show the scratchpad when the pointer rests on the menu bar icon", isOn: $opensOnHover)
                Toggle("Open Jots at login", isOn: $opensAtLogin)
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
                Picker("Font", selection: $fontFamily) {
                    ForEach(EditorFontFamily.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                .fixedSize()
                LabeledContent("Size") {
                    Stepper(value: $fontSize, in: 10...28, step: 1) {
                        Text("\(Int(fontSize)) pt").monospacedDigit()
                    }
                }
                .fixedSize()
                Toggle("Hide Markdown syntax outside the current line", isOn: $hidesSyntax)
                Divider()
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scratchpad")
                        .font(.callout.weight(.medium))
                    Text(app.storageDescription)
                        .foregroundStyle(.secondary)
                    if let hint = app.storageHint {
                        Text(hint)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .controlSize(.small)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            status == .requiresApproval ? "Allow Jots in System Settings to finish turning this on." : nil
    }
}

/// A button that records a keyboard shortcut: click it, then press the keys. Escape cancels.
private struct HotKeyRecorder: View {
    @Binding var shortcut: HotKeyShortcut?
    /// Called with `true` while recording, so the current shortcut doesn't fire mid-recording.
    var onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Type a shortcut…" : shortcut?.label ?? "Record Shortcut")
                    .frame(minWidth: 110)
            }
            if shortcut != nil, !isRecording {
                Button("Clear Shortcut", systemImage: "xmark.circle.fill") { shortcut = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
            } else if let recorded = HotKeyShortcut(event: event) {
                shortcut = recorded
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onRecordingChange(false)
    }
}
