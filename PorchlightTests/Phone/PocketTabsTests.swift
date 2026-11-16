import Foundation
import Testing
@testable import Porchlight

/// The phone's other tabs and pages: grocery sections, dinners to groceries, Glow for
/// me, the next 7 days, Pitch in's week, and the calendar choices.
@Suite("Phone tabs")
struct PocketTabsTests {
    private typealias F = CareFixture
    private let calendar = CareFixture.calendar

    private func person(_ id: Person.ID, _ name: String, order: Int) -> Person {
        Person(id: id, householdId: 100, name: name, color: .blue, sortOrder: order, createdAt: F.date(day: 1, 0))
    }

    // MARK: Lists

    @Test("Groceries group under their aisles in store-walk order, keeping list order inside")
    func grocerySections() {
        func item(_ id: ListItem.ID, _ title: String, _ section: String?) -> ListItem {
            ListItem(id: id, listId: 1, title: title, section: section, addedById: nil, checked: false, sortOrder: 0, createdAt: F.date(8))
        }
        let items = [item(1, "Oat milk", "Dairy"), item(2, "Basil", "Produce"), item(3, "Candles", "For the party"), item(4, "Limes", "Produce"), item(5, "Thing", nil)]
        let sections = GrocerySections.group(items)
        #expect(sections.map(\.name) == ["Produce", "Dairy", "For the party", "Other"])
        #expect(sections[0].items.map(\.title) == ["Basil", "Limes"])
    }

    @Test("A dinner's needs become one grocery item each; nothing is merged")
    func dinnerNeeds() {
        #expect(DinnerIngredients.titles(from: "tortillas, limes and cilantro") == ["Tortillas", "Limes", "Cilantro"])
        #expect(DinnerIngredients.titles(from: " limes ,, limes ") == ["Limes", "Limes"])
        #expect(DinnerIngredients.titles(from: "  ").isEmpty)
    }

    @Test("Adding a dinner's needs puts each on the grocery list in its aisle, by me")
    func dinnerNeedsInTheDatabase() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let me = try db.snapshot().people[0].id
        try db.ensureDefaultLists(householdId: household.id)
        let groceries = try #require(try db.homeSnapshot(since: DayKey(rawValue: "2026-01-01")).lists.first { $0.kind == .grocery })
        for title in DinnerIngredients.titles(from: "tortillas, limes, limes") {
            _ = try db.addListItem(title: title, to: groceries.id, addedBy: me)
        }
        let items = try db.homeSnapshot(since: DayKey(rawValue: "2026-01-01")).items.filter { $0.listId == groceries.id }
        #expect(items.map(\.title) == ["Tortillas", "Limes", "Limes"])
        #expect(items.map(\.section) == ["Bakery", "Produce", "Produce"])
        #expect(items.allSatisfy { $0.addedById == me })
    }

    // MARK: Glow

    private func earning(_ person: Person.ID?, _ stars: Int, day: Int, log: CareLog.ID) -> StarEarning {
        let date = F.date(day: day, 9)
        return StarEarning(source: .care(routineId: 10, logId: log), personId: person, stars: stars, day: F.key(day), at: date, recordedAt: date, title: "Walk", emoji: "🦮")
    }

    @Test("A shared goal names everyone who earned this round, most stars first; a treat only its owner")
    func earners() {
        let people = [person(F.james, "James", order: 0), person(F.mia, "Mia", order: 1), person(F.ava, "Ava", order: 2)]
        let earnings = [
            earning(F.james, 2, day: 3, log: 1),   // before the round started
            earning(F.mia, 2, day: 5, log: 2), earning(F.james, 1, day: 6, log: 3), earning(F.mia, 3, day: 7, log: 4),
        ]
        let shared = Reward(id: 1, householdId: 100, title: "Pizza night", emoji: "🍕", targetStars: 5, ownerId: nil, startDay: F.key(4).rawValue, archived: false, sortOrder: 0, createdAt: F.date(day: 1, 0))
        #expect(PocketGlowLogic.earners(of: shared, earnings: earnings, redemptions: [], people: people).map(\.name) == ["Mia", "James"])
        var treat = shared
        treat.ownerId = F.james
        #expect(PocketGlowLogic.earners(of: treat, earnings: earnings, redemptions: [], people: people).map(\.name) == ["James"])
        #expect(PocketGlowLogic.names(people.prefix(2).map { $0 }, me: F.james).contains("you"))
    }

    @Test("My Glow is my week and all-time stars, and the rewards I'm saving for")
    func mine() {
        let people = [person(F.james, "James", order: 0), person(F.mia, "Mia", order: 1)]
        let week = HomeWeek(containing: F.key(7), calendar: calendar)
        let summary = GlowSummary(
            people: people, earnings: [earning(F.james, 2, day: 6, log: 1), earning(F.mia, 5, day: 6, log: 2), earning(F.james, 1, day: 7, log: 3)],
            redemptions: [], rewards: [], lifetime: [F.james: 40], week: week, today: F.key(7), calendar: calendar
        )
        #expect(PocketGlowLogic.mine(summary, me: F.james) == .init(weekStars: 3, lifetimeStars: 40))
        func reward(_ id: Reward.ID, owner: Person.ID?, order: Int, archived: Bool = false) -> Reward {
            Reward(id: id, householdId: 100, title: "R\(id.number)", emoji: nil, targetStars: 10, ownerId: owner, startDay: "2026-11-01", archived: archived, sortOrder: order, createdAt: F.date(day: 1, 0))
        }
        let rewards = [reward(1, owner: F.james, order: 0), reward(2, owner: nil, order: 1), reward(3, owner: F.mia, order: 2), reward(4, owner: nil, order: 3, archived: true)]
        #expect(PocketGlowLogic.rewards(rewards, me: F.james) { _ in 4 }.map(\.reward.id) == [2, 1])
    }

    // MARK: Next 7 days

    private func event(_ id: String, day: Int, _ hour: Double, allDay: Bool = false) -> CalendarEvent {
        let start = F.date(day: day, 0).addingTimeInterval(hour * 3600)
        return CalendarEvent(
            id: id, calendarId: "c", title: id, emoji: nil, celebration: nil, location: nil, notes: nil,
            start: start, end: start.addingTimeInterval(allDay ? 24 * 3600 : 3600), isAllDay: allDay,
            owner: .everyone, isBusy: false, calendarTitle: "Family", isFromSpecialCalendar: false
        )
    }

    @Test("The next 7 days skip empty days and put all-day events first")
    func nextDays() {
        let events: [DayKey: [CalendarEvent]] = [
            F.key(7): [event("Dinner", day: 7, 19), event("Rosa visiting", day: 7, 0, allDay: true)],
            F.key(9): [event("Yoga", day: 9, 18), event("Brunch", day: 9, 10)],
            F.key(20): [event("Too far", day: 20, 9)],
        ]
        let days = PocketAgendaLogic.nextDays(from: F.key(7), count: 7, calendar: calendar) { events[$0] ?? [] }
        #expect(days.map(\.day) == [F.key(7), F.key(9)])
        #expect(days[0].events.map(\.id) == ["Rosa visiting", "Dinner"])
        #expect(days[1].events.map(\.id) == ["Brunch", "Yoga"])
        #expect(PocketAgendaLogic.dayTitle(F.key(7), today: F.key(7), calendar: calendar) == "Today")
        #expect(PocketAgendaLogic.dayTitle(F.key(8), today: F.key(7), calendar: calendar) == "Tomorrow")
        #expect(PocketAgendaLogic.dayTitle(F.key(9), today: F.key(7), calendar: calendar) == F.key(9).formatted(.dateTime.weekday(.wide), calendar: calendar))
    }

    // MARK: Pitch in

    @Test("Pitch in's week counts every chore day this week, done or still to come")
    func weekProgress() {
        let week = HomeWeek(containing: F.key(7), calendar: calendar)
        let daily = Chore(id: 1, householdId: 100, title: "Dishes", ownerId: F.james, repeatKind: "daily", weekdayMask: 0, intervalDays: 1, anchorDay: "2026-10-01", stars: 1, archived: false, sortOrder: 0, createdAt: F.date(day: 1, 0))
        let done = [
            ChoreCompletion(choreId: 1, day: F.key(2), personId: F.james, stars: 1, completedAt: F.date(day: 2, 20)),
            ChoreCompletion(choreId: 1, day: F.key(5), personId: F.mia, stars: 1, completedAt: F.date(day: 5, 20)),
        ]
        let progress = PocketPitchInLogic.weekProgress(chores: [daily], completions: done, week: week, calendar: calendar)
        #expect(progress.done == 2)
        #expect(progress.total == 7)
        let mine = PocketPitchInLogic.doneThisWeek(by: F.james, chores: [daily], completions: done, week: week, before: F.key(7))
        #expect(mine.map(\.completion.dayKey) == [F.key(2)])
    }

    // MARK: Calendars

    @Test("A calendar's choice on the phone maps to how it is shared")
    func calendarChoices() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        try db.syncCalendarSources(householdId: household.id, calendars: [
            ExternalCalendar(id: "work", title: "Work", account: "Google", colorHex: 0x336699, kind: .regular),
        ])
        var source = try #require(try db.calendarSnapshot().sources.first)
        #expect(source.sharing == .household, "A new calendar starts shared with the household")
        for choice in CalendarSharing.allCases {
            try db.setCalendarSourceSharing(id: source.id, sharing: choice)
            source = try #require(try db.calendarSnapshot().sources.first)
            #expect(source.sharing == choice)
        }
        try db.setCalendarSourceSharing(id: source.id, sharing: .busyOnly)
        source = try #require(try db.calendarSnapshot().sources.first)
        #expect(source.visibility == .busy)
        #expect(!source.isPersonal)
    }
}
