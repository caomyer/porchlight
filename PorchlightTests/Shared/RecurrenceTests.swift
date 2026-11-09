import Foundation
import Testing
@testable import Porchlight

@Suite("Repeat rules shared by chores and routines")
struct RecurrenceTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func day(_ raw: String) -> DayKey { DayKey(rawValue: raw) }

    @Test("Nothing repeats before its start day")
    func startDay() {
        let start = day("2026-11-10")
        for rule in [Recurrence.daily, .weekdays([1, 2, 3, 4, 5, 6, 7]), .everyNDays(2), .monthly] {
            #expect(!rule.occurs(on: day("2026-11-09"), start: start, calendar: calendar))
            #expect(rule.occurs(on: start, start: start, calendar: calendar))
        }
    }

    @Test("Monthly lands on the start's day of the month, or the month's last day")
    func monthly() {
        let start = day("2026-01-31")
        #expect(Recurrence.monthly.occurs(on: day("2026-02-28"), start: start, calendar: calendar))
        #expect(!Recurrence.monthly.occurs(on: day("2026-02-27"), start: start, calendar: calendar))
        #expect(Recurrence.monthly.occurs(on: day("2026-03-31"), start: start, calendar: calendar))
        #expect(Recurrence.monthly.describe(start: day("2026-11-03"), calendar: calendar) == "monthly on the 3rd")
    }

    @Test("The next day it lands on")
    func nextDay() {
        let start = day("2026-11-02")  // a Monday
        #expect(Recurrence.weekdays([5]).nextDay(onOrAfter: day("2026-11-03"), start: start, calendar: calendar) == day("2026-11-05"))
        #expect(Recurrence.everyNDays(3).nextDay(onOrAfter: day("2026-11-03"), start: start, calendar: calendar) == day("2026-11-05"))
        #expect(Recurrence.once.nextDay(onOrAfter: day("2026-11-03"), start: start, calendar: calendar) == nil)
    }

    @Test("Storage round-trips through the stored columns")
    func storage() {
        for rule in [Recurrence.daily, .weekdays([2, 6]), .everyNDays(14), .monthly, .once] {
            #expect(Recurrence(kind: rule.kind, weekdayMask: rule.weekdayMask, intervalDays: rule.intervalDays) == rule)
        }
        #expect(Recurrence.weekdays([7]).describe(start: day("2026-11-07"), calendar: calendar) == "every Saturday")
        #expect(Recurrence.everyNDays(14).describe(start: day("2026-11-07"), calendar: calendar) == "every 2 weeks")
    }

    @Test("The picker reads back what it will do")
    func pickerSummary() {
        var choice = RepeatChoice(recurrence: .weekdays([5]), start: day("2026-11-10"), calendar: calendar)
        #expect(choice.summary(today: day("2026-11-08"), calendar: calendar) == "Every Thursday. First: Thursday, Nov 12.")
        choice.kind = .weekdays
        choice.weekdays = []
        #expect(choice.summary(today: day("2026-11-08"), calendar: calendar) == "Pick at least one day.")
        choice = RepeatChoice(recurrence: .daily, start: day("2026-11-01"), calendar: calendar)
        #expect(choice.summary(today: day("2026-11-08"), calendar: calendar) == "Every day. Next: today.")
    }
}
