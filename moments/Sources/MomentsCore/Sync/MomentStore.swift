import Foundation
import Observation

/// The moments, as the app shows and edits them.
///
/// Edits apply at once and are saved to this Mac's library right away; when a sync folder is
/// connected, they're merged into it in the background, and changes arriving there from other
/// Macs are merged back in. See ``MomentMerge`` for how conflicting changes are combined.
@MainActor
@Observable
public final class MomentStore {
    public enum Status: Equatable, Sendable {
        /// No sync folder: the moments stay on this Mac.
        case off
        /// Connected, and hasn't finished a sync yet.
        case connecting
        case synced(Date)
        /// A file is in iCloud but not on this Mac yet.
        case downloading
        case failed(String)
    }

    /// In list order.
    public private(set) var moments: [Moment] = []
    public private(set) var status = Status.off
    /// Something worth telling the user once, e.g. that an unreadable file was set aside.
    public private(set) var notice: String?
    /// The last failure to save this Mac's library.
    public private(set) var lastError: String?
    public var folderURL: URL? { folder?.url }

    /// Stands in for the clock in tests.
    @ObservationIgnored public var now: @Sendable () -> Date = { .now }

    @ObservationIgnored private var library: MomentLibrary
    @ObservationIgnored private let libraryURL: URL
    @ObservationIgnored private let backupFolder: URL?
    @ObservationIgnored private var folder: SyncFolder?
    @ObservationIgnored private var presenter: FolderPresenter?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var needsSync = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Failed syncs in a row, for backing off.
    @ObservationIgnored private var failures = 0

    /// - Parameters:
    ///   - libraryURL: This Mac's copy of the moments. Created on the first change.
    ///   - backupFolder: Where the sync folder's `moments.json` is copied before this Mac first
    ///     writes to it.
    public init(libraryURL: URL, backupFolder: URL? = nil) {
        self.libraryURL = libraryURL
        self.backupFolder = backupFolder
        library = MomentLibrary()
        load()
    }

    // MARK: - Editing

    public func moment(withID id: UUID) -> Moment? {
        library.moments[id]
    }

    /// Adds the moment, or saves it over the one with its id.
    ///
    /// - Parameter original: The moment as it was when editing began, so only the fields edited
    ///   since are saved and a change another Mac made meanwhile isn't undone.
    public func save(_ moment: Moment, from original: Moment? = nil) {
        library.save(moment, from: original, now: now())
        changed()
    }

    public func delete(_ id: UUID) {
        library.delete(id, now: now())
        changed()
    }

    /// Puts the moments in the order of `ids`.
    public func reorder(_ ids: [UUID]) {
        library.reorder(ids, now: now())
        changed()
    }

    /// The weight that puts a new moment at the end of the list.
    public var nextSortWeight: Int { library.nextSortWeight }

    public func dismissNotice() {
        notice = nil
    }

    private func changed() {
        publish()
        persist()
        sync()
    }

    // MARK: - Syncing

    /// Syncs through the folder at `url`, or stops syncing if it's `nil`. The moments stay either
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
        folder = url.map { SyncFolder(url: $0, backupFolder: backupFolder) }
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
        let snapshot = library
        let result = await folder.sync(snapshot, presenter: presenter, now: now())
        // Disconnected or moved to another folder while this ran.
        guard folder === self.folder else { return }

        let before = library
        library = library.integrating(result.library)
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
        let sorted = library.sortedMoments
        if sorted != moments {
            moments = sorted
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: libraryURL)
            library = try JSONDecoder().decode(MomentLibrary.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            library = MomentLibrary()
        } catch {
            // Keep the unreadable library rather than overwrite it with an empty one.
            let copy = SyncFolder.uniqueURL(
                libraryURL.deletingLastPathComponent().appendingPathComponent(
                    "\(libraryURL.deletingPathExtension().lastPathComponent) (unreadable \(SyncFolder.fileStamp(.now))).json"))
            try? FileManager.default.moveItem(at: libraryURL, to: copy)
            notice = "This Mac's moments couldn't be read, so they were kept as “\(copy.lastPathComponent)”."
            library = MomentLibrary()
        }
        publish()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try MomentFile.encoder.encode(library).write(to: libraryURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn't save your moments: \(error.localizedDescription)"
        }
    }
}
