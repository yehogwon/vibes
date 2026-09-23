import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.fontFamily) private var fontFamily = EditorFontFamily.system
    @AppStorage(SettingsKey.fontSize) private var fontSize = 14.0
    @AppStorage(SettingsKey.hidesSyntax) private var hidesSyntax = true

    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?

    var body: some View {
        @Bindable var app = app
        Form {
            Section("General") {
                LabeledContent("Open Jots from anywhere") {
                    HotKeyRecorder(shortcut: $app.hotKey, onRecordingChange: app.pauseHotKey)
                }
                if let error = app.hotKeyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Open Jots at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in updateLoginItem(enabled) }
                if let loginItemMessage {
                    HStack {
                        Text(loginItemMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
            }
            Section("Editor") {
                Picker("Font", selection: $fontFamily) {
                    ForEach(EditorFontFamily.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                LabeledContent("Size") {
                    Stepper(value: $fontSize, in: 10...28, step: 1) {
                        Text("\(Int(fontSize)) pt").monospacedDigit()
                    }
                }
                Toggle("Hide Markdown syntax outside the current line", isOn: $hidesSyntax)
            }
            Section("Storage") {
                LabeledContent("Scratchpad", value: app.storageDescription)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
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
