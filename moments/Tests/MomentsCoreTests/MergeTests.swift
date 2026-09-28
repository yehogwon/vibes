import Foundation
import Testing

@testable import MomentsCore

/// Seconds after a fixed start, to keep the arithmetic readable.
func at(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_790_000_000 + seconds)
}

func moment(_ name: String, updated: TimeInterval = 0, id: UUID = UUID()) -> Moment {
    Moment(id: id, name: name, date: at(0), createdAt: at(0), updatedAt: at(updated))
}

func set(_ moments: Moment..., deleted: [UUID: Date] = [:]) -> MomentSet {
    MomentSet(moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }), deleted: deleted)
}

@Suite("MomentMerge")
struct MergeTests {
    @Test func keepsMomentsAddedOnEitherSide() {
        let mine = moment("mine")
        let theirs = moment("theirs")
        let merged = MomentMerge.merge(set(mine), set(theirs), base: [:])
        #expect(Set(merged.moments.values.map(\.name)) == ["mine", "theirs"])
    }

    @Test func aMissingMomentIsNotADeletion() {
        let base = moment("kept")
        let merged = MomentMerge.merge(set(), set(base), base: [base.id: base])
        #expect(merged.moments[base.id] == base)
    }

    @Test func combinesEditsToDifferentFields() {
        let base = moment("Trip", updated: 0)
        var mine = base
        mine.emoji = "✈️"
        mine.updatedAt = at(10)
        var theirs = base
        theirs.name = "Trip to Jeju"
        theirs.inMenubar = true
        theirs.updatedAt = at(20)

        for merged in [
            MomentMerge.merge(set(mine), set(theirs), base: [base.id: base]),
            MomentMerge.merge(set(theirs), set(mine), base: [base.id: base]),
        ] {
            let result = merged.moments[base.id]
            #expect(result?.name == "Trip to Jeju")
            #expect(result?.emoji == "✈️")
            #expect(result?.inMenubar == true)
            #expect(result?.updatedAt == at(20))
        }
    }

    @Test func theNewerEditWinsAFieldBothChanged() {
        let base = moment("Trip", updated: 0)
        var mine = base
        mine.name = "Mine"
        mine.updatedAt = at(30)
        var theirs = base
        theirs.name = "Theirs"
        theirs.colorHex = "FF453A"
        theirs.updatedAt = at(20)

        let result = MomentMerge.merge(set(mine), set(theirs), base: [base.id: base]).moments[base.id]
        #expect(result?.name == "Mine")
        #expect(result?.colorHex == "FF453A")
    }

    @Test func withoutABaseTheNewerVersionWinsWhole() {
        let id = UUID()
        var older = moment("older", updated: 5, id: id)
        older.emoji = "🐢"
        let newer = moment("newer", updated: 9, id: id)
        let result = MomentMerge.merge(set(older), set(newer), base: [:]).moments[id]
        #expect(result == newer)
    }

    @Test func tiesAreBrokenTheSameWayOnEveryMac() {
        let id = UUID()
        let a = moment("a", updated: 5, id: id)
        let b = moment("b", updated: 5, id: id)
        let one = MomentMerge.merge(set(a), set(b), base: [:])
        let other = MomentMerge.merge(set(b), set(a), base: [:])
        #expect(one == other)
    }

    @Test func ignoresAStaleCopy() {
        // This Mac synced "Current"; an old conflict version still says "Old".
        let id = UUID()
        let current = moment("Current", updated: 50, id: id)
        let stale = moment("Old", updated: 10, id: id)
        let result = MomentMerge.merge(set(current), set(stale), base: [id: current]).moments[id]
        #expect(result == current)
    }

    @Test func takesTheOtherSidesEditWhenThisSideDidntChange() {
        let base = moment("Before", updated: 10)
        var theirs = base
        theirs.name = "After"
        theirs.updatedAt = at(20)
        let result = MomentMerge.merge(set(base), set(theirs), base: [base.id: base]).moments[base.id]
        #expect(result?.name == "After")
    }

    @Test func aDeletionRemovesEarlierVersions() {
        let doomed = moment("doomed", updated: 10)
        let merged = MomentMerge.merge(set(), set(doomed), base: [:])
        #expect(merged.moments[doomed.id] != nil)

        let deleted = MomentMerge.merge(set(deleted: [doomed.id: at(11)]), set(doomed), base: [:])
        #expect(deleted.moments[doomed.id] == nil)
        #expect(deleted.deleted[doomed.id] == at(11))
    }

    @Test func anEditAfterTheDeletionBringsTheMomentBack() {
        let revived = moment("revived", updated: 20)
        let merged = MomentMerge.merge(set(deleted: [revived.id: at(11)]), set(revived), base: [:])
        #expect(merged.moments[revived.id] == revived)
    }

    @Test func keepsTheLaterOfTwoDeletions() {
        let id = UUID()
        let merged = MomentMerge.merge(set(deleted: [id: at(5)]), set(deleted: [id: at(9)]), base: [:])
        #expect(merged.deleted[id] == at(9))
    }

    @Test func combinesUnknownKeysLikeFields() {
        var base = moment("x")
        base.extras = ["a": .integer(1)]
        var mine = base
        mine.extras["a"] = .integer(2)
        mine.updatedAt = at(10)
        var theirs = base
        theirs.extras["b"] = .string("new")
        theirs.updatedAt = at(20)
        let result = MomentMerge.merge(set(mine), set(theirs), base: [base.id: base]).moments[base.id]
        #expect(result?.extras == ["a": .integer(2), "b": .string("new")])
    }
}

@Suite("MomentLibrary")
struct LibraryTests {
    @Test func stampsEditsAfterTheVersionTheyReplace() {
        // Another Mac's clock is an hour ahead; an edit made here after seeing its version must
        // still count as newer.
        var library = MomentLibrary()
        let ahead = moment("from the future", updated: 3600)
        library.moments[ahead.id] = ahead
        var edited = ahead
        edited.name = "edited here"
        library.save(edited, now: at(0))
        #expect(library.moments[ahead.id]?.updatedAt == at(3601))
    }

    @Test func savingUnchangedContentDoesNothing() {
        var library = MomentLibrary()
        let original = moment("same", updated: 5)
        library.moments[original.id] = original
        var copy = original
        copy.updatedAt = at(100)
        library.save(copy, now: at(100))
        #expect(library.moments[original.id]?.updatedAt == at(5))
    }

    @Test func deletingRecordsWhen() {
        var library = MomentLibrary()
        let doomed = moment("doomed", updated: 50)
        library.moments[doomed.id] = doomed
        library.delete(doomed.id, now: at(10))
        #expect(library.moments.isEmpty)
        #expect(library.deleted[doomed.id] == at(51))
    }

    @Test func reorderingRenumbersOnlyWhatMoved() {
        var library = MomentLibrary()
        var a = moment("a"), b = moment("b"), c = moment("c")
        (a.sortWeight, b.sortWeight, c.sortWeight) = (0, 1, 2)
        for item in [a, b, c] {
            library.moments[item.id] = item
        }
        library.reorder([a.id, c.id, b.id], now: at(100))
        #expect(library.sortedMoments.map(\.name) == ["a", "c", "b"])
        #expect(library.moments[a.id]?.updatedAt == at(0))
        #expect(library.moments[c.id]?.updatedAt == at(100))
        #expect(library.nextSortWeight == 3)
    }

    @Test func integratingKeepsEditsMadeDuringASync() {
        var snapshot = MomentLibrary()
        let shared = moment("shared", updated: 0)
        snapshot.moments[shared.id] = shared

        // While syncing, this Mac renamed the moment and added another...
        var current = snapshot
        var renamed = shared
        renamed.name = "renamed here"
        current.save(renamed, now: at(10))
        let added = moment("added here", updated: 10)
        current.save(added, now: at(10))

        // ...and the sync brought in another Mac's new color and a new moment.
        var result = snapshot
        var recolored = shared
        recolored.colorHex = "32D74B"
        recolored.updatedAt = at(5)
        result.moments[shared.id] = recolored
        let arrived = moment("from the other Mac", updated: 5)
        result.moments[arrived.id] = arrived
        result.synced = result.moments

        let integrated = current.integrating(result, from: snapshot)
        #expect(integrated.moments[shared.id]?.name == "renamed here")
        #expect(integrated.moments[shared.id]?.colorHex == "32D74B")
        #expect(integrated.moments[added.id] != nil)
        #expect(integrated.moments[arrived.id] != nil)
        #expect(integrated.synced == result.synced)
    }

    @Test func forgetsOldDeletions() {
        var library = MomentLibrary()
        let old = UUID(), recent = UUID()
        library.deleted = [old: at(0), recent: at(1000)]
        library.forgetDeletions(before: at(500))
        #expect(library.deleted == [recent: at(1000)])
    }

    @Test func roundTripsThroughJSON() throws {
        var library = MomentLibrary()
        library.save(moment("a", updated: 1), now: at(1))
        library.delete(UUID(), now: at(2))
        library.deleted[UUID()] = at(3)
        library.synced = library.moments
        library.syncedFolder = "/tmp/folder"
        library.backedUp = true
        let data = try MomentFile.encoder.encode(library)
        #expect(try JSONDecoder().decode(MomentLibrary.self, from: data) == library)
    }
}
