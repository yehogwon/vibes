import AppKit
import JotsCore
import Observation
import UniformTypeIdentifiers

/// App-wide state: the scratchpad file and the actions on it.
@MainActor
@Observable
final class AppState {
    let file: JotFile
    /// When the text was last copied, for the editor's "Copied" confirmation.
    private(set) var copiedAt: Date?
    /// Closes the scratchpad popover. Set by the app delegate, which owns it.
    @ObservationIgnored var closeScratchpad: () -> Void = {}

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let settingsWindow = SettingsWindowController()

    init() {
        file = JotFile(url: URL.applicationSupportDirectory.appendingPathComponent("Jots.md"))

        let center = NotificationCenter.default
        for name in [NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.file.flush() }
                })
        }
    }

    // MARK: - Commands

    func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(file.text, forType: .string)
        copiedAt = .now
    }

    func export() {
        file.flush()
        NSApp.activate()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Jots.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try file.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func showInFinder() {
        if !FileManager.default.fileExists(atPath: file.url.path) {
            // Nothing typed yet: create the file so there is something to show.
            file.stage(file.text)
        }
        file.flush()
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func showSettings() {
        settingsWindow.show()
    }
}
