import Foundation
import Testing
@testable import Porchlight

/// The phone's Today: which slot one tap logs, the order of the cards, the one missed
/// slot it offers to catch up on, and how my chores and the shared ones are split.
@Suite("Phone Today")
struct PocketTodayTests {
    private typealias F = CareFixture

    private static let household = Household(
        id: 100, name: "Home", timeZoneIdentifier: "America/Los_Angeles", firstWeekday: 1,
        setupCompleted: true, createdAt: F.date(day: 1, 0)
    )
    private static let feed = CareRoutine(
        id: 12, companionId: 1, kind: .feed, title: "Feed", emoji: "🥣", everyDays: 1,
        windows: [.hours("Breakfast", 6, 9), .hours("Dinner", 17, 19)],
        trackedFields: [], stars: 1, nudgeAfterMinutes: nil, sortOrder: 1
    )
    private static let people = [
        Person(id: F.james, householdId: 100, name: "James", color: .blue, sortOrder: 0, createdAt: F.date(day: 1, 0)),
        Person(id: F.mia, householdId: 100, name: "Mia", color: .coral, sortOrder: 1, createdAt: F.date(day: 1, 0)),
    ]

    private static func companion(_ id: Companion.ID, _ name: String, _ species: Species, order: Int) -> Companion {
        Companion(
            id: id, householdId: 100, name: name, species: species, coat: .honey, about: "",
            captionTone: .off, sortOrder: order, createdAt: F.date(day: 1, 0)
        )
    }

    /// Yo-Yo (walks and meals) and, when asked, the fern watered every three days.
    private func snapshot(_ entries: [CareEntry], fern: Bool = false) -> CompanionSnapshot {
        CompanionSnapshot(
            household: Self.household, people: Self.people, everyone: Self.people,
            companions: [Self.companion(1, "Yo-Yo", .dog, order: 0)] + (fern ? [Self.companion(2, "Fern", .plant, order: 1)] : []),
            routines: [F.walk, Self.feed] + (fern ? [F.water] : []),
            entries: entries.sorted { $0.time < $1.time }
        )
    }

    private func reports(_ snapshot: CompanionSnapshot, at now: Date) -> [CompanionReport] {
        snapshot.companions.compactMap { CompanionReport.make(snapshot: snapshot, companionId: $0.id, now: now) }
    }

    private func walkToday(_ entries: [CareEntry], at now: Date) throws -> RoutineToday {
        try #require(reports(snapshot(entries), at: now).first?.primary)
    }

    /// Both meals on November 7.
    private let meals = [
        F.entry(501, 7, 30, by: [F.mia], routine: 12),
        F.entry(502, 17, 30, by: [F.mia], routine: 12),
    ]

    // MARK: One tap

    @Test("One tap logs the slot whose window is open now")
    func openWindow() throws {
        let morning = F.entry(1, 7, 10, by: [F.mia])
        let slot = PocketToday.oneTapSlot(try walkToday([morning], at: F.date(18, 5)), now: F.date(18, 5), calendar: F.calendar)
        #expect(slot?.index == 1)
        #expect(slot?.state == .due)
    }

    @Test("Between windows, one tap logs the nearer slot only while it is still waiting")
    func betweenWindows() throws {
        let morning = F.entry(1, 7, 10, by: [F.mia])
        // 2 pm is nearer the evening (5 pm) than the morning (10 am).
        let afternoon = PocketToday.oneTapSlot(try walkToday([morning], at: F.date(14, 0)), now: F.date(14, 0), calendar: F.calendar)
        #expect(afternoon?.index == 1)
        #expect(afternoon?.state == .upcoming)
        // 11 am belongs to the morning, which Mia already did.
        #expect(PocketToday.oneTapSlot(try walkToday([morning], at: F.date(11, 0)), now: F.date(11, 0), calendar: F.calendar) == nil)
    }

    @Test("A window that closed without a log is caught up on, not tapped")
    func closedWindow() throws {
        let morning = F.entry(1, 7, 10, by: [F.mia])
        let now = F.date(21, 0)
        #expect(PocketToday.oneTapSlot(try walkToday([morning], at: now), now: now, calendar: F.calendar) == nil)
        let snapshot = snapshot([morning] + meals)
        let missed = try #require(PocketToday.catchUp(reports(snapshot, at: now), snapshot: snapshot, dismissed: []))
        #expect(missed.missed.routine.id == F.walk.id)
        #expect(missed.missed.day == F.key(7))
        #expect(missed.missed.slot.index == 1)
    }

    // MARK: Cards

    @Test("The companion that needs someone now comes first; the rest keep the household's order")
    func cardOrder() {
        // Yo-Yo is all set; the fern's watering is due today, any time.
        let entries = [F.entry(1, 7, 10), F.entry(2, 17, 40, by: [F.mia])] + meals
        let snapshot = snapshot(entries, fern: true)
        let cards = PocketToday.cards(reports(snapshot, at: F.date(18, 30)), calendar: F.calendar)
        #expect(cards.map(\.report.name) == ["Fern", "Yo-Yo"])
        #expect(cards.map(\.standing) == [.due, .allSet])
        #expect(cards[0].lead?.routine.id == F.water.id)
        #expect(cards[1].lead == nil)
    }

    @Test("A walk that is open leads its card; a meal that is open too is offered beside it")
    func leadAndOthers() throws {
        let entries = [F.entry(1, 7, 10), F.entry(501, 7, 30, by: [F.mia], routine: 12)]
        let card = try #require(PocketToday.cards(reports(snapshot(entries), at: F.date(17, 20)), calendar: F.calendar).first)
        #expect(card.standing == .due)
        #expect(card.lead?.routine.id == F.walk.id)
        #expect(card.lead?.slot.index == 1)
        #expect(card.others.map(\.routine.id) == [Self.feed.id])
        #expect(card.shown?.routine.id == F.walk.id)
    }

    @Test("A card that just finished shows it was logged, then folds to all set")
    func freshness() throws {
        let entries = [F.entry(1, 7, 10), F.entry(2, 18, 0, by: [F.mia])] + meals
        let soon = try #require(PocketToday.cards(reports(snapshot(entries), at: F.date(18, 10)), calendar: F.calendar).first)
        #expect(PocketToday.isFresh(soon))
        let later = try #require(PocketToday.cards(reports(snapshot(entries), at: F.date(18, 30)), calendar: F.calendar).first)
        #expect(!PocketToday.isFresh(later))
        #expect(PocketToday.allSetLine(later.report, me: F.james, names: snapshot(entries).names, calendar: F.calendar)
            == "Walked at 6pm by Mia · fed at 5:30pm by Mia")
    }

    // MARK: Catching up

    @Test("Catching up offers the newest missed slot, and leaves a dismissed one alone")
    func catchUpNewest() throws {
        // Yesterday's dinner was never logged; today's walks and meals are done.
        let entries = [
            F.entry(10, day: 6, 7, 0), F.entry(11, day: 6, 18, 0),
            F.entry(510, day: 6, 7, 30, routine: 12),
            F.entry(1, 7, 10), F.entry(2, 18, 0),
        ] + meals
        let snapshot = snapshot(entries)
        let now = F.date(19, 0)
        let first = try #require(PocketToday.catchUp(reports(snapshot, at: now), snapshot: snapshot, dismissed: []))
        #expect(first.missed.routine.id == Self.feed.id)
        #expect(first.missed.day == F.key(6))
        #expect(first.missed.slot.window.label == "Dinner")
        let after = PocketToday.catchUp(reports(snapshot, at: now), snapshot: snapshot, dismissed: [first.missed.id])
        #expect(after?.missed.id != first.missed.id)
    }

    // MARK: Chores

    @Test("My chores and the shared ones come from the wall's board for today")
    func choreSplit() {
        let day = DayKey(rawValue: "2026-11-07")
        func chore(_ id: Chore.ID, _ title: String, owner: Person.ID?, order: Int) -> Chore {
            Chore(
                id: id, householdId: 100, title: title, ownerId: owner, repeatKind: "daily", weekdayMask: 0, intervalDays: 1,
                anchorDay: "2026-11-01", stars: 2, archived: false, sortOrder: order, createdAt: F.date(day: 1, 0)
            )
        }
        let chores = [
            chore(1, "Breakfast", owner: F.james, order: 0), chore(2, "Dishes", owner: F.mia, order: 1),
            chore(3, "Vacuum", owner: nil, order: 2), chore(4, "Recycling", owner: F.james, order: 3),
        ]
        let done = ChoreCompletion(choreId: 1, day: day, personId: F.james, stars: 2, completedAt: F.date(8, 0))
        let board = ChoreBoard(
            people: Self.people, chores: chores, completions: [done], earnings: [], rewards: [], today: day, calendar: F.calendar
        )
        let split = PocketToday.chores(board, me: F.james)
        #expect(split.mine.map(\.chore.title) == ["Breakfast", "Recycling"])
        #expect(split.mine.map(\.isDone) == [true, false])
        #expect(split.anyone.map(\.chore.title) == ["Vacuum"])
        #expect(PocketToday.chores(board, me: F.mia).mine.map(\.chore.title) == ["Dishes"])
    }

    @Test("Stars today count my chores and care, not anyone else's or other days'")
    func starsToday() {
        let day = DayKey(rawValue: "2026-11-07")
        func earning(_ person: Person.ID, _ stars: Int, on day: DayKey, log: CareLog.ID) -> StarEarning {
            StarEarning(source: .care(routineId: 10, logId: log), personId: person, stars: stars, day: day, at: F.date(8, 0), recordedAt: F.date(8, 0), title: "Walk", emoji: "🦮")
        }
        let earnings = [
            earning(F.james, 2, on: day, log: 1), earning(F.james, 3, on: day, log: 2),
            earning(F.mia, 2, on: day, log: 3), earning(F.james, 5, on: DayKey(rawValue: "2026-11-06"), log: 4),
        ]
        #expect(PocketToday.stars(earnings, me: F.james, on: day) == 5)
    }

    // MARK: Words

    @Test("Someone else's log is named before offering to join it")
    func words() {
        let names: [Person.ID: String] = [F.james: "James", F.mia: "Mia"]
        let entry = F.entry(1, 17, 40, by: [F.mia])
        #expect(PocketToday.alreadyDone(entry, words: CareWords(F.walk, species: .dog), companion: "Yo-Yo", me: F.james, names: names, calendar: F.calendar) == "Mia walked Yo-Yo at 5:40pm")
        let mine = F.entry(2, 17, 40, by: [F.james])
        #expect(PocketToday.alreadyDone(mine, words: CareWords(F.walk, species: .dog), companion: "Yo-Yo", me: F.james, names: names, calendar: F.calendar) == "You walked Yo-Yo at 5:40pm")
        #expect(PocketToday.who([F.james, F.mia], me: F.james, names: names) == "Mia & you")
    }
}
