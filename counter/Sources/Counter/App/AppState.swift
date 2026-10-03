import AppKit
import CounterCore
import Observation

/// App-wide state: the timers, the clock they count by, and what the panel shows.
@MainActor
@Observable
final class AppState {
    enum Route: Equatable {
        case timers
        case newTimer
        case settings
    }

    let store: TimerStore
    /// What the panel shows. With no timers, the timers page is the new timer page.
    var route = Route.timers
    /// The time the timers count from. Moves on each whole second while one is running.
    private(set) var now = Date.now

    /// Show the timers when the pointer rests on the menu bar item, not only on a click.
    var opensOnHover: Bool {
        didSet { UserDefaults.standard.set(opensOnHover, forKey: SettingsKey.opensOnHover) }
    }

    /// Set by the app delegate, which owns the panel.
    @ObservationIgnored var closePanel: () -> Void = {}
    /// Called when the timers change or the clock moves, to update the menu bar item.
    @ObservationIgnored var timersDidChange: () -> Void = {}

    @ObservationIgnored private let alerts = Alerts()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var syncTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        // For trying sync with a second copy: `-CounterLocalFolder <path>` keeps this copy's
        // timers elsewhere.
        let localFolder =
            defaults.string(forKey: SettingsKey.localFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL.applicationSupportDirectory.appendingPathComponent("Counter", isDirectory: true)
        store = TimerStore(libraryURL: localFolder.appendingPathComponent("Library.json"))
        opensOnHover = defaults.object(forKey: SettingsKey.opensOnHover) as? Bool ?? true
    }

    func start() {
        alerts.start()
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observe(name, in: center) { $0.tick() }
        }
        observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { state in
            state.tick()
            state.store.sync()
        }
        // Signing in or out of iCloud changes where the timers sync.
        observe(.NSUbiquityIdentityDidChange, in: center) { $0.resolveSyncFolder() }
        // iCloud usually says when a file changes, but not always; look now and then anyway.
        syncTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.sync() }
        }

        observeTimers()
        resolveSyncFolder()
        tick()
    }

    // MARK: - Timers

    func startTimer(seconds: Int) {
        guard seconds > 0 else { return }
        now = .now
        store.add(Countdown(duration: seconds, startingAt: now))
        route = .timers
    }

    func remove(_ timer: Countdown) {
        store.remove(timer.id)
    }

    /// Esc: leaves the new timer page or settings first, then closes the panel.
    func goBack() {
        if route == .settings || route == .newTimer && !store.timers.isEmpty {
            route = .timers
        } else {
            closePanel()
        }
    }

    // MARK: - Sync folder

    var syncDescription: String {
        guard let folder = store.folderURL else {
            return "On this Mac only. Sign in to iCloud and turn on iCloud Drive to sync."
        }
        if folder.path.hasPrefix(Self.iCloudDrive.path) {
            return "iCloud Drive › " + folder.path.dropFirst(Self.iCloudDrive.path.count + 1)
                .replacingOccurrences(of: "/", with: " › ")
        }
        return folder.path
    }

    func showSyncFolder() {
        guard let folder = store.folderURL else { return }
        let file = folder.appendingPathComponent(TimerFile.name)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    nonisolated private static let iCloudDrive = URL.homeDirectory.appendingPathComponent(
        "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

    /// A Counter folder in iCloud Drive. Writing straight into iCloud Drive needs no iCloud
    /// entitlement, so an ad hoc signed build syncs.
    nonisolated private static func iCloudFolder() -> URL? {
        if let override = UserDefaults.standard.string(forKey: SettingsKey.syncFolder) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard FileManager.default.ubiquityIdentityToken != nil,
            FileManager.default.fileExists(atPath: iCloudDrive.path)
        else { return nil }
        return iCloudDrive.appendingPathComponent("Counter", isDirectory: true)
    }

    private func resolveSyncFolder() {
        Task {
            // Asking for the iCloud identity can take a moment.
            let folder = await Task.detached(priority: .userInitiated) { Self.iCloudFolder() }.value
            store.connect(to: folder)
        }
    }

    // MARK: - Updates

    /// Moves the clock, then waits for the next whole second if a timer is still running. Each
    /// timer ends on a whole second, so its countdown changes together with the system clock.
    private func tick() {
        now = .now
        timersDidChange()
        alerts.update(store.timers, now: now)
        ticker?.invalidate()
        ticker = nil
        guard store.timers.contains(where: { !$0.hasEnded(at: now) }) else { return }
        let next = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down) + 1)
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Common modes keep it ticking while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func observeTimers() {
        withObservationTracking {
            _ = store.timers
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.tick()
                self?.observeTimers()
            }
        }
    }

    private func observe(
        _ name: Notification.Name, in center: NotificationCenter, perform: @escaping @MainActor (AppState) -> Void
    ) {
        observers.append(
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self { perform(self) }
                }
            })
    }
}

enum SettingsKey {
    static let opensOnHover = "OpensOnHover"
    static let customDuration = "CustomDuration"
    static let syncFolder = "CounterSyncFolder"
    static let localFolder = "CounterLocalFolder"
}
