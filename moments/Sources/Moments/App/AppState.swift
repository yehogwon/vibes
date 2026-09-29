import AppKit
import MomentsCore
import Observation

/// App-wide state: the moments, the clock the list counts by, and what the panel shows.
@MainActor
@Observable
final class AppState {
    enum Route: Equatable {
        case list
        case editor(Moment, isNew: Bool)
        case settings
    }

    let store: MomentStore
    /// What the panel shows.
    var route = Route.list
    /// The time the list counts from. Moves every half minute and whenever the day, the clock,
    /// or the time zone changes.
    private(set) var now = Date.now

    /// Show the list when the pointer rests on a menu bar item, not only on a click.
    var opensOnHover: Bool {
        didSet { UserDefaults.standard.set(opensOnHover, forKey: SettingsKey.opensOnHover) }
    }

    /// Set by the app delegate, which owns the panel.
    @ObservationIgnored var closePanel: () -> Void = {}
    /// Lets a modal window (the photo picker) show above the panel while it's up.
    @ObservationIgnored var lowerPanel: (Bool) -> Void = { _ in }
    /// Called when the moments or the day change, to update menu bar items and reminders.
    @ObservationIgnored var momentsDidChange: () -> Void = {}

    @ObservationIgnored private let reminders = Reminders()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timers: [Timer] = []

    init() {
        let defaults = UserDefaults.standard
        // For trying sync with a second copy: `-MomentsLocalFolder <path>` keeps this copy's
        // moments elsewhere.
        let localFolder =
            defaults.string(forKey: SettingsKey.localFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL.applicationSupportDirectory.appendingPathComponent("Moments", isDirectory: true)
        store = MomentStore(
            libraryURL: localFolder.appendingPathComponent("Library.json"),
            backupFolder: localFolder.appendingPathComponent("Backups", isDirectory: true))
        opensOnHover = defaults.object(forKey: SettingsKey.opensOnHover) as? Bool ?? true
    }

    func start() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observe(name, in: center) { $0.tick() }
        }
        observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { state in
            state.tick()
            state.store.sync()
        }
        // Signing in or out of iCloud changes where the moments sync.
        observe(.NSUbiquityIdentityDidChange, in: center) { $0.resolveSyncFolder() }

        timers.append(
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            })
        // iCloud usually says when a file changes, but not always; look now and then anyway.
        timers.append(
            Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.sync() }
            })

        observeMoments()
        resolveSyncFolder()
        momentsDidChange()
    }

    // MARK: - Editing

    func newMoment(_ kind: Moment.Kind) {
        let today = Calendar.current.startOfDay(for: now)
        let moment = Moment(
            kind: kind, date: kind == .progress ? now : today, startDate: today,
            endDate: kind == .progress ? Calendar.current.date(byAdding: .month, value: 1, to: today) : nil,
            sortWeight: store.nextSortWeight, createdAt: now)
        route = .editor(moment, isNew: true)
    }

    func edit(_ moment: Moment) {
        route = .editor(store.moment(withID: moment.id) ?? moment, isNew: false)
    }

    /// - Parameter original: The moment as editing began, so a change that arrived from another
    ///   Mac while editing isn't undone.
    func save(_ moment: Moment, editedFrom original: Moment?) {
        store.save(moment, from: original)
        route = .list
    }

    func delete(_ id: UUID) {
        store.delete(id)
        route = .list
    }

    func toggleMenuBar(_ moment: Moment) {
        guard var current = store.moment(withID: moment.id) else { return }
        current.inMenubar.toggle()
        store.save(current)
    }

    /// Moves the moment `id` to just before `target`, or to the end.
    func move(_ id: UUID, before target: UUID?) {
        guard id != target else { return }
        var ids = store.moments.map(\.id).filter { $0 != id }
        let index = target.flatMap { ids.firstIndex(of: $0) } ?? ids.endIndex
        ids.insert(id, at: index)
        store.reorder(ids)
    }

    /// Esc: leaves the editor or settings first, then closes the panel.
    func goBack() {
        if route == .list {
            closePanel()
        } else {
            route = .list
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
        let file = folder.appendingPathComponent(MomentFile.name)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    nonisolated private static let iCloudDrive = URL.homeDirectory.appendingPathComponent(
        "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

    /// The folder the original Moment syncs `moments.json` through, so both share it. Writing
    /// straight into iCloud Drive needs no iCloud entitlement, so an ad hoc signed build syncs.
    nonisolated private static func iCloudFolder() -> URL? {
        if let override = UserDefaults.standard.string(forKey: SettingsKey.syncFolder) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard FileManager.default.ubiquityIdentityToken != nil,
            FileManager.default.fileExists(atPath: iCloudDrive.path)
        else { return nil }
        return iCloudDrive.appendingPathComponent("Moment", isDirectory: true)
    }

    private func resolveSyncFolder() {
        Task {
            // Asking for the iCloud identity can take a moment.
            let folder = await Task.detached(priority: .userInitiated) { Self.iCloudFolder() }.value
            store.connect(to: folder)
        }
    }

    // MARK: - Updates

    private func tick() {
        now = .now
        // Progress items in the menu bar move within the day, so update them every tick.
        momentsDidChange()
        reminders.update(store.moments, now: now)
    }

    private func observeMoments() {
        withObservationTracking {
            _ = store.moments
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.momentsDidChange()
                self.reminders.update(self.store.moments, now: self.now)
                self.observeMoments()
            }
        }
        reminders.update(store.moments, now: now)
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
    static let syncFolder = "MomentsSyncFolder"
    static let localFolder = "MomentsLocalFolder"
}
