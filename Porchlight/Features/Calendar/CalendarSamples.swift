#if DEBUG
import Foundation

enum CalendarSamples {
    /// Seeds sample data matching the mocks (DEBUG `-sampleHousehold` only).
    static func seed(_ database: AppDatabase, household: Household, people: [Person]) throws {
        let householdId = household.id
        try database.syncCalendarSources(householdId: householdId, calendars: calendars)
        let sources = try database.calendarSnapshot().sources
        for source in sources {
            let id = source.id
            switch source.externalId {
            case work:
                try database.setCalendarSourceVisibility(id: id, visibility: .busy)
            case holidays:
                try database.setCalendarSourceShown(id: id, isShown: false)
            default:
                break
            }
        }
    }

    static let james = "sample-james"
    static let work = "sample-work"
    static let mia = "sample-mia"
    static let us = "sample-us"
    static let birthdays = "sample-birthdays"
    static let holidays = "sample-holidays"

    static let calendars: [ExternalCalendar] = [
        ExternalCalendar(id: james, title: "James", account: "Google · james@example.com", colorHex: 0x4C7BB0),
        ExternalCalendar(id: work, title: "Work", account: "Google · james@example.com", colorHex: 0x7E8CA0),
        ExternalCalendar(id: mia, title: "Mia", account: "iCloud · mia@example.com", colorHex: 0xDD7558),
        ExternalCalendar(id: us, title: "Us", account: "Google · shared by James", colorHex: 0xC2933A),
        ExternalCalendar(id: birthdays, title: "Birthdays", account: "iCloud · from Contacts", colorHex: 0xB07AA1, kind: .birthdays),
        ExternalCalendar(id: holidays, title: "US Holidays", account: "Subscribed link", colorHex: 0x9AA0A6, kind: .subscribed),
    ]
}

/// Stand-in for EventKit on the simulator (which has no accounts). Mirrors the
/// mocks: the mock week of Nov 1-7 ends on the real today, and the rest of the
/// month follows the month mock.
@MainActor
final class SampleCalendarProvider: CalendarProvider {
    private static let james = CalendarSamples.james
    private static let work = CalendarSamples.work
    private static let mia = CalendarSamples.mia
    private static let us = CalendarSamples.us
    private static let birthdays = CalendarSamples.birthdays
    private static let holidays = CalendarSamples.holidays

    var onChange: (@MainActor () -> Void)?
    let access = CalendarAccess.granted
    private let calendar: Calendar
    private lazy var allEvents: [ExternalEvent] = makeEvents()

    init(calendar: Calendar = .current, now: Date = .now) {
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
    }

    private let today: Date

    func requestAccess() async -> CalendarAccess { access }

    func calendars() -> [ExternalCalendar] { CalendarSamples.calendars }

    func events(in interval: DateInterval, calendarIds: Set<String>) -> [ExternalEvent] {
        allEvents.filter { calendarIds.contains($0.calendarId) && $0.end > interval.start && $0.start < interval.end }
    }

    // MARK: Data

    private func makeEvents() -> [ExternalEvent] {
        var events: [ExternalEvent] = []

        func timed(_ offset: Int, _ calendarId: String, _ start: Double, _ end: Double, _ title: String, _ location: String? = nil, notes: String? = nil) {
            let day = date(offset)
            events.append(ExternalEvent(
                id: "\(calendarId)-\(offset)-\(title)",
                calendarId: calendarId,
                title: title,
                location: location,
                notes: notes,
                start: day.addingTimeInterval(start * 3600),
                end: day.addingTimeInterval(end * 3600),
                isAllDay: false
            ))
        }

        func allDay(_ offset: Int, days: Int = 1, _ calendarId: String, _ title: String, _ location: String? = nil, notes: String? = nil) {
            events.append(ExternalEvent(
                id: "\(calendarId)-\(offset)-\(title)",
                calendarId: calendarId,
                title: title,
                location: location,
                notes: notes,
                start: date(offset),
                end: date(offset + days),
                isAllDay: true
            ))
        }

        // The mock week: six days ago through today.
        timed(-6, Self.us, 10, 12, "Brunch at home")
        timed(-6, Self.james, 14, 15.5, "Tennis", "Golden Gate Park courts")
        timed(-6, Self.mia, 16, 17, "Meal prep")
        timed(-5, Self.james, 11, 12, "Dentist", "Dr. Patel")
        timed(-5, Self.mia, 9, 10.5, "Design review")
        timed(-5, Self.mia, 18.5, 19.5, "Yoga", "Haven Studio")
        timed(-4, Self.work, 13, 14, "Sprint planning")
        timed(-4, Self.us, 18, 19, "Taco night")
        timed(-3, Self.james, 12, 13, "Lunch w/ Sam")
        timed(-3, Self.mia, 19, 20, "Pottery", "Clay Studio")
        timed(-2, Self.mia, 8, 9, "Gym")
        timed(-2, Self.james, 16, 17, "Call w/ Mom")
        timed(-2, Self.us, 19, 20.5, "Movie night")
        timed(-1, Self.work, 9, 10, "1:1 with Dana")
        timed(-1, Self.us, 18.5, 20.5, "Sushi night in")
        allDay(-1, days: 3, Self.us, "Aunt Rosa visiting", notes: "Guest room is ready. She lands Friday at 4.")
        timed(0, Self.james, 10, 11.5, "Climbing gym", "Mission Cliffs")
        timed(0, Self.us, 12.5, 13.5, "Aunt Rosa over for lunch", "at home")
        timed(0, Self.mia, 15, 17, "Pottery class", "Clay Studio")
        timed(0, Self.mia, 19, 20.5, "Book club", "at Priya's", notes: "This month: Tomorrow, and Tomorrow, and Tomorrow")

        // The rest of the month mock (mock day n is n - 7 days from today).
        timed(1, Self.us, 10, 11.5, "Brunch with Rosa")
        timed(1, Self.us, 13, 14, "Farmers market")
        timed(2, Self.mia, 18.5, 19.5, "Yoga", "Haven Studio")
        timed(2, Self.work, 9, 11, "Quarterly planning")
        timed(3, Self.us, 18, 19, "Taco night")
        timed(3, Self.work, 13, 14, "Sprint planning")
        timed(4, Self.mia, 19, 20, "Pottery", "Clay Studio")
        timed(4, Self.james, 7.5, 8.5, "Haircut", "Barber & Co")
        timed(5, Self.us, 18, 21, "Grandma's 80th", "Lucia's", notes: "Dinner at 6. Bring the photo album.")
        timed(6, Self.us, 19, 20.5, "Movie night")
        timed(6, Self.mia, 8, 9, "Gym")
        timed(7, Self.james, 14, 15.5, "Tennis", "Golden Gate Park courts")
        timed(9, Self.mia, 18.5, 19.5, "Yoga", "Haven Studio")
        allDay(10, days: 3, Self.james, "Seattle trip")
        timed(10, Self.us, 18, 19, "Taco night")
        timed(13, Self.us, 19, 20.5, "Movie night")
        allDay(14, Self.us, "Our anniversary", "Nopa", notes: "Table booked for 7:30.")
        timed(14, Self.mia, 10, 12, "Bake sale", "Lincoln Elementary")
        timed(16, Self.mia, 18.5, 19.5, "Yoga", "Haven Studio")
        timed(17, Self.us, 18, 19, "Taco night")
        allDay(20, Self.us, "Day off")
        timed(21, Self.us, 10, 12, "Tree hunt")
        timed(23, Self.mia, 18.5, 19.5, "Yoga", "Haven Studio")

        // Earlier weeks: the household's regular rhythm.
        for week in 1...6 {
            let base = -6 - 7 * week
            timed(base + 1, Self.mia, 18.5, 19.5, "Yoga", "Haven Studio")
            timed(base + 2, Self.us, 18, 19, "Taco night")
            timed(base + 3, Self.mia, 19, 20, "Pottery", "Clay Studio")
            timed(base + 4, Self.us, 19, 20.5, "Movie night")
            if week.isMultiple(of: 2) { timed(base, Self.james, 14, 15.5, "Tennis", "Golden Gate Park courts") }
            timed(base + 2, Self.work, 13, 14, "Sprint planning")
        }

        allDay(-10, Self.birthdays, "Leo's Birthday")
        allDay(40, Self.birthdays, "Sam's Birthday")
        events += holidays()
        return events
    }

    private func date(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// A few real US holidays around today.
    private func holidays() -> [ExternalEvent] {
        let year = calendar.component(.year, from: today)
        var events: [ExternalEvent] = []
        for y in (year - 1)...(year + 1) {
            var days: [(String, DateComponents)] = [
                ("New Year's Day", DateComponents(year: y, month: 1, day: 1)),
                ("Independence Day", DateComponents(year: y, month: 7, day: 4)),
                ("Halloween", DateComponents(year: y, month: 10, day: 31)),
                ("Veterans Day", DateComponents(year: y, month: 11, day: 11)),
                ("Christmas Day", DateComponents(year: y, month: 12, day: 25)),
            ]
            days.append(("Thanksgiving", DateComponents(year: y, month: 11, weekday: 5, weekdayOrdinal: 4)))
            for (title, components) in days {
                guard let start = calendar.date(from: components), let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
                events.append(ExternalEvent(id: "holiday-\(y)-\(title)", calendarId: Self.holidays, title: title, start: start, end: end, isAllDay: true))
            }
        }
        return events
    }
}
#endif
