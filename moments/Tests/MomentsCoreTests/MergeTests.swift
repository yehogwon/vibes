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

/// `moment` as a library would save it after `edit`, at `time`.
func edited(_ moment: Moment, at time: TimeInterval, _ edit: (inout Moment) -> Void) -> Moment {
    var library = MomentLibrary()
    library.moments[moment.id] = moment
    var copy = moment
    edit(&copy)
    library.save(copy, now: at(time))
    return library.moments[moment.id]!
}

@Suite("MomentMerge")
struct MergeTests {
    @Test func keepsMomentsAddedOnEitherSide() {
        let mine = moment("mine")
        let theirs = moment("theirs")
        let merged = MomentMerge.merge(set(mine), set(theirs))
        #expect(Set(merged.moments.values.map(\.name)) == ["mine", "theirs"])
    }

    @Test func aMissingMomentIsNotADeletion() {
        let kept = moment("kept")
        #expect(MomentMerge.merge(set(), set(kept)).moments[kept.id] == kept)
    }

    @Test func combinesEditsToDifferentFields() {
        let trip = moment("Trip")
        let mine = edited(trip, at: 10) { $0.emoji = "✈️" }
        let theirs = edited(trip, at: 20) {
            $0.name = "Trip to Jeju"
            $0.inMenubar = true
        }
        for result in [Moment.merged(mine, theirs), Moment.merged(theirs, mine)] {
            #expect(result.name == "Trip to Jeju")
            #expect(result.emoji == "✈️")
            #expect(result.inMenubar)
            #expect(result.updatedAt == at(20))
            #expect(result.stamp(of: "emoji") == at(10))
            #expect(result.stamp(of: "name") == at(20))
            #expect(result.stamp(of: "date") == at(0))
        }
    }

    @Test func theLaterEditWinsAFieldBothChanged() {
        let trip = moment("Trip")
        let mine = edited(trip, at: 30) { $0.name = "Mine" }
        let theirs = edited(trip, at: 20) {
            $0.name = "Theirs"
            $0.colorHex = "FF453A"
        }
        let result = Moment.merged(mine, theirs)
        #expect(result.name == "Mine")
        #expect(result.colorHex == "FF453A")
    }

    @Test func anOlderEditOfAnotherFieldStillSurvives() {
        // The rename happened first, on a Mac that then went quiet; a later emoji change on
        // another Mac doesn't undo it.
        let trip = moment("Trip")
        let renamed = edited(trip, at: 100) { $0.name = "Renamed" }
        let decorated = edited(trip, at: 105) { $0.emoji = "🎒" }
        let result = Moment.merged(decorated, renamed)
        #expect(result.name == "Renamed")
        #expect(result.emoji == "🎒")
    }

    @Test func anEditFromAnAppThatDoesntStampFieldsWinsWhole() {
        // The original app bumps updatedAt without saying which fields changed.
        let trip = moment("Trip")
        let mine = edited(trip, at: 10) { $0.emoji = "✈️" }
        var theirs = trip
        theirs.name = "Renamed elsewhere"
        theirs.updatedAt = at(20)
        let result = Moment.merged(mine, theirs)
        #expect(result == Moment.merged(theirs, mine))
        #expect(result.name == "Renamed elsewhere")
        #expect(result.emoji == "")
    }

    @Test func mergingIsOrderIndependent() {
        let trip = moment("Trip")
        let a = edited(trip, at: 10) { $0.name = "A" }
        let b = edited(trip, at: 10) { $0.name = "B" }
        let c = edited(trip, at: 12) { $0.emoji = "🌊" }
        let ab = Moment.merged(a, b)
        #expect(ab == Moment.merged(b, a))
        #expect(Moment.merged(ab, c) == Moment.merged(a, Moment.merged(b, c)))
        #expect(Moment.merged(ab, ab) == ab)
        // A tie on the same field is broken by value, the same way everywhere.
        #expect(ab.name == "B")
    }

    @Test func aDeletionRemovesEarlierVersions() {
        let doomed = moment("doomed", updated: 10)
        let merged = MomentMerge.merge(set(deleted: [doomed.id: at(11)]), set(doomed))
        #expect(merged.moments[doomed.id] == nil)
        #expect(merged.deleted[doomed.id] == at(11))
    }

    @Test func anEditAfterTheDeletionBringsTheMomentBack() {
        let revived = moment("revived", updated: 20)
        let merged = MomentMerge.merge(set(deleted: [revived.id: at(11)]), set(revived))
        #expect(merged.moments[revived.id] == revived)
    }

    @Test func keepsTheLaterOfTwoDeletions() {
        let id = UUID()
        let merged = MomentMerge.merge(set(deleted: [id: at(5)]), set(deleted: [id: at(9)]))
        #expect(merged.deleted[id] == at(9))
    }

    @Test func unknownKeysComeFromTheNewerVersion() {
        var older = moment("x", updated: 5)
        older.extras = ["a": .integer(1)]
        var newer = older
        newer.extras = ["a": .integer(2), "b": .string("new")]
        newer.updatedAt = at(9)
        #expect(Moment.merged(older, newer).extras == newer.extras)
    }
}

@Suite("MomentLibrary")
struct LibraryTests {
    @Test func stampsEditsAfterTheVersionTheyReplace() {
        // Another Mac's clock is an hour ahead; an edit made here after seeing its version must
        // still count as newer.
        let ahead = moment("from the future", updated: 3600)
        let result = edited(ahead, at: 0) { $0.name = "edited here" }
        #expect(result.updatedAt == at(3601))
        #expect(result.stamp(of: "name") == at(3601))
    }

    @Test func savingUnchangedContentDoesNothing() {
        var library = MomentLibrary()
        let original = moment("same", updated: 5)
        library.moments[original.id] = original
        var copy = original
        copy.updatedAt = at(100)
        library.save(copy, now: at(100))
        #expect(library.moments[original.id] == original)
    }

    @Test func savesOnlyWhatTheEditorChanged() {
        // While the editor was open, a rename arrived from another Mac.
        var library = MomentLibrary()
        let original = moment("Trip")
        library.moments[original.id] = edited(original, at: 10) { $0.name = "Renamed elsewhere" }

        var draft = original
        draft.emoji = "🎒"
        library.save(draft, from: original, now: at(20))
        let saved = library.moments[original.id]
        #expect(saved?.name == "Renamed elsewhere")
        #expect(saved?.emoji == "🎒")
        #expect(saved?.stamp(of: "name") == at(10))
    }

    @Test func aFirstEditKeepsTheOriginalAppsTimesForOtherFields() {
        // Written by the original app: no per-field times.
        let fromFile = moment("Trip", updated: 50)
        let result = edited(fromFile, at: 60) { $0.emoji = "🎒" }
        #expect(result.stamp(of: "emoji") == at(60))
        #expect(result.stamp(of: "name") == at(50))
        #expect(result.fieldUpdatedAt.keys.count > 1)
    }

    @Test func deletingRecordsWhen() {
        var library = MomentLibrary()
        let doomed = moment("doomed", updated: 50)
        library.moments[doomed.id] = doomed
        library.delete(doomed.id, now: at(10))
        #expect(library.moments.isEmpty)
        #expect(library.deleted[doomed.id] == at(51))
    }

    @Test func savingADeletedMomentBringsItBack() {
        var library = MomentLibrary()
        let doomed = moment("doomed", updated: 50)
        library.moments[doomed.id] = doomed
        library.delete(doomed.id, now: at(60))
        library.save(doomed, now: at(10))
        let merged = MomentMerge.merge(library.set, set(deleted: library.deleted))
        #expect(merged.moments[doomed.id] != nil)
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
        #expect(library.moments[c.id]?.stamp(of: "sortWeight") == at(100))
        #expect(library.moments[c.id]?.stamp(of: "name") == at(0))
        #expect(library.nextSortWeight == 3)
    }

    @Test func integratingKeepsEditsMadeDuringASync() {
        var snapshot = MomentLibrary()
        let shared = moment("shared")
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
        result.moments[shared.id] = edited(shared, at: 5) { $0.colorHex = "32D74B" }
        let arrived = moment("from the other Mac", updated: 5)
        result.moments[arrived.id] = arrived
        result.backedUpFolder = "/folder"

        let integrated = current.integrating(result)
        #expect(integrated.moments[shared.id]?.name == "renamed here")
        #expect(integrated.moments[shared.id]?.colorHex == "32D74B")
        #expect(integrated.moments[added.id] != nil)
        #expect(integrated.moments[arrived.id] != nil)
        #expect(integrated.backedUpFolder == "/folder")
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
        let first = moment("a", updated: 1)
        library.save(first, now: at(1))
        library.save(edited(first, at: 5) { $0.emoji = "🎈" }, now: at(5))
        library.deleted[UUID()] = at(3)
        library.backedUpFolder = "/tmp/folder"
        let data = try MomentFile.encoder.encode(library)
        #expect(try JSONDecoder().decode(MomentLibrary.self, from: data) == library)
    }
}
