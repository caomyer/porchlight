import Foundation
import GRDB
import Testing
@testable import Porchlight

@Suite("Shared contracts")
struct SharedTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        return calendar
    }

    @Test("DayKey round-trips and steps across month ends")
    func dayKey() throws {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 23, minute: 59)))
        let key = DayKey(date, calendar: calendar)
        #expect(key.rawValue == "2026-11-30")
        #expect(key.adding(days: 1, calendar: calendar).rawValue == "2026-12-01")
        #expect(DayKey(key.startDate(in: calendar), calendar: calendar) == key)
        #expect(DayKey(rawValue: "2026-11-07") < key)
    }

    @Test("Week starts on the household's first weekday")
    func weekDays() throws {
        let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 7)))
        let days = calendar.weekDays(containing: saturday).map { DayKey($0, calendar: calendar).rawValue }
        #expect(days.first == "2026-11-01")
        #expect(days.last == "2026-11-07")
    }

    @Test("Month grid covers whole weeks")
    func monthGrid() throws {
        let november = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15)))
        let days = calendar.monthGridDays(containing: november)
        #expect(days.count % 7 == 0)
        #expect(DayKey(days.first!, calendar: calendar).rawValue == "2026-11-01")
        #expect(DayKey(days.last!, calendar: calendar).rawValue == "2026-12-05")
    }

    @Test("A new household needs setup; marking it complete sticks")
    func setupFlag() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "J", color: .blue)])
        #expect(try db.snapshot().household?.setupCompleted == false)
        try db.markSetupCompleted(householdId: household.id)
        #expect(try db.snapshot().household?.setupCompleted == true)
    }

    @Test("Clock time has no leading zero")
    func clockFormat() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = try #require(utc.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 1, minute: 5)))
        let text = ClockFormat.time(date, calendar: utc)
        #expect(!text.hasPrefix("0"))
        #expect(text.hasSuffix(":05"))
    }
}
