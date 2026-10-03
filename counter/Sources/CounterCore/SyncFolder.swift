import Foundation

/// The folder timers sync through: `timers.json`, usually in iCloud Drive, where iCloud carries it
/// between Macs.
///
/// Every access is coordinated with other processes, iCloud's included, on a private queue:
/// coordination can wait for a download, and that mustn't hold up the main thread.
public final class SyncFolder: Sendable {
    public let url: URL

    var fileURL: URL { url.appendingPathComponent(TimerFile.name) }

    private let queue = DispatchQueue(label: "Counter sync folder")

    public init(url: URL) {
        self.url = url
    }

    public struct Result: Sendable {
        public enum Status: Equatable, Sendable {
            case synced
            /// The file is in iCloud but not on this Mac yet; it's being downloaded.
            case downloading
            case failed(String)
        }

        public var list: TimerList
        public var status: Status
        /// Things worth telling the user, e.g. that an unreadable file was set aside.
        public var notices: [String] = []
    }

    /// Merges `list` with the folder and writes back whatever the folder is missing.
    ///
    /// - Parameter presenter: This app's presenter of the folder, so it isn't told about its own
    ///   writes.
    public func sync(_ list: TimerList, presenter: NSFilePresenter?, now: Date = .now) async -> Result {
        let box = PresenterBox(presenter)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.syncNow(list, presenter: box.presenter, now: now))
            }
        }
    }

    /// The blocking part of ``sync(_:presenter:now:)``.
    func syncNow(_ list: TimerList, presenter: NSFilePresenter?, now: Date) -> Result {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return Result(list: list, status: .failed(Self.describe(error)))
        }
        // Reading a file iCloud hasn't downloaded would wait for it, possibly for as long as the
        // Mac is offline. Ask for it and try again once it's here.
        if Cloud.isNotDownloaded(fileURL) {
            Cloud.startDownloading(fileURL)
            return Result(list: list, status: .downloading)
        }

        var result = Result(list: list, status: .synced)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: fileURL, options: .forMerging, error: &coordinationError
        ) { fileURL in
            do {
                result = try merge(list, at: fileURL, now: now)
            } catch {
                result.status = .failed(Self.describe(error))
            }
        }
        if let coordinationError {
            result.status = .failed(Self.describe(coordinationError))
        }
        return result
    }

    private func merge(_ list: TimerList, at fileURL: URL, now: Date) throws -> Result {
        var notices: [String] = []
        let data = try Self.read(fileURL)

        // What the folder has now. A damaged file is kept beside it and written again, so it's
        // set aside only once.
        var onDisk = TimerList()
        var rewrite = false
        if let data {
            do {
                onDisk = try TimerFile.decode(data)
            } catch where Self.isJSON(data) {
                // Valid JSON of another shape is probably a newer app's format. Replacing it could
                // break that app, so leave it alone.
                return Result(
                    list: list,
                    status: .failed(
                        "\(TimerFile.name) is in a format this version of Counter doesn't know, so it was left alone."))
            } catch {
                notices.append(try setAside(data, now: now))
                rewrite = true
            }
        }

        // iCloud keeps the losing side of two Macs writing at once as a conflict version. Merge in
        // each one, and only then mark it resolved; one that isn't on this Mac yet waits for the
        // next sync.
        var remote = onDisk
        var resolved: [NSFileVersion] = []
        var waiting = false
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? [] {
            guard let data = try? Data(contentsOf: version.url) else {
                waiting = true
                continue
            }
            if let other = try? TimerFile.decode(data) {
                remote = TimerList.merge(remote, other)
            } else {
                notices.append(try setAside(data, now: now, as: "conflict"))
            }
            resolved.append(version)
        }

        var merged = TimerList.merge(list, remote)
        merged.forgetDeletions(at: now)

        // Write only what changed, so a sync that finds nothing new doesn't touch the file (and
        // wake every other Mac).
        if rewrite || merged != onDisk && (data != nil || !merged.timers.isEmpty || !merged.deleted.isEmpty) {
            try TimerFile.encode(merged).write(to: fileURL, options: .atomic)
        }

        for version in resolved {
            version.isResolved = true
        }
        if !waiting, !resolved.isEmpty {
            try? NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
        }
        return Result(list: merged, status: waiting ? .downloading : .synced, notices: notices)
    }

    // MARK: - Helpers

    /// The file's contents, or `nil` if there's no file.
    private static func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// Keeps an unreadable file's contents as "timers (unreadable <date>).json" beside it.
    private func setAside(_ data: Data, now: Date, as label: String = "unreadable") throws -> String {
        let name = fileURL.deletingPathExtension().lastPathComponent
        let copy = Self.uniqueURL(url.appendingPathComponent("\(name) (\(label) \(Self.fileStamp(now))).json"))
        try data.write(to: copy, options: .atomic)
        let what = label == "conflict" ? "A conflicting copy of \(TimerFile.name)" : TimerFile.name
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

/// Tells the app when something in the sync folder changes: another Mac's timer arriving, a
/// conflict version, the file being deleted.
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
        queue.name = "Counter folder presenter"
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
