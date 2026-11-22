import Foundation
import Testing
@testable import Porchlight

/// The one-line reader (docs/design/calendar-add-edit.md, "Adding"), on a table of real
/// phrases with the clock pinned: Tuesday, November 24, 2026, at 8 in the morning in Los
/// Angeles, unless a row says otherwise.
@Suite("Reading one typed line into an event")
struct EventLineTests {
    static func calendar(firstWeekday: Int = 1, locale: String = "en_US") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: locale)
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static let leo = Person(id: .derived("leo"), householdId: .derived("h"), name: "Leo", color: .blue, sortOrder: 0, createdAt: .distantPast)
    static let mia = Person(id: .derived("mia"), householdId: .derived("h"), name: "Mia Chen", color: .coral, sortOrder: 1, createdAt: .distantPast)

    static func at(_ text: String, _ calendar: Calendar = calendar()) -> Date { CalendarPassOnTests.date(text, calendar) }
    static let now = at("2026-11-24 08:00")

    struct Row: CustomTestStringConvertible, Sendable {
        var line: String
        var title: String
        var start: String
        /// "all day" for an all-day event, else the end.
        var end: String
        var forLeo = false
        var now = "2026-11-24 08:00"
        var testDescription: String { "\"\(line)\"" }
    }

    static let rows: [Row] = [
        // The proposal's own line.
        Row(line: "Leo dentist thu 4pm", title: "Leo dentist", start: "2026-11-26 16:00", end: "2026-11-26 17:00", forLeo: true),
        // Days.
        Row(line: "Haircut tomorrow at 9:30", title: "Haircut", start: "2026-11-25 09:30", end: "2026-11-25 10:30"),
        Row(line: "Pick up cake today 5pm", title: "Pick up cake", start: "2026-11-24 17:00", end: "2026-11-24 18:00"),
        Row(line: "Movie tonight", title: "Movie", start: "2026-11-24 19:00", end: "2026-11-24 20:00"),
        Row(line: "Book club friday 7pm", title: "Book club", start: "2026-11-27 19:00", end: "2026-11-27 20:00"),
        Row(line: "Soccer next tuesday 3:30pm", title: "Soccer", start: "2026-12-01 15:30", end: "2026-12-01 16:30"),
        // A weekday alone is the next one: today's if its time is still ahead, else a week on.
        Row(line: "Standup tue 9am", title: "Standup", start: "2026-11-24 09:00", end: "2026-11-24 10:00"),
        Row(line: "Breakfast tue 7am", title: "Breakfast", start: "2026-12-01 07:00", end: "2026-12-01 08:00"),
        // Dates, across the year's end.
        Row(line: "Winter concert Dec 10 6:30pm", title: "Winter concert", start: "2026-12-10 18:30", end: "2026-12-10 19:30"),
        Row(line: "New year brunch jan 1 11am", title: "New year brunch", start: "2027-01-01 11:00", end: "2027-01-01 12:00"),
        Row(line: "Recital on 12/3 at 6", title: "Recital", start: "2026-12-03 18:00", end: "2026-12-03 19:00"),
        Row(line: "Visit 3rd January", title: "Visit", start: "2027-01-03 00:00", end: "all day"),
        // Times with and without am or pm; the bare hour; noon and lunch.
        Row(line: "Soccer thu 4", title: "Soccer", start: "2026-11-26 16:00", end: "2026-11-26 17:00"),
        Row(line: "Gym wed at 7", title: "Gym", start: "2026-11-25 07:00", end: "2026-11-25 08:00"),
        Row(line: "Call grandma wed at 11:15", title: "Call grandma", start: "2026-11-25 11:15", end: "2026-11-25 12:15"),
        Row(line: "Plumber fri noon", title: "Plumber", start: "2026-11-27 12:00", end: "2026-11-27 13:00"),
        Row(line: "Sam at lunch fri", title: "Sam", start: "2026-11-27 12:30", end: "2026-11-27 13:30"),
        Row(line: "Lunch with Sam fri 1pm", title: "Lunch with Sam", start: "2026-11-27 13:00", end: "2026-11-27 14:00"),
        // 24-hour times.
        Row(line: "Train sat 16:45", title: "Train", start: "2026-11-28 16:45", end: "2026-11-28 17:45"),
        Row(line: "Flight sat 09:05", title: "Flight", start: "2026-11-28 09:05", end: "2026-11-28 10:05"),
        // Ranges and durations.
        Row(line: "Piano wed 4-5pm", title: "Piano", start: "2026-11-25 16:00", end: "2026-11-25 17:00"),
        Row(line: "Party sat 7pm to 10", title: "Party", start: "2026-11-28 19:00", end: "2026-11-28 22:00"),
        Row(line: "Brunch sun 11-1pm", title: "Brunch", start: "2026-11-29 11:00", end: "2026-11-29 13:00"),
        Row(line: "Hike sat from 9 to 12", title: "Hike", start: "2026-11-28 09:00", end: "2026-11-28 12:00"),
        Row(line: "Meeting thu 2pm for 90 minutes", title: "Meeting", start: "2026-11-26 14:00", end: "2026-11-26 15:30"),
        Row(line: "Run fri 6am for an hour", title: "Run", start: "2026-11-27 06:00", end: "2026-11-27 07:00"),
        // All day.
        Row(line: "Thanksgiving thu all day", title: "Thanksgiving", start: "2026-11-26 00:00", end: "all day"),
        Row(line: "Half day, school out fri", title: "Half day school out", start: "2026-11-27 00:00", end: "all day"),
        // Who: at the start, or after "for"; a full name's first name.
        Row(line: "Haircut for Leo sat 10am", title: "Haircut", start: "2026-11-28 10:00", end: "2026-11-28 11:00", forLeo: true),
        Row(line: "Mia piano wed 4pm", title: "Mia piano", start: "2026-11-25 16:00", end: "2026-11-25 17:00"),
        // A time with no day: today if still ahead, else tomorrow.
        Row(line: "Call the bank 3pm", title: "Call the bank", start: "2026-11-24 15:00", end: "2026-11-24 16:00"),
        Row(line: "Walk 7am", title: "Walk", start: "2026-11-25 07:00", end: "2026-11-25 08:00"),
        // A number that is a count stays in the title.
        Row(line: "Buy 2 tickets fri 6pm", title: "Buy 2 tickets", start: "2026-11-27 18:00", end: "2026-11-27 19:00"),
        // On New Year's Eve, "tomorrow" is next year.
        Row(line: "Brunch tomorrow 10am", title: "Brunch", start: "2027-01-01 10:00", end: "2027-01-01 11:00", now: "2026-12-31 21:00"),
    ]

    @Test("A line reads into its title, day, time and who it is for", arguments: rows)
    func reads(row: Row) {
        let reading = EventLine.read(row.line, now: Self.at(row.now), calendar: Self.calendar(), people: [Self.leo, Self.mia])
        #expect(reading.title == row.title)
        #expect(reading.start == Self.at(row.start), "start \(reading.start)")
        if row.end == "all day" {
            #expect(reading.isAllDay)
        } else {
            #expect(!reading.isAllDay)
            #expect(reading.end == Self.at(row.end), "end \(reading.end)")
        }
        #expect(reading.forIds == (row.forLeo ? [Self.leo.id] : (row.line.hasPrefix("Mia") ? [Self.mia.id] : [])))
    }

    @Test("\"Next\" a weekday is in the household's following week, from a Sunday or a Monday start")
    func nextWeek() {
        // Saturday, November 28: next Monday is two days on whichever day starts the week.
        let saturday = Self.at("2026-11-28 08:00")
        for firstWeekday in [1, 2] {
            let reading = EventLine.read("Dentist next monday 9am", now: saturday, calendar: Self.calendar(firstWeekday: firstWeekday), people: [])
            #expect(reading.start == Self.at("2026-11-30 09:00"), "first weekday \(firstWeekday)")
        }
        // Sunday, November 29: on a Monday-start calendar "next Sunday" is a week on; on a
        // Sunday-start one, today's week is the one that has begun, so also a week on.
        let sunday = Self.at("2026-11-29 08:00")
        #expect(EventLine.read("Brunch next sunday 10am", now: sunday, calendar: Self.calendar(firstWeekday: 2), people: []).start == Self.at("2026-12-06 10:00"))
        #expect(EventLine.read("Brunch next sunday 10am", now: sunday, calendar: Self.calendar(firstWeekday: 1), people: []).start == Self.at("2026-12-06 10:00"))
    }

    @Test("A date written with slashes is month first in the US and day first elsewhere")
    func slashes() {
        #expect(EventLine.read("Trip 3/12", now: Self.now, calendar: Self.calendar(), people: []).start == Self.at("2027-03-12 00:00"))
        let british = Self.calendar(firstWeekday: 2, locale: "en_GB")
        #expect(EventLine.read("Trip 3/12", now: Self.now, calendar: british, people: []).start == Self.at("2026-12-03 00:00", british))
    }

    @Test("A line with no day or time starts at the next whole hour, and says it found neither")
    func nothingSaid() {
        let reading = EventLine.read("Call the plumber", now: Self.at("2026-11-24 08:20"), calendar: Self.calendar(), people: [])
        #expect(reading.title == "Call the plumber")
        #expect(reading.start == Self.at("2026-11-24 09:00") && !reading.foundDay && !reading.foundTime)
    }
}
