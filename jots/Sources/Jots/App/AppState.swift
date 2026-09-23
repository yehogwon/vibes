import AppKit
import JotsCore
import Observation
import UniformTypeIdentifiers

/// App-wide state: the scratchpad file, where it's stored, and the global shortcut.
@MainActor
@Observable
final class AppState {
    enum Storage: Equatable {
        case checking
        case iCloud
        case local(JotStorage.ICloudStatus)
    }

    let file: JotFile
    private(set) var storage = Storage.checking
    /// Something about storage worth telling the user once, e.g. that two versions were kept.
    private(set) var storageNotice: String?
    /// When the text was last copied, for the editor's "Copied" confirmation.
    private(set) var copiedAt: Date?

    /// The shortcut that opens the scratchpad from any app; `nil` turns it off.
    var hotKey: HotKeyShortcut? {
        didSet {
            UserDefaults.standard.set(hotKey?.rawValue ?? "", forKey: SettingsKey.hotKey)
            registerHotKey()
        }
    }
    private(set) var hotKeyError: String?

    /// Set by the app delegate, which owns the popover.
    @ObservationIgnored var closeScratchpad: () -> Void = {}
    @ObservationIgnored var toggleScratchpad: () -> Void = {}

    @ObservationIgnored private let localURL = URL.applicationSupportDirectory.appendingPathComponent(
        JotStorage.fileName)
    @ObservationIgnored private let globalHotKey = GlobalHotKey()
    @ObservationIgnored private var settingsWindow: SettingsWindowController?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        file = JotFile(url: localURL)
        // A missing value means "never set" (use the default); an empty one means "turned off".
        if let stored = UserDefaults.standard.string(forKey: SettingsKey.hotKey) {
            hotKey = HotKeyShortcut(rawValue: stored)
        } else {
            hotKey = .standard
        }
        globalHotKey.action = { [weak self] in self?.toggleScratchpad() }

        let center = NotificationCenter.default
        for name in [NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.file.flush() }
                })
        }
        // Signing in or out of iCloud moves the scratchpad.
        observers.append(
            center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resolveStorage() }
            })
    }

    /// Registers the shortcut and finds out whether the scratchpad lives in iCloud.
    func start() {
        registerHotKey()
        resolveStorage()
    }

    var isEditable: Bool { file.isEditable && storage != .checking }

    var storageDescription: String {
        switch storage {
        case .checking: "Checking iCloud…"
        case .iCloud: "iCloud Drive › Jots"
        case .local(.signedOut): "On this Mac (sign in to iCloud and turn on iCloud Drive to sync)"
        case .local(.notEntitled): "On this Mac (this build isn't signed for iCloud)"
        case .local: "On this Mac"
        }
    }

    // MARK: - Storage

    private func resolveStorage() {
        let wasInICloud = storage == .iCloud
        file.beginRelocation()
        let localURL = localURL
        Task {
            let (status, resolution) = await Task.detached(priority: .userInitiated) {
                let status = JotStorage.iCloudStatus()
                let resolution = JotStorage.resolve(
                    localURL: localURL, cloudDocuments: status.documentsURL,
                    deviceName: Host.current().localizedName ?? "this Mac")
                return (status, resolution)
            }.value

            switch resolution.location {
            case .iCloud(let url):
                file.relocate(to: url)
                storage = .iCloud
            case .local(let url):
                // Leaving iCloud: keep working on the text that was there.
                file.relocate(to: url, carryingText: wasInICloud)
                storage = .local(status)
            }
            if let notice = resolution.notice {
                storageNotice = notice
            }
        }
    }

    func dismissStorageNotice() {
        storageNotice = nil
    }

    // MARK: - Shortcut

    /// Stops the shortcut while a new one is being recorded, so pressing it doesn't fire.
    func pauseHotKey(_ paused: Bool) {
        if paused {
            globalHotKey.register(nil)
        } else {
            registerHotKey()
        }
    }

    private func registerHotKey() {
        if globalHotKey.register(hotKey) {
            hotKeyError = nil
        } else {
            hotKeyError = "\(hotKey?.label ?? "That shortcut") is already used by another app."
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
        panel.nameFieldStringValue = JotStorage.fileName
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

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showSettings() {
        let controller = settingsWindow ?? SettingsWindowController(state: self)
        settingsWindow = controller
        controller.show()
    }
}
