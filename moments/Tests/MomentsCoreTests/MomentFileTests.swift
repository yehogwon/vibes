import Foundation
import Testing

@testable import MomentsCore

@Suite("MomentFile")
struct MomentFileTests {
    /// Two moments written the way the original Moment writes `moments.json`: pretty-printed,
    /// sorted keys, "key" : value, escaped slashes, no trailing newline. The second has a photo
    /// and a key this version doesn't know.
    static let original = #"""
        [
          {
            "color" : {
              "hex" : "5E5CE6"
            },
            "createdAt" : "2026-08-24T04:23:26Z",
            "date" : "2026-08-24T04:23:26Z",
            "emoji" : "",
            "endDate" : "2026-08-24T04:23:26Z",
            "id" : "CAFE3877-9504-46F3-9804-3E0A241BD308",
            "inMenubar" : false,
            "kind" : "progress",
            "name" : "",
            "remindDays" : -1,
            "repeatCycle" : "none",
            "sortWeight" : 0,
            "span" : "year",
            "startDate" : "2026-08-24T04:23:26Z",
            "unit" : "day",
            "updatedAt" : "2026-08-24T04:23:26Z"
          },
          {
            "color" : {
              "hex" : ""
            },
            "createdAt" : "2026-08-24T05:21:15Z",
            "date" : "2030-09-17T15:00:00Z",
            "emoji" : "🎓",
            "endDate" : "2026-08-24T05:21:15Z",
            "id" : "0501D8DF-186C-4EA0-A659-CF1E0D851148",
            "imageData" : "iVBOR\/\/+\/Q==",
            "inMenubar" : true,
            "kind" : "date",
            "name" : "Graduation",
            "remindDays" : 3,
            "repeatCycle" : "none",
            "sortWeight" : 1,
            "span" : "year",
            "startDate" : "2026-08-24T05:21:15Z",
            "thumbnail" : {
              "size" : 64
            },
            "unit" : "month",
            "updatedAt" : "2026-09-01T10:00:00Z"
          }
        ]
        """#

    @Test func readsTheOriginalFormat() throws {
        let list = try MomentFile.decode(Data(Self.original.utf8))
        #expect(list.unreadable.isEmpty)
        #expect(list.moments.count == 2)

        let progress = list.moments[0]
        #expect(progress.kind == .progress)
        #expect(progress.span == .year)
        #expect(progress.colorHex == "5E5CE6")
        #expect(progress.imageData == nil)
        #expect(progress.remindDays == -1)

        let graduation = list.moments[1]
        #expect(graduation.kind == .date)
        #expect(graduation.name == "Graduation")
        #expect(graduation.emoji == "🎓")
        #expect(graduation.imageData == Data([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFE, 0xFD]))
        #expect(graduation.inMenubar)
        #expect(graduation.unit == .month)
        #expect(graduation.remindDays == 3)
        #expect(graduation.date == ISODate.parse("2030-09-17T15:00:00Z"))
        #expect(graduation.extras == ["thumbnail": .object(["size": .integer(64)])])
    }

    @Test func writesItBackByteForByte() throws {
        let data = Data(Self.original.utf8)
        let rewritten = try MomentFile.encode(MomentFile.decode(data))
        #expect(String(decoding: rewritten, as: UTF8.self) == Self.original)
    }

    /// Checks a real file, e.g. the one in iCloud Drive, without committing it:
    /// `MOMENTS_ROUNDTRIP_FILE=path swift test --filter roundTripsARealFile`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MOMENTS_ROUNDTRIP_FILE"] != nil))
    func roundTripsARealFile() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MOMENTS_ROUNDTRIP_FILE"] ?? "")
        let data = try Data(contentsOf: url)
        let list = try MomentFile.decode(data)
        #expect(list.unreadable.isEmpty)
        #expect(try MomentFile.encode(list) == data)
    }

    @Test func keepsEntriesItCantRead() throws {
        let json = #"[{"name" : "no id"}, {"id" : "0501D8DF-186C-4EA0-A659-CF1E0D851148"}]"#
        let list = try MomentFile.decode(Data(json.utf8))
        #expect(list.moments.map(\.id.uuidString) == ["0501D8DF-186C-4EA0-A659-CF1E0D851148"])
        #expect(list.unreadable == [.object(["name": .string("no id")])])
        let again = try MomentFile.decode(MomentFile.encode(list))
        #expect(again.unreadable == list.unreadable)
    }

    @Test func fillsInMissingFields() throws {
        let json = #"[{"id" : "0501D8DF-186C-4EA0-A659-CF1E0D851148", "date" : "2026-01-02T03:04:05.678Z"}]"#
        let moment = try #require(try MomentFile.decode(Data(json.utf8)).moments.first)
        #expect(moment.kind == .date)
        #expect(moment.repeatCycle == .none)
        #expect(moment.remindDays == -1)
        #expect(moment.date == ISODate.parse("2026-01-02T03:04:05Z"))
        #expect(moment.startDate == moment.date)
        #expect(moment.createdAt == Date(timeIntervalSince1970: 0))
    }

    @Test func rejectsAFileThatIsntAList() {
        #expect(throws: (any Error).self) { try MomentFile.decode(Data(#"{"moments": []}"#.utf8)) }
        #expect(throws: (any Error).self) { try MomentFile.decode(Data("not json".utf8)) }
    }

    @Test func readsAnEmptyFileAsNoMoments() throws {
        #expect(try MomentFile.decode(Data()) == MomentList())
    }

    @Test func writesInListOrder() throws {
        let now = ISODate.parse("2026-09-01T00:00:00Z")!
        let first = Moment(name: "first", date: now, sortWeight: 0, createdAt: now)
        let second = Moment(name: "second", date: now, sortWeight: 1, createdAt: now)
        let list = try MomentFile.decode(MomentFile.encode(MomentList(moments: [second, first])))
        #expect(list.moments.map(\.name) == ["first", "second"])
    }

    @Test func roundTripsDeletions() throws {
        let id = UUID()
        let date = ISODate.parse("2026-09-01T12:00:00Z")!
        let data = try MomentFile.encodeDeletions([id: date])
        #expect(try MomentFile.decodeDeletions(data) == [id: date])
        #expect(try MomentFile.decodeDeletions(Data()) == [:])
    }

    @Test func dropsFractionsOfASecond() {
        let date = Date(timeIntervalSince1970: 1000.75)
        let moment = Moment(date: date, createdAt: date)
        #expect(moment.date.timeIntervalSince1970 == 1000)
        #expect(moment.updatedAt.timeIntervalSince1970 == 1000)
    }
}
