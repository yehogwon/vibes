import Foundation
import Testing

@testable import CountsCore

/// Two Macs, each with its own library, sharing a sync folder the way iCloud Drive would share it.
@MainActor
final class TwoMacs {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CountsCoreTests-\(UUID().uuidString)")
    let a: TimerStore
    let b: TimerStore
    var cloud: URL { directory.appendingPathComponent("Cloud") }
    var file: URL { cloud.appendingPathComponent(TimerFile.name) }

    init() {
        a = TimerStore(libraryURL: directory.appendingPathComponent("A/Library.json"))
        b = TimerStore(libraryURL: directory.appendingPathComponent("B/Library.json"))
        for store in [a, b] {
            store.now = { at(0) }
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func connect() async {
        a.connect(to: cloud)
        b.connect(to: cloud)
        await settle()
    }

    /// Syncs both until neither has anything new for the other.
    func settle() async {
        for _ in 0..<2 {
            for store in [a, b] {
                store.sync()
                await store.waitForSync()
            }
        }
    }
}

@Suite("Syncing")
@MainActor
struct SyncTests {
    @Test func aTimerStartedOnOneMacShowsOnTheOther() async throws {
        let macs = TwoMacs()
        await macs.connect()
        let timer = Countdown(duration: 300, startingAt: at(0))
        macs.a.add(timer)
        await macs.settle()
        #expect(macs.b.timers == [timer])
        #expect(try TimerFile.decode(Data(contentsOf: macs.file)).sorted == [timer])
    }

    @Test func aTimerRemovedOnOneMacGoesFromTheOther() async {
        let macs = TwoMacs()
        await macs.connect()
        let timer = Countdown(duration: 300, startingAt: at(0))
        macs.a.add(timer)
        await macs.settle()
        macs.b.remove(timer.id)
        await macs.settle()
        #expect(macs.a.timers.isEmpty)
        #expect(macs.b.timers.isEmpty)
    }

    @Test func timersAddedWhileApartAreAllKept() async {
        let macs = TwoMacs()
        let mine = Countdown(duration: 60, startingAt: at(0))
        let theirs = Countdown(duration: 120, startingAt: at(0))
        macs.a.add(mine)
        macs.b.add(theirs)
        await macs.connect()
        #expect(macs.a.timers == [mine, theirs])
        #expect(macs.b.timers == [mine, theirs])
    }

    @Test func timersSurviveARelaunch() {
        let macs = TwoMacs()
        let timer = Countdown(duration: 60, startingAt: at(0))
        macs.a.add(timer)
        let relaunched = TimerStore(libraryURL: macs.directory.appendingPathComponent("A/Library.json"))
        #expect(relaunched.timers == [timer])
    }

    @Test func setsAsideAnUnreadableFileAndWritesItAgain() async throws {
        let macs = TwoMacs()
        try FileManager.default.createDirectory(at: macs.cloud, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: macs.file)
        let timer = Countdown(duration: 60, startingAt: at(0))
        macs.a.add(timer)
        macs.a.connect(to: macs.cloud)
        await macs.a.waitForSync()
        #expect(macs.a.notice?.contains("couldn't be read") == true)
        #expect(try TimerFile.decode(Data(contentsOf: macs.file)).sorted == [timer])
        let names = try FileManager.default.contentsOfDirectory(atPath: macs.cloud.path)
        #expect(names.contains { $0.hasPrefix("timers (unreadable ") })
    }

    @Test func leavesAnotherFormatAlone() async throws {
        let macs = TwoMacs()
        try FileManager.default.createDirectory(at: macs.cloud, withIntermediateDirectories: true)
        let newer = Data(#"[{"something": "else"}]"#.utf8)
        try newer.write(to: macs.file)
        macs.a.add(Countdown(duration: 60, startingAt: at(0)))
        macs.a.connect(to: macs.cloud)
        await macs.a.waitForSync()
        guard case .failed = macs.a.status else {
            Issue.record("Expected the sync to fail, not \(macs.a.status)")
            return
        }
        #expect(try Data(contentsOf: macs.file) == newer)
    }
}
