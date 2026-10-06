import Foundation
import Testing

@testable import CountsCore

/// Seconds after a fixed start, to keep the arithmetic readable.
func at(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_790_000_000 + seconds)
}

@Suite("Countdown")
struct CountdownTests {
    @Test func readsMinutesAndSecondsUnderAnHour() {
        #expect(Countdown.clock(0) == "0:00")
        #expect(Countdown.clock(5) == "0:05")
        #expect(Countdown.clock(299) == "4:59")
        #expect(Countdown.clock(3599) == "59:59")
    }

    @Test func readsHoursFromAnHour() {
        #expect(Countdown.clock(3600) == "1:00:00")
        #expect(Countdown.clock(3900) == "1:05:00")
        #expect(Countdown.clock(100 * 3600 + 61) == "100:01:01")
    }

    @Test func roundsUpSoItReadsZeroOnlyOnceEnded() {
        let timer = Countdown(duration: 300, startingAt: at(0))
        #expect(timer.clock(at: at(0)) == "5:00")
        #expect(timer.clock(at: at(0.5)) == "5:00")
        #expect(timer.clock(at: at(1)) == "4:59")
        #expect(timer.clock(at: at(299.9)) == "0:01")
        #expect(!timer.hasEnded(at: at(299.9)))
        #expect(timer.clock(at: at(300)) == "Done")
        #expect(timer.hasEnded(at: at(300)))
        #expect(timer.secondsLeft(at: at(400)) == 0)
    }

    @Test func startsOnAWholeSecond() {
        let timer = Countdown(duration: 60, startingAt: at(0.7))
        #expect(timer.endsAt == at(60))
    }

    @Test func drainsFromOneToZero() {
        let timer = Countdown(duration: 100, startingAt: at(0))
        #expect(timer.fractionLeft(at: at(0)) == 1)
        #expect(timer.fractionLeft(at: at(25)) == 0.75)
        #expect(timer.fractionLeft(at: at(200)) == 0)
    }

    @Test func listsTheOneEndingFirstFirst() {
        let long = Countdown(duration: 600, startingAt: at(0))
        let short = Countdown(duration: 60, startingAt: at(0))
        let ended = Countdown(duration: 10, startingAt: at(-100))
        let list = TimerList(timers: [long, short, ended])
        #expect(list.sorted == [ended, short, long])
    }

    @Test func breaksTiesTheSameWayEverywhere() {
        let a = Countdown(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, duration: 60, endsAt: at(60))
        let b = Countdown(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, duration: 60, endsAt: at(60))
        #expect(TimerList(timers: [b, a]).sorted == [a, b])
    }
}

@Suite("TimerFile")
struct TimerFileTests {
    @Test func writesEndsInUTC() throws {
        let id = UUID(uuidString: "6F1C2D3E-0000-4000-8000-000000000001")!
        let removed = UUID(uuidString: "6F1C2D3E-0000-4000-8000-000000000002")!
        let list = TimerList(
            timers: [Countdown(id: id, duration: 1500, endsAt: Date(timeIntervalSince1970: 1_790_000_000))],
            deleted: [removed: Date(timeIntervalSince1970: 1_790_000_060)])
        let json = String(decoding: try TimerFile.encode(list), as: UTF8.self)
        #expect(json.contains(#""endsAt" : "2026-09-21T14:13:20Z""#))
        #expect(json.contains(#""6F1C2D3E-0000-4000-8000-000000000002" : "2026-09-21T14:14:20Z""#))
        #expect(try TimerFile.decode(Data(json.utf8)) == list)
    }

    @Test func readsAnOffsetAsTheSameInstant() throws {
        let json = #"{"timers": [{"id": "6F1C2D3E-0000-4000-8000-000000000001", "duration": 60, "endsAt": "2026-09-21T23:13:20+09:00"}]}"#
        let list = try TimerFile.decode(Data(json.utf8))
        #expect(list.sorted.first?.endsAt == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func readsAnEmptyFileAsNoTimers() throws {
        #expect(try TimerFile.decode(Data()) == TimerList())
    }
}

@Suite("TimerList.merge")
struct MergeTests {
    let mine = Countdown(duration: 60, startingAt: at(0))
    let theirs = Countdown(duration: 120, startingAt: at(0))

    @Test func keepsTimersAddedOnEitherSide() {
        let merged = TimerList.merge(TimerList(timers: [mine]), TimerList(timers: [theirs]))
        #expect(merged.sorted == [mine, theirs])
    }

    @Test func aRemovalOnEitherSideWins() {
        var removed = TimerList(timers: [mine, theirs])
        removed.remove(mine.id, now: at(10))
        let stale = TimerList(timers: [mine, theirs])
        for merged in [TimerList.merge(removed, stale), TimerList.merge(stale, removed)] {
            #expect(merged.sorted == [theirs])
            #expect(merged.deleted == [mine.id: at(10)])
        }
    }

    @Test func doesNotDependOnOrderOrGrouping() {
        var a = TimerList(timers: [mine])
        a.remove(mine.id, now: at(5))
        let b = TimerList(timers: [mine, theirs])
        let c = TimerList(timers: [Countdown(id: theirs.id, duration: 999, endsAt: at(999))])
        let left = TimerList.merge(TimerList.merge(a, b), c)
        let right = TimerList.merge(a, TimerList.merge(c, b))
        #expect(left == right)
        #expect(TimerList.merge(b, c) == TimerList.merge(c, b))
    }

    @Test func forgetsOldRemovals() {
        var list = TimerList(deleted: [mine.id: at(0), theirs.id: at(TimerList.deletionMemory)])
        list.forgetDeletions(at: at(TimerList.deletionMemory + 1))
        #expect(list.deleted == [theirs.id: at(TimerList.deletionMemory)])
    }
}
