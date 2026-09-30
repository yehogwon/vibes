import Foundation
import Testing
import os

@testable import MomentsCore

/// A fresh directory per test, removed afterwards.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("MomentsCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }
}

/// A clock the test moves by hand.
///
/// A lock rather than `Mutex`, which needs macOS 15.
final class TestClock: Sendable {
    private let date = OSAllocatedUnfairLock(initialState: at(0))

    var now: Date { date.withLock { $0 } }

    func advance(_ seconds: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// Two Macs: each has its own library and they share a sync folder, the way iCloud Drive would
/// share it.
@MainActor
struct TwoMacs {
    let directory: TemporaryDirectory
    let clock = TestClock()
    let a: MomentStore
    let b: MomentStore
    var cloud: URL { directory.path("Cloud") }

    init() throws {
        directory = try TemporaryDirectory()
        a = MomentStore(libraryURL: directory.path("A/Library.json"), backupFolder: directory.path("A/Backups"))
        b = MomentStore(libraryURL: directory.path("B/Library.json"), backupFolder: directory.path("B/Backups"))
        for store in [a, b] {
            store.now = { [clock] in clock.now }
        }
    }

    func connect() async {
        a.connect(to: cloud)
        b.connect(to: cloud)
        await settle()
    }

    /// Syncs both until neither has anything new for the other.
    func settle() async {
        for _ in 0..<3 {
            for store in [a, b] {
                store.sync()
                await store.waitForSync()
            }
        }
    }

    func disconnect() {
        a.connect(to: nil)
        b.connect(to: nil)
    }

    func cloudMoments() throws -> [Moment] {
        try MomentFile.decode(Data(contentsOf: cloud.appendingPathComponent(MomentFile.name))).moments
    }

    func new(_ name: String, on store: MomentStore) -> Moment {
        let moment = Moment(name: name, date: clock.now, sortWeight: store.nextSortWeight, createdAt: clock.now)
        store.save(moment)
        return moment
    }
}

@Suite("MomentStore", .serialized)
@MainActor
struct MomentStoreTests {
    @Test func keepsMomentsOnThisMacWithoutAFolder() throws {
        let directory = try TemporaryDirectory()
        let url = directory.path("Library.json")
        let store = MomentStore(libraryURL: url)
        #expect(store.status == .off)
        store.save(Moment(name: "Offline", date: .now, createdAt: .now))
        #expect(store.moments.map(\.name) == ["Offline"])
        #expect(MomentStore(libraryURL: url).moments.map(\.name) == ["Offline"])
    }

    @Test func aMomentAddedOnOneMacAppearsOnTheOther() async throws {
        let macs = try TwoMacs()
        await macs.connect()
        _ = macs.new("Exam", on: macs.a)
        await macs.settle()
        #expect(macs.b.moments.map(\.name) == ["Exam"])
        #expect(try macs.cloudMoments().map(\.name) == ["Exam"])
        if case .synced = macs.b.status {} else { Issue.record("B isn't synced: \(macs.b.status)") }
        macs.disconnect()
    }

    @Test func editsToDifferentFieldsOnTwoMacsBothSurvive() async throws {
        let macs = try TwoMacs()
        await macs.connect()
        let trip = macs.new("Trip", on: macs.a)
        await macs.settle()

        // Both Macs edit while offline from each other.
        macs.disconnect()
        macs.clock.advance(60)
        var renamed = try #require(macs.a.moment(withID: trip.id))
        renamed.name = "Trip to Jeju"
        macs.a.save(renamed)
        macs.clock.advance(60)
        var pinned = try #require(macs.b.moment(withID: trip.id))
        pinned.inMenubar = true
        pinned.emoji = "✈️"
        macs.b.save(pinned)

        await macs.connect()
        for store in [macs.a, macs.b] {
            let merged = try #require(store.moment(withID: trip.id))
            #expect(merged.name == "Trip to Jeju")
            #expect(merged.inMenubar)
            #expect(merged.emoji == "✈️")
        }
        macs.disconnect()
    }

    @Test func theLaterEditWinsWhenTwoMacsChangeTheSameField() async throws {
        let macs = try TwoMacs()
        await macs.connect()
        let trip = macs.new("Trip", on: macs.a)
        await macs.settle()

        macs.disconnect()
        macs.clock.advance(60)
        var first = try #require(macs.a.moment(withID: trip.id))
        first.name = "First"
        macs.a.save(first)
        macs.clock.advance(60)
        var second = try #require(macs.b.moment(withID: trip.id))
        second.name = "Second"
        macs.b.save(second)

        await macs.connect()
        #expect(macs.a.moment(withID: trip.id)?.name == "Second")
        #expect(macs.b.moment(withID: trip.id)?.name == "Second")
        macs.disconnect()
    }

    @Test func aDeletionReachesTheOtherMac() async throws {
        let macs = try TwoMacs()
        await macs.connect()
        let doomed = macs.new("Doomed", on: macs.a)
        _ = macs.new("Kept", on: macs.a)
        await macs.settle()
        #expect(macs.b.moments.count == 2)

        macs.clock.advance(10)
        macs.b.delete(doomed.id)
        await macs.settle()
        #expect(macs.a.moments.map(\.name) == ["Kept"])
        #expect(try macs.cloudMoments().map(\.name) == ["Kept"])
        macs.disconnect()
    }

    @Test func anEditAfterADeletionElsewhereBringsTheMomentBack() async throws {
        let macs = try TwoMacs()
        await macs.connect()
        let moment = macs.new("Contested", on: macs.a)
        await macs.settle()

        macs.disconnect()
        macs.clock.advance(10)
        macs.a.delete(moment.id)
        macs.clock.advance(10)
        var edited = try #require(macs.b.moment(withID: moment.id))
        edited.name = "Still wanted"
        macs.b.save(edited)

        await macs.connect()
        #expect(macs.a.moments.map(\.name) == ["Still wanted"])
        #expect(macs.b.moments.map(\.name) == ["Still wanted"])
        macs.disconnect()
    }

    @Test func adoptsAnExistingFileWithoutRewritingIt() async throws {
        let macs = try TwoMacs()
        try FileManager.default.createDirectory(at: macs.cloud, withIntermediateDirectories: true)
        let file = macs.cloud.appendingPathComponent(MomentFile.name)
        let original = Data(MomentFileTests.original.utf8)
        try original.write(to: file)

        macs.a.connect(to: macs.cloud)
        await macs.a.waitForSync()
        #expect(macs.a.moments.map(\.displayName) == ["This Year", "Graduation"])
        #expect(try Data(contentsOf: file) == original)
        #expect(!FileManager.default.fileExists(atPath: macs.cloud.appendingPathComponent(MomentFile.deletionsName).path))

        // It was backed up before this Mac could write to it.
        let backups = try FileManager.default.contentsOfDirectory(
            at: macs.directory.path("A/Backups"), includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try backups.first.map { try Data(contentsOf: $0) } == original)
        macs.disconnect()
    }

    @Test func setsAsideAFileItCantRead() async throws {
        let macs = try TwoMacs()
        try FileManager.default.createDirectory(at: macs.cloud, withIntermediateDirectories: true)
        let file = macs.cloud.appendingPathComponent(MomentFile.name)
        try Data("{ not a list".utf8).write(to: file)

        _ = macs.new("Local", on: macs.a)
        macs.a.connect(to: macs.cloud)
        await macs.a.waitForSync()

        #expect(try macs.cloudMoments().map(\.name) == ["Local"])
        let names = try FileManager.default.contentsOfDirectory(atPath: macs.cloud.path)
        let kept = try #require(names.first { $0.hasPrefix("moments (unreadable") })
        #expect(try String(contentsOf: macs.cloud.appendingPathComponent(kept), encoding: .utf8) == "{ not a list")
        #expect(macs.a.notice?.contains(kept) == true)
        macs.disconnect()
    }

    @Test func aSyncWithNothingNewLeavesTheFilesAlone() async throws {
        let macs = try TwoMacs()
        await macs.connect()
        _ = macs.new("Stable", on: macs.a)
        await macs.settle()
        let file = macs.cloud.appendingPathComponent(MomentFile.name)
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date

        try await Task.sleep(for: .milliseconds(20))
        await macs.settle()
        let after = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        #expect(before == after)
        macs.disconnect()
    }

    @Test func leavingTheFolderKeepsTheMoments() async throws {
        let macs = try TwoMacs()
        await macs.connect()
        _ = macs.new("Mine", on: macs.a)
        await macs.settle()
        macs.b.connect(to: nil)
        #expect(macs.b.status == .off)
        #expect(macs.b.moments.map(\.name) == ["Mine"])
        macs.disconnect()
    }

    @Test func editsBothMacsWroteWhileApartBothSurvive() async throws {
        let macs = try TwoMacs()
        await macs.connect()
        let trip = macs.new("Trip", on: macs.a)
        await macs.settle()
        macs.disconnect()

        // Offline, each Mac's copy of iCloud Drive is still there and writable, so each writes
        // its edit to its own copy of the file.
        let copyA = macs.directory.path("Cloud A")
        let copyB = macs.directory.path("Cloud B")
        try FileManager.default.copyItem(at: macs.cloud, to: copyA)
        try FileManager.default.copyItem(at: macs.cloud, to: copyB)
        macs.clock.advance(60)
        macs.a.connect(to: copyA)
        var renamed = try #require(macs.a.moment(withID: trip.id))
        renamed.name = "Trip to Jeju"
        macs.a.save(renamed)
        await macs.a.waitForSync()
        macs.clock.advance(5)
        macs.b.connect(to: copyB)
        var decorated = try #require(macs.b.moment(withID: trip.id))
        decorated.emoji = "🎒"
        macs.b.save(decorated)
        await macs.b.waitForSync()
        macs.disconnect()

        // Back online, iCloud keeps A's file.
        let file = macs.cloud.appendingPathComponent(MomentFile.name)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.copyItem(at: copyA.appendingPathComponent(MomentFile.name), to: file)
        await macs.connect()
        for store in [macs.a, macs.b] {
            let merged = try #require(store.moment(withID: trip.id))
            #expect(merged.name == "Trip to Jeju")
            #expect(merged.emoji == "🎒")
        }
        #expect(try macs.cloudMoments().first?.emoji == "🎒")
        macs.disconnect()
    }

    @Test func setsAsideAnUnreadableFileOnlyOnce() async throws {
        let macs = try TwoMacs()
        try FileManager.default.createDirectory(at: macs.cloud, withIntermediateDirectories: true)
        try Data("{ not a list".utf8).write(to: macs.cloud.appendingPathComponent(MomentFile.name))

        // A new Mac with nothing of its own to write.
        macs.a.connect(to: macs.cloud)
        for _ in 0..<3 {
            macs.a.sync()
            await macs.a.waitForSync()
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: macs.cloud.path)
        #expect(names.filter { $0.contains("unreadable") }.count == 1)
        #expect(try macs.cloudMoments().isEmpty)
        macs.disconnect()
    }

    @Test func leavesAFileInAnUnknownFormatAlone() async throws {
        let macs = try TwoMacs()
        try FileManager.default.createDirectory(at: macs.cloud, withIntermediateDirectories: true)
        let file = macs.cloud.appendingPathComponent(MomentFile.name)
        let newer = Data(#"{"version" : 2, "moments" : []}"#.utf8)
        try newer.write(to: file)

        _ = macs.new("Local", on: macs.a)
        macs.a.connect(to: macs.cloud)
        await macs.a.waitForSync()
        guard case .failed = macs.a.status else {
            Issue.record("Expected a failure, got \(macs.a.status)")
            return
        }
        #expect(try Data(contentsOf: file) == newer)
        #expect(try FileManager.default.contentsOfDirectory(atPath: macs.cloud.path) == [MomentFile.name])
        #expect(macs.a.moments.map(\.name) == ["Local"])
        macs.disconnect()
    }
}
