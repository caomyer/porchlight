import Foundation
import Testing
@testable import Porchlight

/// When the household is free together (docs/design/calendar-free-together.md), on the UI
/// tests' pinned Wednesday, November 18, 2026, in Los Angeles unless a test says otherwise.
@Suite("Free together: evenings and weekend days")
struct FreeTogetherLogicTests {
    static func calendar(_ zone: String = "America/Los_Angeles", locale: String = "en_US") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    static let alex = Person(id: .derived("alex"), householdId: .derived("h"), name: "Alex", color: .blue, sortOrder: 0, createdAt: .distantPast)
    static let sam = Person(id: .derived("sam"), householdId: .derived("h"), name: "Sam", color: .coral, sortOrder: 1, createdAt: .distantPast)
    static let both = [alex.id, sam.id]

    /// "2026-11-18 17:30" in `calendar`.
    static func at(_ text: String, _ calendar: Calendar = calendar()) -> Date {
        let parts = text.split(separator: " ")
        let day = DayKey(rawValue: String(parts[0])).startDate(in: calendar)
        let hm = parts[1].split(separator: ":").map { Int($0)! }
        return calendar.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: day)!
    }

    static func event(
        _ title: String, _ from: String, _ to: String, owner: Owner, also: [Owner] = [], busy: Bool = false, quiet: Bool = false,
        allDay: Bool = false, calendar: Calendar = calendar()
    ) -> CalendarEvent {
        var event = CalendarEvent(
            id: title, calendarId: "c", title: busy ? "Busy" : title, emoji: nil, celebration: nil, location: nil, notes: nil,
            start: at(from, calendar), end: at(to, calendar), isAllDay: allDay,
            owner: owner, isBusy: busy, calendarTitle: "Cal", isFromSpecialCalendar: false
        )
        event.alsoFor = also
        event.isQuiet = quiet
        return event
    }

    static let wednesdayMorning = at("2026-11-18 08:00")

    private func times(_ events: [CalendarEvent], people: [Person.ID] = both, now: Date = wednesdayMorning, calendar: Calendar = calendar()) -> [FreeTime] {
        FreeTogetherLogic.times(events: events, people: people, from: now, calendar: calendar)
    }

    private func time(_ day: String, _ events: [CalendarEvent], people: [Person.ID] = both, now: Date = wednesdayMorning, calendar: Calendar = calendar()) -> FreeTime? {
        times(events, people: people, now: now, calendar: calendar).first { $0.day.rawValue == day }
    }

    private let words = FreeWords(calendar: calendar(), twelveHour: true, locale: Locale(identifier: "en_US"))

    // MARK: The days

    @Test("Today and the next 13 days: weekday evenings, Saturdays and Sundays as whole days")
    func days() {
        let all = times([])
        #expect(all.count == 14)
        #expect(all.first?.day.rawValue == "2026-11-18" && all.last?.day.rawValue == "2026-12-01")
        #expect(all.filter { $0.kind == .weekend }.map(\.day.rawValue) == ["2026-11-21", "2026-11-22", "2026-11-28", "2026-11-29"])
        #expect(all.first?.isToday == true && FreeWords.kindLabel(all[0]) == "Tonight")
        #expect(all.allSatisfy { $0.everyoneFrom != nil }, "nothing planned: everyone is free every time")
        #expect(words.headline(all[0], asked: 2) == "Everyone free from 5:30\u{202F}PM")
        #expect(words.headline(all[3], asked: 2) == "Everyone free all day", "Saturday")
        #expect(words.dayLabel(all[1]) == "Thu, Nov 19")
    }

    @Test("Weekend days follow the household's locale, not a fixed Saturday and Sunday")
    func weekendByLocale() {
        // In Israel the weekend is Friday and Saturday.
        let israel = Self.calendar("Asia/Jerusalem", locale: "he_IL")
        let now = Self.at("2026-11-18 08:00", israel)
        let kinds = FreeTogetherLogic.times(events: [], people: Self.both, from: now, days: 7, calendar: israel)
        #expect(kinds.filter { $0.kind == .weekend }.map(\.day.rawValue) == ["2026-11-20", "2026-11-21"])
    }

    @Test("Tonight counts from now: from the next quarter hour, and not at all with under two hours left")
    func tonight() {
        #expect(time("2026-11-18", [], now: Self.at("2026-11-18 16:00"))?.everyoneFrom == Self.at("2026-11-18 17:30"))
        #expect(time("2026-11-18", [], now: Self.at("2026-11-18 18:00"))?.everyoneFrom == Self.at("2026-11-18 18:00"))
        #expect(time("2026-11-18", [], now: Self.at("2026-11-18 18:05"))?.everyoneFrom == Self.at("2026-11-18 18:15"))
        #expect(time("2026-11-18", [], now: Self.at("2026-11-18 19:30"))?.everyoneFrom == Self.at("2026-11-18 19:30"), "exactly two hours left")
        #expect(time("2026-11-18", [], now: Self.at("2026-11-18 20:15")) == nil, "75 minutes left is not an evening")
        #expect(time("2026-11-18", [], now: Self.at("2026-11-18 21:45")) == nil)
        // A Saturday morning: "Today", from now, never "all day" once it has begun.
        let saturday = time("2026-11-21", [], now: Self.at("2026-11-21 10:10"))
        #expect(saturday.map(FreeWords.kindLabel) == "Today")
        #expect(saturday.flatMap { words.headline($0, asked: 2) } == "Everyone free from 10:15\u{202F}AM")
    }

    // MARK: Edges and thresholds

    @Test("An event ending as the evening opens leaves it free; a minute later moves it to the next quarter hour")
    func edges() {
        let atOpening = Self.event("Pickup", "2026-11-19 16:30", "2026-11-19 17:30", owner: .person(Self.alex.id))
        #expect(time("2026-11-19", [atOpening])?.everyoneFrom == Self.at("2026-11-19 17:30"))
        let minuteLate = Self.event("Pickup", "2026-11-19 16:30", "2026-11-19 17:31", owner: .person(Self.alex.id))
        #expect(time("2026-11-19", [minuteLate])?.everyoneFrom == Self.at("2026-11-19 17:45"))
        // One starting as it closes takes nothing from it.
        let atClosing = Self.event("Late show", "2026-11-19 21:30", "2026-11-19 23:30", owner: .everyone)
        #expect(time("2026-11-19", [atClosing])?.everyoneFrom == Self.at("2026-11-19 17:30"))
    }

    @Test("Two hours in an evening, three in a weekend day: exactly enough is free, a quarter hour short isn't")
    func thresholds() {
        let twoLeft = Self.event("Swim", "2026-11-19 17:30", "2026-11-19 19:30", owner: .person(Self.sam.id))
        #expect(time("2026-11-19", [twoLeft])?.free[Self.sam.id] == Self.at("2026-11-19 19:30"))
        let short = Self.event("Swim", "2026-11-19 17:30", "2026-11-19 19:31", owner: .person(Self.sam.id))
        let evening = time("2026-11-19", [short])
        #expect(evening?.free[Self.sam.id] == nil && evening?.free[Self.alex.id] == Self.at("2026-11-19 17:30"))
        #expect(evening?.everyoneFrom == nil)
        // Saturday 9 to 9:30: a morning event to 6:30 PM leaves three hours; to 6:31 PM doesn't.
        let three = Self.event("Tournament", "2026-11-21 09:00", "2026-11-21 18:30", owner: .everyone)
        #expect(time("2026-11-21", [three])?.everyoneFrom == Self.at("2026-11-21 18:30"))
        let less = Self.event("Tournament", "2026-11-21 09:00", "2026-11-21 18:31", owner: .everyone)
        #expect(time("2026-11-21", [less])?.everyoneFrom == nil)
        // A gap of three hours in the middle of the day counts.
        let morning = Self.event("Brunch", "2026-11-22 09:00", "2026-11-22 12:00", owner: .everyone)
        let evening2 = Self.event("Dinner", "2026-11-22 15:00", "2026-11-22 21:30", owner: .everyone)
        let sunday = time("2026-11-22", [morning, evening2])
        #expect(sunday?.everyoneFrom == Self.at("2026-11-22 12:00"))
        #expect(sunday.flatMap { words.headline($0, asked: 2) } == "Everyone free 12:00 to 3:00\u{202F}PM", "a stretch with something after it says when it ends")
        let late = Self.event("Brunch", "2026-11-22 09:00", "2026-11-22 14:00", owner: .everyone)
        #expect(time("2026-11-22", [late]).flatMap { words.headline($0, asked: 2) } == "Everyone free from 2:00\u{202F}PM")
    }

    @Test("A free stretch says when it ends when something follows it; after noon and all day only when nothing does")
    func stretchEnds() {
        let lunch = Self.event("Lunch out", "2026-11-21 13:00", "2026-11-21 14:00", owner: .person(Self.sam.id))
        let tacos = Self.event("Taco night", "2026-11-21 18:00", "2026-11-21 21:30", owner: .everyone)
        #expect(time("2026-11-21", [lunch, tacos]).flatMap { words.headline($0, asked: 2) } == "Everyone free until 1:00\u{202F}PM")
        let morning = Self.event("Soccer", "2026-11-21 09:00", "2026-11-21 12:00", owner: .everyone)
        #expect(time("2026-11-21", [morning]).flatMap { words.headline($0, asked: 2) } == "Everyone free after noon")
        #expect(time("2026-11-21", [morning, tacos]).flatMap { words.headline($0, asked: 2) } == "Everyone free 12:00 to 6:00\u{202F}PM")
        // An evening: until the first thing, or from the last.
        let late = Self.event("Late call", "2026-11-19 19:30", "2026-11-19 21:30", owner: .person(Self.alex.id))
        #expect(time("2026-11-19", [late]).flatMap { words.headline($0, asked: 2) } == "Everyone free until 7:30\u{202F}PM")
        let swim = Self.event("Swim", "2026-11-19 19:30", "2026-11-19 21:30", owner: .person(Self.sam.id))
        let found = time("2026-11-19", [swim], people: [Self.sam.id])
        #expect(found.flatMap { words.headline($0, asked: 1) } == "Free until 7:30\u{202F}PM")
    }

    @Test("No one free, each for something different: Everyone busy, then each; one plan for everyone is the plan")
    func everyoneBusy() {
        let swim = Self.event("Swim", "2026-11-19 17:30", "2026-11-19 21:30", owner: .person(Self.alex.id))
        let club = Self.event("Book club", "2026-11-19 17:30", "2026-11-19 21:00", owner: .person(Self.sam.id))
        let found = time("2026-11-19", [swim, club])
        #expect(found.flatMap { words.summary($0, asked: 2) } == "Everyone busy")
        #expect(found.map { words.busyLines($0, people: [Self.alex, Self.sam], household: 2).map(\.listed) }
            == ["Alex: Swim, 5:30 to 9:30\u{202F}PM", "Sam: Book club, 5:30 to 9:00\u{202F}PM"])
        let movie = Self.event("Movie night", "2026-11-19 19:00", "2026-11-19 20:30", owner: .everyone)
        let together = time("2026-11-19", [movie])
        #expect(together.flatMap { words.summary($0, asked: 2) } == nil)
        let line = together.map { words.busyLines($0, people: [Self.alex, Self.sam], household: 2) }?.first
        #expect(line?.title == "Movie night" && line?.detail == "Everyone, 7:00 to 8:30\u{202F}PM")
    }

    @Test("Events across midnight and across a whole weekend are busy wherever they reach")
    func longEvents() {
        let overnight = Self.event("Red-eye", "2026-11-20 23:00", "2026-11-21 10:00", owner: .everyone)
        #expect(time("2026-11-21", [overnight])?.everyoneFrom == Self.at("2026-11-21 10:00"))
        let trip = Self.event("Cabin", "2026-11-20 16:00", "2026-11-22 20:00", owner: .everyone)
        let found = times([trip])
        #expect(found.first { $0.day.rawValue == "2026-11-20" }?.everyoneFrom == nil)
        #expect(found.first { $0.day.rawValue == "2026-11-21" }?.everyoneFrom == nil)
        #expect(found.first { $0.day.rawValue == "2026-11-22" }?.everyoneFrom == nil, "home at 8, an hour and a half before the day ends")
        #expect(found.first { $0.day.rawValue == "2026-11-23" }?.everyoneFrom == Self.at("2026-11-23 17:30"))
    }

    // MARK: Clocks and zones

    @Test("On the days the clocks change, the windows are still 5:30 to 9:30 and 9 to 9:30 on the wall's clock")
    func clocksChange() {
        let calendar = Self.calendar()
        // Sunday, March 8, 2026 (an hour shorter) and Sunday, November 1, 2026 (an hour longer).
        for (now, sunday) in [("2026-03-05 08:00", "2026-03-08"), ("2026-10-29 08:00", "2026-11-01")] {
            let found = FreeTogetherLogic.times(events: [], people: Self.both, from: Self.at(now, calendar), days: 7, calendar: calendar)
            let day = found.first { $0.day.rawValue == sunday }
            #expect(day?.kind == .weekend)
            #expect(day?.window.start == Self.at("\(sunday) 09:00", calendar) && day?.window.end == Self.at("\(sunday) 21:30", calendar))
            #expect(day?.window.duration == 12.5 * 3600)
            let monday = found.first { $0.day.rawValue > sunday }
            #expect(monday?.window.start == Self.at("\(monday!.day.rawValue) 17:30", calendar))
        }
    }

    @Test("In another time zone the evening is that zone's 5:30")
    func otherZone() {
        let berlin = Self.calendar("Europe/Berlin", locale: "de_DE")
        let found = FreeTogetherLogic.times(events: [], people: Self.both, from: Self.at("2026-11-18 08:00", berlin), days: 3, calendar: berlin)
        #expect(found.first?.window.start == Self.at("2026-11-18 17:30", berlin))
        #expect(found.map(\.day.rawValue) == ["2026-11-18", "2026-11-19", "2026-11-20"])
    }

    // MARK: What counts

    @Test("Work shown quietly is busy from its first meeting to its last, gaps and all; shown in full, a gap is free")
    func quietWork() {
        // One block, as the wall shows it: 5:30 to 8:30 PM.
        let block = Self.event("Alex at work", "2026-11-19 17:30", "2026-11-19 20:30", owner: .person(Self.alex.id), quiet: true)
        let quiet = time("2026-11-19", [block])
        #expect(quiet?.free[Self.alex.id] == nil, "an hour left")
        #expect(quiet.map { words.busyLines($0, people: [Self.alex, Self.sam], household: 2).map(\.sentence) } == ["Alex at work until 8:30\u{202F}PM"])
        #expect(quiet.map { words.freeLines($0, people: [Self.alex, Self.sam]) } == ["Sam free from 5:30\u{202F}PM"])
        // The same two meetings shown in full leave 6 to 8 free.
        let first = Self.event("Standup", "2026-11-19 17:30", "2026-11-19 18:00", owner: .person(Self.alex.id))
        let second = Self.event("Review", "2026-11-19 20:00", "2026-11-19 20:30", owner: .person(Self.alex.id))
        #expect(time("2026-11-19", [first, second])?.free[Self.alex.id] == Self.at("2026-11-19 18:00"))
    }

    @Test("Busy only is busy and says only that; an event For one person in another's calendar is theirs; one for everyone, everyone's")
    func owners() {
        let doctor = Self.event("Doctor", "2026-11-19 17:00", "2026-11-19 20:00", owner: .person(Self.sam.id), busy: true)
        let found = time("2026-11-19", [doctor])
        #expect(found.map { words.busyLines($0, people: [Self.alex, Self.sam], household: 2).map(\.sentence) } == ["Sam busy, 5:00 to 8:00\u{202F}PM"])
        // Book club in Alex's calendar, For Sam: Sam is out, Alex isn't.
        var club = Self.event("Book club", "2026-11-19 19:00", "2026-11-19 21:00", owner: .person(Self.sam.id))
        club.calendarId = "alex-calendar"
        let evening = time("2026-11-19", [club])
        #expect(evening?.free[Self.alex.id] == Self.at("2026-11-19 17:30") && evening?.free[Self.sam.id] == nil)
        #expect(evening.map { words.busyLines($0, people: [Self.alex, Self.sam], household: 2).map(\.sentence) } == ["Sam busy: Book club, 7:00 to 9:00\u{202F}PM"])
        // A party for everyone keeps everyone out, said once.
        let party = Self.event("Grandma's 80th", "2026-11-20 18:00", "2026-11-20 21:00", owner: .everyone)
        let friday = time("2026-11-20", [party])
        #expect(friday.map { words.busyLines($0, people: [Self.alex, Self.sam], household: 2).map(\.sentence) } == ["Grandma's 80th: Everyone, 6:00 to 9:00\u{202F}PM"])
        // The same event on both calendars (one with the other's face) keeps both out.
        let shared = Self.event("Movie", "2026-11-23 18:00", "2026-11-23 21:00", owner: .person(Self.alex.id), also: [.person(Self.sam.id)])
        #expect(time("2026-11-23", [shared])?.free.isEmpty == true)
    }

    @Test("An all-day event is never busy and is listed under its day")
    func allDay() {
        let rosa = Self.event("Aunt Rosa visiting", "2026-11-21 00:00", "2026-11-23 00:00", owner: .everyone, allDay: true)
        let birthday = Self.event("Sam's birthday", "2026-11-21 00:00", "2026-11-22 00:00", owner: .person(Self.sam.id), allDay: true)
        let saturday = time("2026-11-21", [rosa, birthday])
        #expect(saturday?.everyoneAllWindow == true)
        #expect(saturday?.allDay == ["Aunt Rosa visiting", "Sam's birthday"])
        #expect(time("2026-11-22", [rosa, birthday])?.allDay == ["Aunt Rosa visiting"])
        #expect(time("2026-11-23", [rosa, birthday])?.allDay == [], "it ended at midnight")
    }

    // MARK: Who is asked

    @Test("With one person's chip picked it answers for that person; a household of one says Free")
    func onePerson() {
        let swim = Self.event("Swim", "2026-11-19 17:30", "2026-11-19 20:00", owner: .person(Self.sam.id))
        let alexOnly = time("2026-11-19", [swim], people: [Self.alex.id])
        #expect(alexOnly.flatMap { words.headline($0, asked: 1) } == "Free from 5:30\u{202F}PM")
        let samOnly = time("2026-11-19", [swim], people: [Self.sam.id])
        #expect(samOnly.flatMap { words.headline($0, asked: 1) } == nil)
        #expect(samOnly.map { words.busyLines($0, people: [Self.alex, Self.sam], household: 2).map(\.sentence) } == ["Sam busy: Swim, 5:30 to 8:00\u{202F}PM"])
        #expect(time("2026-11-21", [], people: [Self.alex.id]).flatMap { words.headline($0, asked: 1) } == "Free all day")
    }

    @Test("Four people: names joined in the household's order, and Everyone only when it is all of them")
    func fourPeople() {
        let kids = [Person.ID.derived("a"), .derived("b"), .derived("c"), .derived("d")]
        let people = kids.enumerated().map { Person(id: $1, householdId: .derived("h"), name: ["Ava", "Ben", "Cy", "Di"][$0], color: .blue, sortOrder: $0, createdAt: .distantPast) }
        #expect(FreeWords.names([kids[0], kids[2]], people: people, household: 4) == "Ava and Cy")
        #expect(FreeWords.names([kids[0], kids[1], kids[3]], people: people, household: 4) == "Ava, Ben and Di")
        #expect(FreeWords.names(kids, people: people, household: 4) == "Everyone")
        let games = Self.event("Game night", "2026-11-19 18:00", "2026-11-19 21:00", owner: .person(kids[1]), also: [.person(kids[2])])
        let found = time("2026-11-19", [games], people: kids)
        #expect(found.map { words.busyLines($0, people: people, household: 4).map(\.sentence) } == ["Ben and Cy busy: Game night, 6:00 to 9:00\u{202F}PM"])
    }

    @Test("Ranges say the period once, across noon twice, and 24-hour phones use 24 hours")
    func ranges() {
        #expect(words.range(Self.at("2026-11-19 19:00"), Self.at("2026-11-19 21:00")) == "7:00 to 9:00\u{202F}PM")
        #expect(words.range(Self.at("2026-11-21 11:00"), Self.at("2026-11-21 13:00")) == "11:00\u{202F}AM to 1:00\u{202F}PM")
        let twentyFour = FreeWords(calendar: Self.calendar(), twelveHour: false, locale: Locale(identifier: "en_GB"))
        #expect(twentyFour.range(Self.at("2026-11-19 19:00"), Self.at("2026-11-19 21:00")) == "19:00 to 21:00")
    }

    @Test("Swept over a year in two zones: every window is inside its day, in order, and never in the past")
    func sweep() {
        for zone in ["America/Los_Angeles", "Europe/Berlin"] {
            let calendar = Self.calendar(zone)
            var now = Self.at("2026-01-01 07:13", calendar)
            for _ in 0..<73 {
                let found = FreeTogetherLogic.times(events: [], people: Self.both, from: now, calendar: calendar)
                #expect(found.count >= 13 && found.count <= 14, "\(zone) \(now)")
                for time in found {
                    #expect(time.window.start >= now && time.window.start < time.window.end)
                    #expect(DayKey(time.window.start, calendar: calendar) == time.day)
                    #expect(DayKey(time.window.end.addingTimeInterval(-1), calendar: calendar) == time.day)
                }
                #expect(zip(found, found.dropFirst()).allSatisfy { $0.window.end <= $1.window.start })
                now = now.addingTimeInterval(5 * 86_400 + 3 * 3600 + 17 * 60)
            }
        }
    }
}
