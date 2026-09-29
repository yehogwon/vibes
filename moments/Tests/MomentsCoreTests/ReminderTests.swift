import Foundation
import Testing

@testable import MomentsCore

@Suite("Reminders")
struct ReminderTests {
    let seoul = TestCalendar()

    func moment(on year: Int, _ month: Int, _ day: Int, remind days: Int, repeating: Moment.RepeatCycle = .none)
        -> Moment
    {
        var moment = seoul.moment(on: year, month, day, repeating: repeating)
        moment.remindDays = days
        return moment
    }

    @Test func remindsTheChosenNumberOfDaysBefore() {
        let reminder = moment(on: 2026, 10, 10, remind: 3).nextReminder(
            after: seoul.date(2026, 9, 28), calendar: seoul.calendar)
        #expect(reminder?.fire == seoul.date(2026, 10, 7, 9))
        #expect(reminder?.day == seoul.date(2026, 10, 10))
    }

    @Test func remindsOnTheDayItself() {
        let reminder = moment(on: 2026, 10, 10, remind: 0).nextReminder(
            after: seoul.date(2026, 10, 10, 8), calendar: seoul.calendar)
        #expect(reminder?.fire == seoul.date(2026, 10, 10, 9))
    }

    @Test func aPassedReminderForAOneOffDayIsGone() {
        let late = seoul.date(2026, 10, 8)
        #expect(moment(on: 2026, 10, 10, remind: 3).nextReminder(after: late, calendar: seoul.calendar) == nil)
        #expect(moment(on: 2026, 9, 1, remind: 0).nextReminder(after: late, calendar: seoul.calendar) == nil)
    }

    @Test func aRepeatingDayRemindsAgainNextTime() {
        let reminder = moment(on: 2020, 10, 10, remind: 3, repeating: .year).nextReminder(
            after: seoul.date(2026, 10, 8), calendar: seoul.calendar)
        #expect(reminder?.fire == seoul.date(2027, 10, 7, 9))
        #expect(reminder?.day == seoul.date(2027, 10, 10))
    }

    @Test func birthdaysRemindEveryYear() {
        var birthday = seoul.moment(.life, on: 1995, 10, 10)
        birthday.remindDays = 1
        let reminder = birthday.nextReminder(after: seoul.date(2026, 10, 9, 10), calendar: seoul.calendar)
        #expect(reminder?.fire == seoul.date(2027, 10, 9, 9))
    }

    @Test func weeklyMomentsWithLongNotice() {
        // Every Tuesday, two weeks ahead: the reminder today is for the Tuesday after next.
        let weekly = moment(on: 2026, 9, 1, remind: 14, repeating: .week)
        let reminder = weekly.nextReminder(after: seoul.date(2026, 9, 28), calendar: seoul.calendar)
        #expect(reminder?.fire == seoul.date(2026, 9, 29, 9))
        #expect(reminder?.day == seoul.date(2026, 10, 13))
    }

    @Test func aWeekAheadOnTheDayItselfAfterTheReminderFired() {
        // Tuesday, 10 am: today's reminder (for next Tuesday) has fired; next is the week after.
        let weekly = moment(on: 2026, 9, 1, remind: 7, repeating: .week)
        let reminder = weekly.nextReminder(after: seoul.date(2026, 9, 29, 10), calendar: seoul.calendar)
        #expect(reminder?.fire == seoul.date(2026, 10, 6, 9))
        #expect(reminder?.day == seoul.date(2026, 10, 13))
    }

    @Test func monthlyMomentsAMonthAheadAroundFebruary() {
        let monthly = moment(on: 2026, 1, 15, remind: 30, repeating: .month)
        let reminder = monthly.nextReminder(after: seoul.date(2026, 1, 20), calendar: seoul.calendar)
        #expect(reminder?.day == seoul.date(2026, 3, 15))
        #expect(reminder?.fire == seoul.date(2026, 2, 13, 9))
    }

    @Test func noReminderMeansNone() {
        #expect(moment(on: 2026, 10, 10, remind: -1).nextReminder(after: seoul.date(2026, 9, 1)) == nil)
        var progress = Moment(kind: .progress, date: .now, createdAt: .now)
        progress.remindDays = 1
        #expect(progress.nextReminder(after: .now) == nil)
    }
}
