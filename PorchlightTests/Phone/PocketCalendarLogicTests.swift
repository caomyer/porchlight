import Foundation
import Testing
@testable import Porchlight

/// The phone's Calendar tab as pure functions (docs/design/calendar-phone-tab.md): weeks from
/// the household's first weekday, paging, the month grid, the header, the dots, the person
/// filter, the list's days and the time style. Calendars, days and the clock are handed in.
@Suite("The phone's Calendar tab: weeks, months, dots, filtering and the list")
struct PocketCalendarLogicTests {
    static func calendar(_ zone: String = "America/Los_Angeles", firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static let alex = Person(id: .derived("alex"), householdId: .derived("h"), name: "Alex", color: .blue, sortOrder: 0, createdAt: .distantPast)
    static let sam = Person(id: .derived("sam"), householdId: .derived("h"), name: "Sam", color: .coral, sortOrder: 1, createdAt: .distantPast)

    static func day(_ text: String) -> DayKey { DayKey(rawValue: text) }

    static func event(_ id: String, _ day: String, hour: Double, owner: Owner, allDay: Bool = false, also: [Owner] = [], calendar: Calendar = calendar()) -> CalendarEvent {
        let start = Self.day(day).startDate(in: calendar).addingTimeInterval(allDay ? 0 : hour * 3600)
        var event = CalendarEvent(
            id: id, calendarId: "c", title: id, emoji: nil, celebration: nil, location: nil, notes: nil,
            start: start, end: start.addingTimeInterval(allDay ? 86_400 : 3600), isAllDay: allDay,
            owner: owner, isBusy: false, calendarTitle: "Cal", isFromSpecialCalendar: false
        )
        event.alsoFor = also
        return event
    }

    // MARK: Weeks

    @Test("A week starts on the household's first weekday, Sunday or Monday, whatever day is in it")
    func weeks() {
        let sunday = Self.calendar(firstWeekday: 1)
        #expect(PocketCalendarLogic.week(containing: Self.day("2026-11-24"), calendar: sunday).map(\.rawValue)
            == ["2026-11-22", "2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27", "2026-11-28"])
        let monday = Self.calendar("Europe/Berlin", firstWeekday: 2)
        #expect(PocketCalendarLogic.week(containing: Self.day("2026-11-22"), calendar: monday).first?.rawValue == "2026-11-16")
        #expect(PocketCalendarLogic.week(containing: Self.day("2026-11-23"), calendar: monday).first?.rawValue == "2026-11-23")
        // Every day of a year lands in a week of seven days holding it.
        for calendar in [sunday, monday] {
            var day = Self.day("2026-01-01")
            for _ in 0..<366 {
                let week = PocketCalendarLogic.week(containing: day, calendar: calendar)
                #expect(week.count == 7 && week.contains(day))
                #expect(calendar.component(.weekday, from: week[0].startDate(in: calendar)) == calendar.firstWeekday)
                day = day.adding(days: 1, calendar: calendar)
            }
        }
    }

    @Test("Paging: a week across the clocks going back keeps seven days, and a picked day's week is found from today's")
    func paging() {
        let calendar = Self.calendar()
        // Daylight saving ends on Sunday, November 1, 2026 in Los Angeles.
        let dst = PocketCalendarLogic.week(containing: Self.day("2026-11-04"), calendar: calendar)
        #expect(dst.map(\.rawValue) == ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"])
        let today = Self.day("2026-11-24")
        #expect(PocketCalendarLogic.week(offset: -3, from: today, calendar: calendar).first?.rawValue == "2026-11-01")
        #expect(PocketCalendarLogic.weekOffset(of: Self.day("2026-11-04"), from: today, calendar: calendar) == -3)
        #expect(PocketCalendarLogic.weekOffset(of: Self.day("2026-12-03"), from: today, calendar: calendar) == 1)
        #expect(PocketCalendarLogic.weekOffset(of: Self.day("2026-11-28"), from: today, calendar: calendar) == 0)
    }

    @Test("The month grid is whole weeks from the first weekday, the next month's days filling the last row")
    func month() {
        let rows = PocketCalendarLogic.monthGrid(containing: Self.day("2026-11-24"), calendar: Self.calendar())
        #expect(rows.count == 5)
        #expect(rows.first?.first?.rawValue == "2026-11-01" && rows.last?.last?.rawValue == "2026-12-05")
        #expect(!PocketCalendarLogic.isInMonth(Self.day("2026-12-01"), of: Self.day("2026-11-24"), calendar: Self.calendar()))
        // A month beginning on the last day of the week needs six rows.
        let august = PocketCalendarLogic.monthGrid(containing: Self.day("2026-08-15"), calendar: Self.calendar())
        #expect(august.count == 6 && august.first?.last?.rawValue == "2026-08-01")
        let monday = PocketCalendarLogic.monthGrid(containing: Self.day("2026-11-24"), calendar: Self.calendar("Europe/Berlin", firstWeekday: 2))
        #expect(monday.first?.first?.rawValue == "2026-10-26" && monday.allSatisfy { $0.count == 7 })
    }

    @Test("The header names the month, or both months, or both years, of the week shown")
    func title() {
        let calendar = Self.calendar()
        #expect(PocketCalendarLogic.title(for: PocketCalendarLogic.week(containing: Self.day("2026-11-24"), calendar: calendar), calendar: calendar) == "November 2026")
        #expect(PocketCalendarLogic.title(for: PocketCalendarLogic.week(containing: Self.day("2026-12-01"), calendar: calendar), calendar: calendar) == "Nov - Dec 2026")
        #expect(PocketCalendarLogic.title(for: PocketCalendarLogic.week(containing: Self.day("2026-12-31"), calendar: calendar), calendar: calendar) == "Dec 2026 - Jan 2027")
    }

    // MARK: People

    @Test("A dot per person with something that day, in the household's order, the household's own last")
    func dots() {
        let events = [
            Self.event("a", "2026-11-24", hour: 9, owner: .person(Self.sam.id)),
            Self.event("b", "2026-11-24", hour: 10, owner: .everyone),
            Self.event("c", "2026-11-24", hour: 11, owner: .person(Self.sam.id), also: [.person(Self.alex.id)]),
        ]
        #expect(PocketCalendarLogic.dots(events, people: [Self.alex, Self.sam]) == [.person(Self.alex.id), .person(Self.sam.id), .everyone])
        #expect(PocketCalendarLogic.dots(events, people: [Self.alex, Self.sam], limit: 2).count == 2)
        #expect(PocketCalendarLogic.dots([], people: [Self.alex]).isEmpty)
        // Under Alex's chip: his, the one he shares with Sam as his, and the household's.
        #expect(PocketCalendarLogic.dots(events, people: [Self.alex, Self.sam], filter: .person(Self.alex.id)) == [.person(Self.alex.id), .everyone])
        let samsOnly = [Self.event("a", "2026-11-24", hour: 9, owner: .person(Self.sam.id), also: [.person(Self.alex.id)])]
        #expect(PocketCalendarLogic.dots(samsOnly, people: [Self.alex, Self.sam], filter: .person(Self.alex.id)) == [.person(Self.alex.id)])
    }

    @Test("A person's chip keeps their events, the shared ones they are on, and the household's")
    func filter() {
        let events = [
            Self.event("alex", "2026-11-24", hour: 9, owner: .person(Self.alex.id)),
            Self.event("sam", "2026-11-24", hour: 10, owner: .person(Self.sam.id)),
            Self.event("both", "2026-11-24", hour: 11, owner: .person(Self.sam.id), also: [.person(Self.alex.id)]),
            Self.event("home", "2026-11-24", hour: 12, owner: .everyone),
        ]
        #expect(PocketCalendarLogic.filter(events, by: .person(Self.alex.id)).map(\.id) == ["alex", "both", "home"])
        #expect(PocketCalendarLogic.filter(events, by: .everyone).count == 4)
    }

    // MARK: The list

    @Test("The list starts at the picked day, saying when it is empty, then the days after that have something, all-day first")
    func sections() {
        let calendar = Self.calendar()
        let byDay: [String: [CalendarEvent]] = [
            "2026-11-25": [Self.event("dinner", "2026-11-25", hour: 19, owner: .everyone), Self.event("away", "2026-11-25", hour: 0, owner: .everyone, allDay: true)],
            "2026-11-27": [Self.event("game", "2026-11-27", hour: 10, owner: .everyone)],
            "2026-12-20": [Self.event("too far", "2026-12-20", hour: 10, owner: .everyone)],
        ]
        let sections = PocketCalendarLogic.sections(from: Self.day("2026-11-24"), today: Self.day("2026-11-24"), calendar: calendar) { byDay[$0.rawValue] ?? [] }
        #expect(sections.map(\.day.rawValue) == ["2026-11-24", "2026-11-25", "2026-11-27"])
        #expect(sections[0].events.isEmpty && sections[0].title == "Today, Tuesday")
        #expect(sections[1].title == "Tomorrow, Wednesday" && sections[1].events.map(\.id) == ["away", "dinner"] && sections[1].count == "2 things")
        #expect(sections[2].title == "Friday" && sections[2].count == "1 thing")
        #expect(PocketCalendarLogic.dayTitle(Self.day("2026-12-07"), today: Self.day("2026-11-24"), calendar: calendar) == "Mon, Dec 7")
        #expect(PocketCalendarLogic.dayTitle(Self.day("2026-11-23"), today: Self.day("2026-11-24"), calendar: calendar) == "Yesterday, Monday")
    }

    @Test("Every time says morning or afternoon on a 12-hour phone, and needs nothing on a 24-hour one")
    func times() {
        let calendar = Self.calendar()
        let evening = Self.day("2026-11-24").startDate(in: calendar).addingTimeInterval(18 * 3600)
        let morning = Self.day("2026-11-24").startDate(in: calendar).addingTimeInterval(9 * 3600 + 30 * 60)
        let us = Locale(identifier: "en_US")
        #expect(ClockFormat.phoneTime(evening, calendar: calendar, twelveHour: true, locale: us) == "6:00\u{202F}PM")
        #expect(ClockFormat.phoneTime(morning, calendar: calendar, twelveHour: true, locale: us) == "9:30\u{202F}AM")
        #expect(ClockFormat.phoneTime(evening, calendar: calendar, twelveHour: false, locale: us) == "18:00")
        // An all-day row says so; a timed one that began the day before shows from midnight.
        let allDay = Self.event("away", "2026-11-24", hour: 0, owner: .everyone, allDay: true)
        #expect(PocketCalendarLogic.time(allDay, on: Self.day("2026-11-24"), calendar: calendar) == "All day")
    }
}
