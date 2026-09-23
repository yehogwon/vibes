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

/// Polls until `condition` holds, for changes delivered asynchronously by file coordination.
@MainActor
private func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

/// Writes the way another app or iCloud would: coordinated, but not through the `JotFile`.
private func writeFromElsewhere(_ text: String, to url: URL) throws {
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { writeError = error }
    }
    if let error = coordinationError ?? writeError { throw error }
}

@Suite("JotFile sync")
@MainActor
struct JotFileSyncTests {
    @Test func picksUpChangesMadeElsewhere() async throws {
        let directory = try TemporaryDirectory()
        try "before".write(to: directory.file(), atomically: true, encoding: .utf8)
        let file = JotFile(url: directory.file())
        let revision = file.externalRevision

        try writeFromElsewhere("after", to: directory.file())
        #expect(await eventually { file.text == "after" })
        #expect(file.externalRevision > revision)
        #expect(!file.hasPendingEdits)
    }

    @Test func ownSavesDoNotCountAsExternalChanges() async throws {
        let directory = try TemporaryDirectory()
        let file = JotFile(url: directory.file())
        let revision = file.externalRevision
        file.stage("mine")
        file.flush()
        try await Task.sleep(for: .milliseconds(500))
        #expect(file.externalRevision == revision)
        #expect(file.conflictCopies.isEmpty)
    }

    @Test func simultaneousEditsKeepBothVersions() async throws {
        let directory = try TemporaryDirectory()
        try "base".write(to: directory.file(), atomically: true, encoding: .utf8)
        let file = JotFile(url: directory.file())
        file.saveDelay = .seconds(60)
        file.stage("typed here")

        try writeFromElsewhere("typed elsewhere", to: directory.file())
        #expect(await eventually { !file.conflictCopies.isEmpty })

        // The local edit is still the scratchpad and gets saved; the other version is its own file.
        #expect(file.text == "typed here")
        file.flush()
        #expect(try String(contentsOf: directory.file(), encoding: .utf8) == "typed here")
        let copy = try #require(file.conflictCopies.first)
        #expect(copy.lastPathComponent.hasPrefix("Jots (conflict "))
        #expect(try String(contentsOf: copy, encoding: .utf8) == "typed elsewhere")
    }

    @Test func relocateLoadsTheNewFile() throws {
        let directory = try TemporaryDirectory()
        try "old place".write(to: directory.file("a.md"), atomically: true, encoding: .utf8)
        try "new place".write(to: directory.file("b.md"), atomically: true, encoding: .utf8)
        let file = JotFile(url: directory.file("a.md"))
        let revision = file.externalRevision

        file.relocate(to: directory.file("b.md"))
        #expect(file.url == directory.file("b.md"))
        #expect(file.text == "new place")
        #expect(file.externalRevision > revision)
    }

    @Test func relocateCarryingTextWritesItToTheNewPlace() throws {
        let directory = try TemporaryDirectory()
        let file = JotFile(url: directory.file("a.md"))
        file.stage("keep this")
        let revision = file.externalRevision

        file.relocate(to: directory.file("b.md"), carryingText: true)
        #expect(try String(contentsOf: directory.file("b.md"), encoding: .utf8) == "keep this")
        #expect(try String(contentsOf: directory.file("a.md"), encoding: .utf8) == "keep this")
        #expect(file.externalRevision == revision)
    }
}

@Suite("JotStorage")
struct JotStorageTests {
    private func plainMove(_ from: URL, _ to: URL) throws {
        try FileManager.default.moveItem(at: from, to: to)
    }

    @Test func staysLocalWithoutICloud() throws {
        let directory = try TemporaryDirectory()
        let resolution = JotStorage.resolve(localURL: directory.file(), cloudDocuments: nil, move: plainMove)
        #expect(resolution.location == .local(directory.file()))
        #expect(resolution.notice == nil)
    }

    @Test func movesTheLocalFileIntoICloudTheFirstTime() throws {
        let directory = try TemporaryDirectory()
        let local = directory.file("local.md")
        let cloud = directory.url.appendingPathComponent("cloud/Documents")
        try "mine".write(to: local, atomically: true, encoding: .utf8)

        let resolution = JotStorage.resolve(localURL: local, cloudDocuments: cloud, move: plainMove)
        let cloudFile = cloud.appendingPathComponent("Jots.md")
        #expect(resolution.location == .iCloud(cloudFile))
        #expect(try String(contentsOf: cloudFile, encoding: .utf8) == "mine")
        #expect(!FileManager.default.fileExists(atPath: local.path))
    }

    @Test func keepsBothWhenICloudAlreadyHasDifferentText() throws {
        let directory = try TemporaryDirectory()
        let local = directory.file("local.md")
        let cloud = directory.url.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try "from this mac".write(to: local, atomically: true, encoding: .utf8)
        try "from icloud".write(to: cloud.appendingPathComponent("Jots.md"), atomically: true, encoding: .utf8)

        let resolution = JotStorage.resolve(
            localURL: local, cloudDocuments: cloud, deviceName: "Studio", move: plainMove)
        #expect(resolution.location == .iCloud(cloud.appendingPathComponent("Jots.md")))
        #expect(resolution.notice != nil)
        let kept = cloud.appendingPathComponent("Jots (from Studio).md")
        #expect(try String(contentsOf: kept, encoding: .utf8) == "from this mac")
        #expect(try String(contentsOf: cloud.appendingPathComponent("Jots.md"), encoding: .utf8) == "from icloud")
    }

    @Test func dropsTheLocalCopyWhenItMatchesICloud() throws {
        let directory = try TemporaryDirectory()
        let local = directory.file("local.md")
        let cloud = directory.url.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try "same".write(to: local, atomically: true, encoding: .utf8)
        try "same".write(to: cloud.appendingPathComponent("Jots.md"), atomically: true, encoding: .utf8)

        let resolution = JotStorage.resolve(localURL: local, cloudDocuments: cloud, move: plainMove)
        #expect(resolution.notice == nil)
        #expect(!FileManager.default.fileExists(atPath: local.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: cloud.path) == ["Jots.md"])
    }

    @Test func staysLocalIfTheMoveFails() throws {
        let directory = try TemporaryDirectory()
        let local = directory.file("local.md")
        try "mine".write(to: local, atomically: true, encoding: .utf8)
        struct MoveFailed: Error {}

        let resolution = JotStorage.resolve(
            localURL: local, cloudDocuments: directory.url.appendingPathComponent("cloud"),
            move: { _, _ in throw MoveFailed() })
        #expect(resolution.location == .local(local))
        #expect(resolution.notice != nil)
        #expect(try String(contentsOf: local, encoding: .utf8) == "mine")
    }
}
