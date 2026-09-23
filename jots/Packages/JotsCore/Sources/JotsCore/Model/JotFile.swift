import Foundation
import Observation

/// The scratchpad: one Markdown file on disk, possibly in iCloud Drive.
///
/// The editor stages every change, and the file is rewritten once typing pauses for
/// `saveDelay`, or immediately on ``flush()``. Reads and writes are coordinated with other
/// processes (iCloud, other editors), and changes made elsewhere are loaded as they arrive.
@MainActor
@Observable
public final class JotFile {
    public private(set) var url: URL
    /// The text as last read from or written to disk.
    public private(set) var savedText: String
    /// Increases whenever the text changes from outside the editor (another device, another
    /// app, or a move), so the editor knows to reload.
    public private(set) var externalRevision = 0
    /// The file is in iCloud but not on this Mac yet. Editing waits, so an empty stand-in can't
    /// overwrite the real text.
    public private(set) var isAwaitingDownload = false
    /// The scratchpad is moving between iCloud and this Mac. Editing pauses so nothing is typed
    /// into the file that's being left behind.
    public private(set) var isRelocating = false
    /// The last load or save failure, for surfacing in the UI.
    public private(set) var lastError: String?
    /// Versions that couldn't be merged automatically, kept as separate files beside this one.
    public private(set) var conflictCopies: [URL] = []
    /// How long typing has to pause before staged text is written.
    public var saveDelay: Duration = .milliseconds(500)

    @ObservationIgnored private var pending: String?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var presenter: FilePresenter?

    /// Opens the file at `url`, or starts empty if it doesn't exist yet. The file itself is
    /// only created on the first save.
    ///
    /// A file that exists but can't be read as UTF-8 is moved aside rather than overwritten.
    public init(url: URL) {
        self.url = url
        savedText = ""
        load()
        startPresenting()
    }

    /// The newest text, including edits that haven't been written yet.
    public var text: String { pending ?? savedText }

    /// Whether the editor should accept typing right now.
    public var isEditable: Bool { !isAwaitingDownload && !isRelocating }

    public var hasPendingEdits: Bool { pending != nil }

    /// Records the editor's latest text. It is written after `saveDelay` of inactivity.
    public func stage(_ text: String) {
        guard isEditable else { return }
        if pending == nil {
            SuddenTermination.disable()
        }
        pending = text
        scheduleFlush()
    }

    /// Writes staged text now. Call before the app quits or resigns active.
    public func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard let text = pending else { return }
        pending = nil
        defer { SuddenTermination.enable() }
        guard text != savedText || !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Coordinated.write(text, to: url, presenter: presenter)
            savedText = text
            lastError = nil
        } catch {
            // Keep the text staged so the next flush retries instead of dropping it.
            pending = text
            SuddenTermination.disable()
            lastError = "Couldn't save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Saves pending edits and pauses editing until ``relocate(to:carryingText:)`` finishes the
    /// move.
    public func beginRelocation() {
        flush()
        isRelocating = true
    }

    /// Switches to the file at `newURL`, saving pending edits first and loading its text.
    ///
    /// - Parameter carryingText: Write the current text to `newURL` instead of loading it, for
    ///   when the old location is going away.
    public func relocate(to newURL: URL, carryingText: Bool = false) {
        defer { isRelocating = false }
        guard newURL.standardizedFileURL != url.standardizedFileURL else { return }
        isRelocating = false
        flush()
        let current = text
        stopPresenting()
        url = newURL
        if carryingText {
            savedText = ""
            pending = current
            flush()
        } else {
            load()
        }
        if savedText != current {
            externalRevision += 1
        }
        startPresenting()
    }

    public func dismissConflicts() {
        conflictCopies.removeAll()
    }

    // MARK: - Loading

    private func load() {
        isAwaitingDownload = false
        do {
            savedText = try Coordinated.read(url, presenter: presenter)
            lastError = nil
        } catch CocoaError.fileReadNoSuchFile where Cloud.isNotDownloaded(url) {
            savedText = ""
            isAwaitingDownload = true
            Cloud.startDownloading(url)
        } catch CocoaError.fileReadNoSuchFile {
            savedText = ""
        } catch {
            savedText = ""
            lastError = Self.moveAside(url, reason: error)
        }
    }

    /// Called when the file changed somewhere else and has been read again.
    fileprivate func presentedTextChanged(_ newText: String) {
        let wasAwaitingDownload = isAwaitingDownload
        isAwaitingDownload = false
        guard newText != savedText || wasAwaitingDownload else { return }
        if let pending {
            if pending != newText {
                // Both sides changed. The local edits win the file (they're saved next); the
                // other version is kept beside it so nothing is lost.
                keepConflictCopy(newText)
                savedText = newText
                scheduleFlush()
                return
            }
            // The same text arrived from elsewhere, so there's nothing left to save.
            self.pending = nil
            flushTask?.cancel()
            flushTask = nil
            SuddenTermination.enable()
        }
        savedText = newText
        externalRevision += 1
    }

    fileprivate func presentedItemMoved(to newURL: URL) {
        url = newURL
    }

    fileprivate func presentedConflictKept(_ copy: URL) {
        conflictCopies.append(copy)
    }

    private func keepConflictCopy(_ text: String) {
        do {
            let copy = Self.conflictURL(for: url)
            try Coordinated.write(text, to: copy, presenter: nil)
            conflictCopies.append(copy)
        } catch {
            lastError = "Couldn't keep a conflicting version: \(error.localizedDescription)"
        }
    }

    // MARK: - Presenting

    private func startPresenting() {
        let presenter = FilePresenter(url: url, file: self)
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
    }

    private func stopPresenting() {
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        presenter = nil
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let delay = saveDelay
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    // MARK: - Helpers

    nonisolated static func conflictURL(for url: URL, date: Date = .now) -> URL {
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let base = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        var candidate = directory.appendingPathComponent("\(base) (conflict \(stamp)).\(url.pathExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (conflict \(stamp) \(counter)).\(url.pathExtension)")
            counter += 1
        }
        return candidate
    }

    /// Renames an unreadable file so a fresh scratchpad can't overwrite it. Returns a message
    /// describing what happened.
    private static func moveAside(_ url: URL, reason: Error) -> String {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let name = url.deletingPathExtension().lastPathComponent + " (unreadable \(stamp))." + url.pathExtension
        let backup = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return "\(url.lastPathComponent) couldn't be read, so it was kept as \"\(name)\"."
        } catch {
            return "\(url.lastPathComponent) couldn't be read: \(reason.localizedDescription)"
        }
    }
}

// MARK: - File presenter

/// Receives notifications about the scratchpad file from the file coordination system and
/// forwards them to the `JotFile` on the main actor.
///
/// All callbacks arrive on `presentedItemOperationQueue`, a private serial queue; the only
/// mutable state (`presentedItemURL`) is only changed there.
private final class FilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    private(set) var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private weak var file: JotFile?

    @MainActor
    init(url: URL, file: JotFile) {
        presentedItemURL = url
        self.file = file
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "Jots file presenter"
        presentedItemOperationQueue = queue
    }

    func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        let keptCopies = resolveConflicts(at: url)
        guard let text = try? Coordinated.read(url, presenter: self) else { return }
        Task { @MainActor [weak file] in
            for copy in keptCopies {
                file?.presentedConflictKept(copy)
            }
            file?.presentedTextChanged(text)
        }
    }

    func presentedItemDidGain(_ version: NSFileVersion) {
        if version.isConflict {
            presentedItemDidChange()
        }
    }

    func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
        Task { @MainActor [weak file] in file?.presentedItemMoved(to: newURL) }
    }

    func savePresentedItemChanges(completionHandler: @escaping @Sendable (Error?) -> Void) {
        Task { @MainActor [weak file] in
            file?.flush()
            completionHandler(nil)
        }
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        // The next save recreates the file.
        completionHandler(nil)
    }

    /// iCloud keeps the losing side of a simultaneous edit as a conflict version. Keep each one
    /// that differs as its own file, then mark them resolved.
    private func resolveConflicts(at url: URL) -> [URL] {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else {
            return []
        }
        let current = try? String(contentsOf: url, encoding: .utf8)
        var kept: [URL] = []
        for version in versions {
            if let text = try? String(contentsOf: version.url, encoding: .utf8), text != current {
                let copy = JotFile.conflictURL(for: url, date: version.modificationDate ?? .now)
                if (try? Coordinated.write(text, to: copy, presenter: nil)) != nil {
                    kept.append(copy)
                }
            }
            version.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        return kept
    }
}

// MARK: - Coordinated I/O

private enum Coordinated {
    static func read(_ url: URL, presenter: NSFilePresenter?) throws -> String {
        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: presenter).coordinate(
            readingItemAt: url, options: [], error: &coordinationError
        ) { readURL in
            result = Result { try String(contentsOf: readURL, encoding: .utf8) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func write(_ text: String, to url: URL, presenter: NSFilePresenter?) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error> = .success(())
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { writeURL in
            result = Result { try text.write(to: writeURL, atomically: true, encoding: .utf8) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}

// MARK: - iCloud helpers

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

/// Keeps macOS from killing the process while there are unsaved edits.
private enum SuddenTermination {
    static func disable() {
        #if os(macOS)
            ProcessInfo.processInfo.disableSuddenTermination()
        #endif
    }

    static func enable() {
        #if os(macOS)
            ProcessInfo.processInfo.enableSuddenTermination()
        #endif
    }
}
