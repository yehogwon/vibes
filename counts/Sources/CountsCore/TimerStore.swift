import Foundation
import Observation

/// The timers, as the app shows them.
///
/// Changes apply at once and are saved to this Mac's library right away; when a sync folder is
/// connected, they're merged into it in the background, and timers arriving there from other Macs
/// are merged back in. See ``TimerList/merge(_:_:)`` for how.
@MainActor
@Observable
public final class TimerStore {
    public enum Status: Equatable, Sendable {
        /// No sync folder: the timers stay on this Mac.
        case off
        /// Connected, and hasn't finished a sync yet.
        case connecting
        case synced(Date)
        /// The file is in iCloud but not on this Mac yet.
        case downloading
        case failed(String)
    }

    /// In list order: the one that ends first, first.
    public private(set) var timers: [Countdown] = []
    public private(set) var status = Status.off
    /// Something worth telling the user once, e.g. that an unreadable file was set aside.
    public private(set) var notice: String?
    /// The last failure to save this Mac's library.
    public private(set) var lastError: String?
    public var folderURL: URL? { folder?.url }

    /// Stands in for the clock in tests.
    @ObservationIgnored public var now: @Sendable () -> Date = { .now }

    @ObservationIgnored private var library = TimerList()
    @ObservationIgnored private let libraryURL: URL
    @ObservationIgnored private var folder: SyncFolder?
    @ObservationIgnored private var presenter: FolderPresenter?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var needsSync = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Failed syncs in a row, for backing off.
    @ObservationIgnored private var failures = 0

    /// - Parameter libraryURL: This Mac's copy of the timers. Created on the first change.
    public init(libraryURL: URL) {
        self.libraryURL = libraryURL
        load()
    }

    // MARK: - Changes

    public func add(_ timer: Countdown) {
        library.add(timer)
        changed()
    }

    public func remove(_ id: UUID) {
        library.remove(id, now: now())
        changed()
    }

    public func dismissNotice() {
        notice = nil
    }

    private func changed() {
        publish()
        persist()
        sync()
    }

    // MARK: - Syncing

    /// Syncs through the folder at `url`, or stops syncing if it's `nil`. The timers stay either
    /// way: this Mac keeps its own copy.
    public func connect(to url: URL?) {
        guard url?.standardizedFileURL != folder?.url.standardizedFileURL else {
            sync()
            return
        }
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        presenter = nil
        retryTask?.cancel()
        failures = 0
        folder = url.map { SyncFolder(url: $0) }
        guard let url else {
            status = .off
            return
        }
        status = .connecting
        let presenter = FolderPresenter(url: url) { [weak self] in
            Task { @MainActor in self?.sync() }
        }
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
        sync()
    }

    /// Syncs with the folder soon, e.g. because something changed or the user is looking.
    public func sync() {
        guard folder != nil else { return }
        needsSync = true
        guard syncTask == nil else { return }
        syncTask = Task {
            while needsSync {
                needsSync = false
                await syncOnce()
            }
            syncTask = nil
        }
    }

    /// Waits for the current sync, if any, to finish. For tests.
    public func waitForSync() async {
        while let task = syncTask {
            await task.value
        }
    }

    private func syncOnce() async {
        guard let folder else { return }
        let result = await folder.sync(library, presenter: presenter, now: now())
        // Disconnected or moved to another folder while this ran.
        guard folder === self.folder else { return }

        // Keeps whatever changed here while the sync ran.
        let before = library
        library = TimerList.merge(library, result.list)
        library.forgetDeletions(at: now())
        if let notice = result.notices.last {
            self.notice = notice
        }
        switch result.status {
        case .synced:
            status = .synced(now())
            failures = 0
        case .downloading:
            status = .downloading
            scheduleRetry(after: 3)
        case .failed(let message):
            status = .failed(message)
            // Something that keeps failing is tried less and less often, up to every 5 minutes.
            failures += 1
            scheduleRetry(after: min(3 * pow(2, Double(failures - 1)), 300))
        }
        if library != before {
            publish()
            persist()
        }
    }

    /// iCloud doesn't always say when a download finishes, so check again in a bit.
    private func scheduleRetry(after seconds: Double) {
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            sync()
        }
    }

    // MARK: - This Mac's library

    private func publish() {
        let sorted = library.sorted
        if sorted != timers {
            timers = sorted
        }
    }

    private func load() {
        do {
            library = try TimerFile.decode(Data(contentsOf: libraryURL))
        } catch CocoaError.fileReadNoSuchFile {
            library = TimerList()
        } catch {
            // Keep the unreadable library rather than overwrite it with an empty one.
            let copy = SyncFolder.uniqueURL(
                libraryURL.deletingLastPathComponent().appendingPathComponent(
                    "\(libraryURL.deletingPathExtension().lastPathComponent) (unreadable \(SyncFolder.fileStamp(.now))).json"))
            try? FileManager.default.moveItem(at: libraryURL, to: copy)
            notice = "This Mac's timers couldn't be read, so they were kept as “\(copy.lastPathComponent)”."
            library = TimerList()
        }
        publish()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try TimerFile.encode(library).write(to: libraryURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn't save your timers: \(error.localizedDescription)"
        }
    }
}
