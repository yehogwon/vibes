import Foundation
import Testing

@testable import MomentsCore

/// A calendar and dates in one time zone, so the tests don't depend on the machine's.
struct TestCalendar {
    var calendar: Calendar

    init(_ zone: String = "Asia/Seoul") {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func moment(
        _ kind: Moment.Kind = .date, on year: Int, _ month: Int, _ day: Int, repeating cycle: Moment.RepeatCycle = .none,
        unit: Moment.Unit = .day
    ) -> Moment {
        let date = date(year, month, day)
        return Moment(kind: kind, date: date, unit: unit, repeatCycle: cycle, createdAt: date)
    }
}

@Suite("Countdown")
struct CountdownTests {
    let seoul = TestCalendar()

    @Test func countsDownToAFutureDay() {
        let count = seoul.moment(on: 2026, 10, 10).dayCount(on: seoul.date(2026, 9, 28, 23, 30), calendar: seoul.calendar)
        #expect(count.days == 12)
        #expect(count.target == seoul.date(2026, 10, 10))
        #expect(count.occurrence == nil)
    }

    @Test func isZeroAllOfTheDay() {
        let moment = seoul.moment(on: 2026, 9, 28)
        #expect(moment.dayCount(on: seoul.date(2026, 9, 28, 0, 0), calendar: seoul.calendar).days == 0)
        #expect(moment.dayCount(on: seoul.date(2026, 9, 28, 23, 59), calendar: seoul.calendar).days == 0)
    }

    @Test func countsUpFromAPastDay() {
        let count = seoul.moment(on: 2026, 8, 25).dayCount(on: seoul.date(2026, 9, 28), calendar: seoul.calendar)
        #expect(count.days == -34)
    }

    @Test func readsTheDayWhereItWasPicked() {
        // The original app stores midnight in Seoul as the previous day in UTC.
        let moment = Moment(date: ISODate.parse("2030-09-17T15:00:00Z")!, createdAt: .now)
        #expect(moment.dayCount(on: seoul.date(2030, 9, 18, 12), calendar: seoul.calendar).days == 0)
    }

    @Test func countsWholeDaysAcrossDaylightSaving() {
        let newYork = TestCalendar("America/New_York")
        // Clocks go forward on March 8, 2026, so that day is 23 hours long.
        let moment = newYork.moment(on: 2026, 3, 10)
        #expect(moment.dayCount(on: newYork.date(2026, 3, 7, 12), calendar: newYork.calendar).days == 3)
    }

    @Test func yearlyMomentsCountToTheNextAnniversary() {
        let anniversary = seoul.moment(on: 2020, 10, 10, repeating: .year)
        let before = anniversary.dayCount(on: seoul.date(2026, 9, 28), calendar: seoul.calendar)
        #expect(before.target == seoul.date(2026, 10, 10))
        #expect(before.days == 12)
        #expect(before.occurrence == 6)

        let onTheDay = anniversary.dayCount(on: seoul.date(2026, 10, 10, 18), calendar: seoul.calendar)
        #expect(onTheDay.days == 0)
        #expect(onTheDay.occurrence == 6)

        let after = anniversary.dayCount(on: seoul.date(2026, 10, 11), calendar: seoul.calendar)
        #expect(after.target == seoul.date(2027, 10, 10))
        #expect(after.occurrence == 7)
    }

    @Test func aRepeatingMomentCountsDownToItsFirstDay() {
        let count = seoul.moment(on: 2026, 12, 25, repeating: .year).dayCount(
            on: seoul.date(2026, 12, 1), calendar: seoul.calendar)
        #expect(count.days == 24)
        #expect(count.occurrence == 0)
    }

    @Test func monthlyMomentsOnThe31stUseTheLastDayOfShorterMonths() {
        let payday = seoul.moment(on: 2026, 1, 31, repeating: .month)
        #expect(payday.dayCount(on: seoul.date(2026, 2, 10), calendar: seoul.calendar).target == seoul.date(2026, 2, 28))
        #expect(payday.dayCount(on: seoul.date(2026, 3, 1), calendar: seoul.calendar).target == seoul.date(2026, 3, 31))
        #expect(payday.dayCount(on: seoul.date(2026, 4, 5), calendar: seoul.calendar).target == seoul.date(2026, 4, 30))
    }

    @Test func leapDaysFallOnFebruary28thInOtherYears() {
        let leap = seoul.moment(on: 2024, 2, 29, repeating: .year)
        #expect(leap.dayCount(on: seoul.date(2026, 2, 1), calendar: seoul.calendar).target == seoul.date(2026, 2, 28))
        #expect(leap.dayCount(on: seoul.date(2027, 12, 1), calendar: seoul.calendar).target == seoul.date(2028, 2, 29))
    }

    @Test func weeklyMomentsComeRoundEverySevenDays() {
        let weekly = seoul.moment(on: 2026, 9, 1, repeating: .week)  // a Tuesday
        let count = weekly.dayCount(on: seoul.date(2026, 9, 28), calendar: seoul.calendar)  // a Monday
        #expect(count.target == seoul.date(2026, 9, 29))
        #expect(count.days == 1)
        #expect(count.occurrence == 4)
    }

    @Test func acceptsOtherSpellingsOfRepeatCycles() {
        let yearly = Moment.RepeatCycle(rawValue: "yearly")
        #expect(yearly.step?.component == .year)
        #expect(Moment.RepeatCycle(rawValue: "sometimes").step == nil)
    }

    @Test func birthdaysCountTheAge() {
        let birthday = seoul.moment(.life, on: 1995, 10, 10)
        let now = seoul.date(2026, 9, 28)
        #expect(birthday.age(on: now, calendar: seoul.calendar) == 30)
        let next = birthday.dayCount(on: now, calendar: seoul.calendar)
        #expect(next.days == 12)
        #expect(next.occurrence == 31)
        #expect(birthday.age(on: seoul.date(2026, 10, 10), calendar: seoul.calendar) == 31)
    }

    @Test func breaksDownDistancesByUnit() {
        let from = seoul.date(2025, 7, 1)
        let to = seoul.date(2026, 9, 4)
        let calendar = seoul.calendar
        #expect(Breakdown(from: from, to: to, unit: .day, calendar: calendar) == Breakdown(days: 430))
        #expect(Breakdown(from: from, to: to, unit: .week, calendar: calendar) == Breakdown(weeks: 61, days: 3))
        #expect(Breakdown(from: from, to: to, unit: .month, calendar: calendar) == Breakdown(months: 14, days: 3))
        #expect(Breakdown(from: to, to: from, unit: .year, calendar: calendar) == Breakdown(years: 1, months: 2, days: 3))
        #expect(Breakdown(years: 1, months: 2, days: 3).description == "1 year 2 months 3 days")
        #expect(Breakdown(weeks: 1).description == "1 week")
        #expect(Breakdown().description == "0 days")
    }

    @Test func summarizesCountdowns() {
        let now = seoul.date(2026, 9, 28, 9)
        let calendar = seoul.calendar
        #expect(
            seoul.moment(on: 2026, 10, 10).summary(on: now, calendar: calendar)
                == CountSummary(headline: "D-12", caption: "12 days left"))
        #expect(
            seoul.moment(on: 2026, 9, 28).summary(on: now, calendar: calendar)
                == CountSummary(headline: "D-Day", caption: "Today"))
        #expect(
            seoul.moment(on: 2026, 8, 25, unit: .month).summary(on: now, calendar: calendar)
                == CountSummary(headline: "D+34", caption: "1 month 3 days ago"))
        #expect(
            seoul.moment(.life, on: 1995, 10, 10).summary(on: now, calendar: calendar)
                == CountSummary(headline: "30", caption: "years old"))
    }
}

@Suite("SpanProgress")
struct SpanProgressTests {
    let seoul = TestCalendar()

    func progress(_ span: Moment.Span, at now: Date) -> SpanProgress {
        Moment(kind: .progress, date: now, span: span, createdAt: now).progress(at: now, calendar: seoul.calendar)
    }

    @Test func measuresTheYear() {
        let progress = progress(.year, at: seoul.date(2026, 7, 2, 12))
        #expect(progress.interval == DateInterval(start: seoul.date(2026, 1, 1), end: seoul.date(2027, 1, 1)))
        #expect(abs(progress.fraction - 0.5) < 0.001)
        #expect(progress.percent == "50%")
        #expect(progress.detail == "Day 183 of 365")
    }

    @Test func measuresQuarters() {
        let interval = progress(.quarter, at: seoul.date(2026, 8, 15)).interval
        #expect(interval == DateInterval(start: seoul.date(2026, 7, 1), end: seoul.date(2026, 10, 1)))
        #expect(progress(.quarter, at: seoul.date(2026, 12, 31)).interval.start == seoul.date(2026, 10, 1))
    }

    @Test func measuresTheDayInHoursLeft() {
        let progress = progress(.day, at: seoul.date(2026, 9, 28, 14, 36))
        #expect(progress.detail == "9h 24m left")
        #expect(progress.percent == "60%")
    }

    @Test func measuresTheWeekByTheCalendarsFirstWeekday() {
        var calendar = seoul.calendar
        calendar.firstWeekday = 2  // Monday
        let now = seoul.date(2026, 9, 30)  // a Wednesday
        let moment = Moment(kind: .progress, date: now, span: .week, createdAt: now)
        #expect(moment.progress(at: now, calendar: calendar).detail == "Day 3 of 7")
    }

    @Test func measuresCustomSpans() {
        let start = seoul.date(2025, 8, 3)
        let end = seoul.date(2027, 8, 13)
        let moment = Moment(
            kind: .progress, date: start, startDate: start, endDate: end, span: .custom, createdAt: start)
        let calendar = seoul.calendar
        #expect(moment.progress(at: seoul.date(2025, 8, 1), calendar: calendar).detail == "Starts in 2 days")
        #expect(moment.progress(at: seoul.date(2025, 8, 1), calendar: calendar).fraction == 0)
        #expect(moment.progress(at: seoul.date(2025, 8, 3, 8), calendar: calendar).detail == "Day 1 of 740")
        #expect(moment.progress(at: seoul.date(2027, 8, 13), calendar: calendar).detail == "Ended")
        #expect(moment.progress(at: seoul.date(2027, 8, 13), calendar: calendar).fraction == 1)
    }

    @Test func namesUnnamedProgressBars() {
        let now = Date.now
        #expect(Moment(kind: .progress, date: now, span: .month, createdAt: now).displayName == "This Month")
        #expect(Moment(kind: .progress, name: " Thesis ", date: now, createdAt: now).displayName == "Thesis")
    }
}
