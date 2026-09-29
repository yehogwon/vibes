import Foundation

/// The folder moments sync through: `moments.json` and `deleted-moments.json`, usually in
/// iCloud Drive, where iCloud carries them between Macs.
///
/// Every access is coordinated with other processes, iCloud's included, on a private queue:
/// coordination can wait for a download, and that mustn't hold up the main thread.
public final class SyncFolder: Sendable {
    public let url: URL
    /// Where `moments.json` is copied before this Mac first writes to it.
    public let backupFolder: URL?

    var momentsURL: URL { url.appendingPathComponent(MomentFile.name) }
    var deletionsURL: URL { url.appendingPathComponent(MomentFile.deletionsName) }

    private let queue = DispatchQueue(label: "Moments sync folder")

    public init(url: URL, backupFolder: URL? = nil) {
        self.url = url
        self.backupFolder = backupFolder
    }

    public struct Result: Sendable {
        public enum Status: Equatable, Sendable {
            case synced
            /// A file is in iCloud but not on this Mac yet; it's being downloaded.
            case downloading
            case failed(String)
        }

        public var library: MomentLibrary
        public var status: Status
        /// Things worth telling the user, e.g. that an unreadable file was set aside.
        public var notices: [String] = []
    }

    /// Merges `library` with the folder and writes back whatever the folder is missing.
    ///
    /// - Parameter presenter: This app's presenter of the folder, so it isn't told about its own
    ///   writes.
    public func sync(_ library: MomentLibrary, presenter: NSFilePresenter?, now: Date = .now) async -> Result {
        let box = PresenterBox(presenter)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.syncNow(library, presenter: box.presenter, now: now))
            }
        }
    }

    /// The blocking part of ``sync(_:presenter:now:)``.
    func syncNow(_ library: MomentLibrary, presenter: NSFilePresenter?, now: Date) -> Result {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return Result(library: library, status: .failed(Self.describe(error)))
        }
        // Reading a file iCloud hasn't downloaded would wait for it, possibly for as long as the
        // Mac is offline. Ask for it and try again once it's here.
        let pending = [momentsURL, deletionsURL].filter(Cloud.isNotDownloaded)
        if !pending.isEmpty {
            pending.forEach(Cloud.startDownloading)
            return Result(library: library, status: .downloading)
        }

        var result = Result(library: library, status: .synced)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: momentsURL, options: .forMerging,
            writingItemAt: deletionsURL, options: .forMerging, error: &coordinationError
        ) { momentsURL, deletionsURL in
            do {
                result = try merge(library, momentsAt: momentsURL, deletionsAt: deletionsURL, now: now)
            } catch {
                result.status = .failed(Self.describe(error))
            }
        }
        if let coordinationError {
            result.status = .failed(Self.describe(coordinationError))
        }
        return result
    }

    private func merge(_ library: MomentLibrary, momentsAt momentsURL: URL, deletionsAt deletionsURL: URL, now: Date)
        throws -> Result
    {
        var notices: [String] = []
        let momentsData = try Self.read(momentsURL)
        let deletionsData = try Self.read(deletionsURL)

        // What the folder has now. A damaged file is kept beside it and written again, so it's
        // set aside only once.
        var onDisk = MomentSet()
        var rewriteMoments = false
        var rewriteDeletions = false
        if let momentsData {
            do {
                onDisk = MomentSet(list: try MomentFile.decode(momentsData))
            } catch where Self.isJSON(momentsData) {
                // Valid JSON of another shape is probably a newer app's format. Replacing it could
                // break that app, so leave it alone.
                return Result(
                    library: library,
                    status: .failed(
                        "\(MomentFile.name) is in a format this version of Moments doesn't know, so it was left alone."))
            } catch {
                notices.append(try setAside(momentsData, of: momentsURL, now: now))
                rewriteMoments = true
            }
        }
        if let deletionsData {
            do {
                onDisk.deleted = try MomentFile.decodeDeletions(deletionsData)
            } catch {
                notices.append(try setAside(deletionsData, of: deletionsURL, now: now))
                rewriteDeletions = true
            }
        }

        // iCloud keeps the losing side of two Macs writing at once as a conflict version. Merge in
        // each one, and only then mark it resolved; one that isn't on this Mac yet waits for the
        // next sync.
        var remote = onDisk
        var resolved: [NSFileVersion] = []
        var waiting: Set<URL> = []
        for file in [momentsURL, deletionsURL] {
            for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: file) ?? [] {
                guard let data = try? Data(contentsOf: version.url) else {
                    waiting.insert(file)
                    continue
                }
                if file == momentsURL, let list = try? MomentFile.decode(data) {
                    remote = MomentMerge.merge(remote, MomentSet(list: list))
                } else if file == deletionsURL, let deleted = try? MomentFile.decodeDeletions(data) {
                    remote.deleted.merge(deleted, uniquingKeysWith: max)
                } else {
                    notices.append(try setAside(data, of: file, now: now, as: "conflict"))
                }
                resolved.append(version)
            }
        }

        var (merged, set) = library.merging(remote)
        merged.forgetDeletions(before: now.addingTimeInterval(-Self.deletionMemory))
        set.deleted = merged.deleted

        if merged.backedUpFolder != url.path {
            if let momentsData, !momentsData.isEmpty, let backupFolder {
                try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
                let backup = Self.uniqueURL(
                    backupFolder.appendingPathComponent("moments \(Self.fileStamp(now)).json"))
                try momentsData.write(to: backup, options: .atomic)
            }
            merged.backedUpFolder = url.path
        }

        // Write only what changed, so a sync that finds nothing new doesn't touch the files (and
        // wake every other Mac).
        let momentsChanged = set.moments != onDisk.moments || set.unreadable != onDisk.unreadable
        if rewriteMoments || momentsChanged && (momentsData != nil || !set.moments.isEmpty || !set.unreadable.isEmpty) {
            try MomentFile.encode(set.list).write(to: momentsURL, options: .atomic)
        }
        if rewriteDeletions || set.deleted != onDisk.deleted && (deletionsData != nil || !set.deleted.isEmpty) {
            try MomentFile.encodeDeletions(set.deleted).write(to: deletionsURL, options: .atomic)
        }

        for version in resolved {
            version.isResolved = true
        }
        for file in [momentsURL, deletionsURL] where !waiting.contains(file) && !resolved.isEmpty {
            try? NSFileVersion.removeOtherVersionsOfItem(at: file)
        }
        return Result(library: merged, status: waiting.isEmpty ? .synced : .downloading, notices: notices)
    }

    /// How long a deletion is remembered.
    static let deletionMemory: TimeInterval = 365 * 24 * 60 * 60


    // MARK: - Helpers

    /// The file's contents, or `nil` if there's no file.
    private static func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// Keeps an unreadable file's contents as "<name> (unreadable <date>).json" beside it.
    private func setAside(_ data: Data, of file: URL, now: Date, as label: String = "unreadable") throws -> String {
        let name = file.deletingPathExtension().lastPathComponent
        let copy = Self.uniqueURL(url.appendingPathComponent("\(name) (\(label) \(Self.fileStamp(now))).json"))
        try data.write(to: copy, options: .atomic)
        let what = label == "conflict" ? "A conflicting copy of \(file.lastPathComponent)" : file.lastPathComponent
        return "\(what) couldn't be read, so it was kept as “\(copy.lastPathComponent)”."
    }

    private static func isJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
    }

    static func fileStamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
    }

    static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let base = url.deletingPathExtension().lastPathComponent
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) \(counter).\(url.pathExtension)")
            counter += 1
        }
        return candidate
    }

    private static func describe(_ error: Error) -> String {
        (error as NSError).localizedDescription
    }
}

/// Hands the presenter to the sync queue. Presenters are only called by the file coordination
/// system, which is thread-safe.
private struct PresenterBox: @unchecked Sendable {
    let presenter: NSFilePresenter?
    init(_ presenter: NSFilePresenter?) { self.presenter = presenter }
}

// MARK: - Watching the folder

/// Tells the app when something in the sync folder changes: another Mac's edit arriving, a
/// conflict version, a file being deleted.
///
/// Callbacks arrive on a private serial queue and only call `onChange`, which is `@Sendable`.
public final class FolderPresenter: NSObject, NSFilePresenter, Sendable {
    public let presentedItemURL: URL?
    public let presentedItemOperationQueue: OperationQueue
    private let onChange: @Sendable () -> Void

    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "Moments folder presenter"
        presentedItemOperationQueue = queue
    }

    public func presentedItemDidChange() { onChange() }
    public func presentedSubitemDidChange(at url: URL) { onChange() }
    public func presentedSubitemDidAppear(at url: URL) { onChange() }
    public func presentedSubitem(at url: URL, didGain version: NSFileVersion) { onChange() }
    public func presentedSubitem(at url: URL, didResolve version: NSFileVersion) {}

    public func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable (Error?) -> Void)
    {
        // The next sync writes the file again from this Mac's copy.
        completionHandler(nil)
        onChange()
    }
}

// MARK: - iCloud

enum Cloud {
    /// A file in iCloud that exists only as a placeholder on this Mac.
    static func isNotDownloaded(_ url: URL) -> Bool {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        if FileManager.default.fileExists(atPath: placeholder.path) {
            return true
        }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        return values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current
    }

    static func startDownloading(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
