import Foundation
import Observation

/// The scratchpad: one Markdown file on disk.
///
/// The editor stages every change, and the file is rewritten once typing pauses for
/// `saveDelay`, or immediately on ``flush()``. Writes are atomic, so a crash mid-save leaves the
/// previous version intact.
@MainActor
@Observable
public final class JotFile {
    public let url: URL
    /// The text as last read from or written to disk.
    public private(set) var savedText: String
    /// The last load or save failure, for surfacing in the UI.
    public private(set) var lastError: String?
    /// How long typing has to pause before staged text is written.
    public var saveDelay: Duration = .milliseconds(500)

    @ObservationIgnored private var pending: String?
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    /// Opens the file at `url`, or starts empty if it doesn't exist yet. The file itself is
    /// only created on the first save.
    ///
    /// A file that exists but can't be read as UTF-8 is moved aside rather than overwritten.
    public init(url: URL) {
        self.url = url
        do {
            savedText = try String(contentsOf: url, encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile {
            savedText = ""
        } catch {
            savedText = ""
            lastError = Self.moveAside(url, reason: error)
        }
    }

    /// The newest text, including edits that haven't been written yet.
    public var text: String { pending ?? savedText }

    public var hasPendingEdits: Bool { pending != nil }

    /// Records the editor's latest text. It is written after `saveDelay` of inactivity.
    public func stage(_ text: String) {
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
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedText = text
            lastError = nil
        } catch {
            // Keep the text staged so the next flush retries instead of dropping it.
            pending = text
            SuddenTermination.disable()
            lastError = "Couldn't save \(url.lastPathComponent): \(error.localizedDescription)"
        }
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
