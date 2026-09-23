import Foundation
import Testing

@testable import JotsCore

/// A fresh directory per test, removed afterwards.
private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("JotsCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String = "Jots.md") -> URL {
        url.appendingPathComponent(name)
    }
}

@Suite("JotFile")
@MainActor
struct JotFileTests {
    @Test func startsEmptyWithoutCreatingAFile() throws {
        let directory = try TemporaryDirectory()
        let file = JotFile(url: directory.file())
        #expect(file.text == "")
        #expect(file.lastError == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.file().path))
    }

    @Test func loadsExistingText() throws {
        let directory = try TemporaryDirectory()
        try "# Hello\n한글".write(to: directory.file(), atomically: true, encoding: .utf8)
        #expect(JotFile(url: directory.file()).text == "# Hello\n한글")
    }

    @Test func stagedTextIsVisibleBeforeItIsWritten() throws {
        let directory = try TemporaryDirectory()
        let file = JotFile(url: directory.file())
        file.stage("draft")
        #expect(file.text == "draft")
        #expect(file.savedText == "")
        #expect(file.hasPendingEdits)
        #expect(!FileManager.default.fileExists(atPath: directory.file().path))
    }

    @Test func flushWritesTheFile() throws {
        let directory = try TemporaryDirectory()
        let file = JotFile(url: directory.file())
        file.stage("- [ ] milk")
        file.flush()
        #expect(!file.hasPendingEdits)
        #expect(file.savedText == "- [ ] milk")
        #expect(try String(contentsOf: directory.file(), encoding: .utf8) == "- [ ] milk")
    }

    @Test func createsMissingParentDirectories() throws {
        let directory = try TemporaryDirectory()
        let nested = directory.url.appendingPathComponent("a/b/Jots.md")
        let file = JotFile(url: nested)
        file.stage("x")
        file.flush()
        #expect(try String(contentsOf: nested, encoding: .utf8) == "x")
    }

    @Test func savesAfterTypingPauses() async throws {
        let directory = try TemporaryDirectory()
        let file = JotFile(url: directory.file())
        file.saveDelay = .milliseconds(10)
        file.stage("later")
        try await Task.sleep(for: .milliseconds(300))
        #expect(try String(contentsOf: directory.file(), encoding: .utf8) == "later")
    }

    @Test func unchangedTextIsNotRewritten() throws {
        let directory = try TemporaryDirectory()
        try "same".write(to: directory.file(), atomically: true, encoding: .utf8)
        let before = try FileManager.default.attributesOfItem(atPath: directory.file().path)[.modificationDate] as? Date
        let file = JotFile(url: directory.file())
        file.stage("same")
        file.flush()
        let after = try FileManager.default.attributesOfItem(atPath: directory.file().path)[.modificationDate] as? Date
        #expect(before == after)
    }

    @Test func unreadableFileIsMovedAsideNotOverwritten() throws {
        let directory = try TemporaryDirectory()
        try Data([0xFF, 0xFE, 0xFD]).write(to: directory.file())
        let file = JotFile(url: directory.file())
        #expect(file.text == "")
        #expect(file.lastError != nil)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
        #expect(names.contains { $0.hasPrefix("Jots (unreadable ") && $0.hasSuffix(").md") })
        #expect(!names.contains("Jots.md"))
    }

    @Test func failedSaveKeepsTextStaged() throws {
        let directory = try TemporaryDirectory()
        // A read-only folder makes the write fail.
        let locked = directory.url.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let file = JotFile(url: locked.appendingPathComponent("Jots.md"))
        file.stage("keep me")
        file.flush()
        #expect(file.lastError != nil)
        #expect(file.hasPendingEdits)
        #expect(file.text == "keep me")
    }
}

@Suite("TextStats")
struct TextStatsTests {
    @Test func counts() {
        #expect(TextStats(counting: "") == TextStats(words: 0, characters: 0))
        #expect(TextStats(counting: "one  two\nthree 🎉") == TextStats(words: 4, characters: 16))
        #expect(TextStats(counting: "안녕 하세요") == TextStats(words: 2, characters: 6))
    }
}
