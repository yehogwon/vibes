import Foundation
import Testing

@testable import MomentsCore

@Suite("NewMoment")
struct NewMomentTests {
    let seoul = TestCalendar()

    @Test func aDayOrBirthdayStartsOnToday() {
        let now = seoul.date(2026, 10, 1, 15, 30)
        for kind in [Moment.Kind.date, .life] {
            let moment = Moment(new: kind, at: now, sortWeight: 3, calendar: seoul.calendar)
            #expect(moment.kind == kind)
            #expect(moment.date == seoul.date(2026, 10, 1))
            #expect(moment.startDate == seoul.date(2026, 10, 1))
            #expect(moment.endDate == seoul.date(2026, 10, 1))
            #expect(moment.sortWeight == 3)
            #expect(moment.createdAt == now)
        }
    }

    @Test func aProgressBarRunsThroughTheYearWithCustomDatesAMonthLong() {
        let now = seoul.date(2026, 10, 1, 15, 30)
        let moment = Moment(new: .progress, at: now, calendar: seoul.calendar)
        #expect(moment.span == .year)
        #expect(moment.date == now)
        #expect(moment.startDate == seoul.date(2026, 10, 1))
        #expect(moment.endDate == seoul.date(2026, 11, 1))
    }

    @Test func switchingKindKeepsWhatEveryKindHas() {
        var moment = Moment(new: .date, at: seoul.date(2026, 10, 1, 15, 30), sortWeight: 2, calendar: seoul.calendar)
        moment.name = "Mom"
        moment.emoji = "🎂"
        moment.imageData = Data([1, 2, 3])
        moment.colorHex = "FF2D55"
        moment.inMenubar = true
        moment.date = seoul.date(1968, 5, 8)
        moment.repeatCycle = .year
        moment.unit = .month
        moment.remindDays = 7
        let id = moment.id

        moment.switchKind(to: .life, calendar: seoul.calendar)

        var expected = Moment(new: .life, at: seoul.date(2026, 10, 1, 15, 30), sortWeight: 2, calendar: seoul.calendar)
        expected.id = id
        expected.name = "Mom"
        expected.emoji = "🎂"
        expected.imageData = Data([1, 2, 3])
        expected.colorHex = "FF2D55"
        expected.inMenubar = true
        #expect(moment == expected)
    }

    @Test func switchingBackStartsTheKindOver() {
        // Part of a second in, which the moment drops.
        let now = seoul.date(2026, 10, 1, 15, 30).addingTimeInterval(42.5)
        let fresh = Moment(new: .progress, at: now, calendar: seoul.calendar)
        var moment = fresh
        moment.span = .custom
        moment.endDate = seoul.date(2026, 12, 24)

        moment.switchKind(to: .date, calendar: seoul.calendar)
        #expect(moment.date == seoul.date(2026, 10, 1))
        moment.switchKind(to: .progress, calendar: seoul.calendar)
        #expect(moment == fresh)
    }
}
