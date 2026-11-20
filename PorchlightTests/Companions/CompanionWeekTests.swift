import Foundation
import Testing
@testable import Porchlight

/// A companion's week, one routine at a time: what the wall's companion page shows for
/// the primary routine and the phone's for any, from one implementation.
@Suite("A companion's week")
struct CompanionWeekTests {
    typealias F = CareFixture

    struct Week {
        let report: CompanionReport
        let calendar: Calendar
        let today: DayKey
        let james: Person.ID
        let mia: Person.ID

        var yesterday: DayKey { today.adding(days: -1, calendar: calendar) }
        var walks: RoutineWeek { report.weeks[0] }
        var meals: RoutineWeek { report.weeks[1] }
    }

    /// Yo-Yo, walked and fed for ten days but only logged today and yesterday, at 6:30 pm.
    /// Yesterday's dinner was skipped; tonight's is open.
    private func week() throws -> Week {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [
            PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral),
        ])
        let people = try db.snapshot().people.map(\.id)
        let calendar = try #require(try db.snapshot().household).calendar
        let today = DayKey(.now, calendar: calendar)
        let now = CareLogic.date(today, minute: 18 * 60 + 30, calendar: calendar)
        let yesterday = today.adding(days: -1, calendar: calendar)

        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        draft.about = "Toy poodle"
        draft.birthDate = calendar.date(byAdding: .month, value: -51, to: now)
        for index in draft.routines.indices { draft.routines[index].startDay = today.adding(days: -10, calendar: calendar) }
        let id = try db.saveCompanion(draft, householdId: household.id, now: now.addingTimeInterval(-11 * 24 * 3600))
        let routines = try db.writer.read(CompanionSnapshot.fetch).routines(of: id)
        let (walk, feed) = (routines[0], routines[1])
        let at = { (day: DayKey, hour: Int, minute: Int) in CareLogic.date(day, minute: hour * 60 + minute, calendar: calendar) }
        try db.logCare(routineId: walk.id, CareLogDraft(people: [people[1]], occurredAt: at(today, 8, 0), durationMinutes: 25, pee: true), now: now)
        try db.logCare(routineId: walk.id, CareLogDraft(people: [people[0]], occurredAt: at(yesterday, 8, 0)), now: now)
        try db.logCare(routineId: walk.id, CareLogDraft(people: people, occurredAt: at(yesterday, 18, 0)), now: now)
        try db.logCare(routineId: feed.id, CareLogDraft(people: [people[0]], occurredAt: at(today, 7, 15)), now: now)
        try db.logCare(routineId: feed.id, CareLogDraft(people: [people[1]], occurredAt: at(yesterday, 7, 15)), now: now)

        let snapshot = try db.writer.read(CompanionSnapshot.fetch)
        let report = try #require(CompanionReport.make(snapshot: snapshot, companionId: id, now: now))
        return Week(report: report, calendar: calendar, today: today, james: people[0], mia: people[1])
    }

    @Test("Every routine has its week, and the primary's is the wall's")
    func everyRoutine() throws {
        let week = try week()
        let report = week.report
        #expect(report.weeks.map(\.routine.kind) == [.walk, .feed])
        #expect(report.primaryWeek?.id == report.primaryRoutine?.id)
        #expect(report.diary == week.walks.diary, "The wall's diary is the primary routine's")
        #expect(report.trail == week.walks.trail)
        #expect(report.weekStats == week.walks.stats)
        #expect(report.week(of: week.meals.id)?.routine.kind == .feed)
        #expect(report.week(of: nil) == nil)

        #expect(week.walks.diary.count == 3)
        #expect(week.meals.diary.count == 2, "Meals have their own diary")
        #expect(week.meals.diary.allSatisfy { $0.entry.log.careRoutineId == week.meals.id })
        #expect(week.meals.trail.count == 7 && week.meals.trail[6].map(\.isDone) == [true, false], "and their own trail")
        #expect(week.meals.missed.allSatisfy { $0.routine.id == week.meals.id })
        #expect(week.walks.missed.count + week.meals.missed.count == report.missed.count, "Each missed slot is in its routine's week")
        #expect(week.meals.missed.contains { $0.day == week.yesterday && $0.slot.index == 1 }, "Yesterday's dinner")
    }

    @Test("A trail slot opens its log, catches up on a missed one and logs one still open")
    func trailTaps() throws {
        let week = try week()
        let meals = week.meals
        let today = meals.trail[6]
        let yesterday = meals.trail[5]

        #expect(meals.tap(today[0], on: week.today) == .edit(try #require(today[0].entry)), "This morning's breakfast opens to fix")
        #expect(meals.tap(today[1], on: week.today) == .log, "Tonight's dinner is open: a new log")
        let dinner = try #require(meals.missed.first { $0.day == week.yesterday && $0.slot.index == 1 })
        #expect(meals.tap(yesterday[1], on: week.yesterday) == .catchUp(dinner), "Yesterday's dinner is caught up on for yesterday")
        #expect(meals.tap(nil, on: week.today) == nil, "A day it wasn't due asks nothing")

        var notOwed = meals
        notOwed.missed = []
        #expect(notOwed.tap(yesterday[1], on: week.yesterday) == nil, "A slot that was never owed asks nothing")

        let names = [week.james: "James", week.mia: "Mia"]
        let weekday = week.yesterday.formatted(.dateTime.weekday(.wide), calendar: week.calendar)
        #expect(meals.trailLabel(yesterday[1], window: yesterday[1].window, on: week.yesterday, names: names, calendar: week.calendar) == "Dinner, \(weekday), missed")
        #expect(meals.trailLabel(yesterday[0], window: yesterday[0].window, on: week.yesterday, names: names, calendar: week.calendar) == "Breakfast, \(weekday), Mia")
        let todayName = week.today.formatted(.dateTime.weekday(.wide), calendar: week.calendar)
        #expect(meals.trailLabel(today[1], window: today[1].window, on: week.today, names: names, calendar: week.calendar) == "Dinner, \(todayName), to do")
        #expect(week.walks.trailLabel(nil, window: .hours("Morning", 6, 10), on: week.today, names: names, calendar: week.calendar).hasSuffix("not due"))
    }

    @Test("The four numbers follow the routine")
    func tiles() throws {
        let week = try week()
        let walks = week.walks.tiles(calendar: week.calendar)
        #expect(walks.map(\.label) == ["2×/day streak 🔥", "avg walk", "slots on time", "business log"])
        #expect(walks[1] == .init(value: "25", unit: "min", label: "avg walk"))
        #expect(walks[3].value == "💧1 💩0")
        let meals = week.meals.tiles(calendar: week.calendar)
        #expect(meals.map(\.label) == ["2×/day streak 🔥", "meals this week", "slots on time", "stars this week"])
        #expect(meals[1].value == "2")
        #expect(meals[3].value == "⭐2")
        #expect(week.meals.summary == "2 meals · 2 stars earned")
        #expect(week.report.weekSummary == week.walks.summary)
    }

    @Test("The podium stands second, first, third, and crowns only a clear leader")
    func podium() {
        let first = CareLogic.Standing(carer: .person(1), count: 5)
        let second = CareLogic.Standing(carer: .person(2), count: 3)
        let third = CareLogic.Standing(carer: .together, count: 1)
        #expect(CareLogic.podium([first, second, third, .init(carer: .person(3), count: 1)]) == [second, first, third])
        #expect(CareLogic.podium([first, second]) == [second, first])
        #expect(CareLogic.podium([first]) == [first])
        #expect(CareLogic.leader([first, second]) == first)
        #expect(CareLogic.leader([first]) == first)
        #expect(CareLogic.leader([first, .init(carer: .person(2), count: 5)]) == nil, "A tie has no crown")
        #expect(CareLogic.leader([]) == nil)
    }

    @Test("The page's words, from the routine's kind")
    func words() throws {
        let week = try week()
        let walk = week.walks.routine
        let feed = week.meals.routine
        #expect(CompanionWeekWords.diaryTitle(walk) == "Walk diary")
        #expect(CompanionWeekWords.diaryTitle(feed) == "Meal diary")
        #expect(CompanionWeekWords.podiumTitle(feed) == "Chef of the week")
        #expect(CompanionWeekWords.trailMeta(walk) == "who walked, each slot")
        #expect(CompanionWeekWords.trailMeta(feed) == "who fed, each slot")
        var litter = feed
        litter.kind = .litter
        #expect(CompanionWeekWords.trailMeta(litter) == "who did it, each slot")
        #expect(CompanionWeekWords.logButton(feed) == "Log a meal")
        #expect(CompanionWeekWords.emptyDiary(feed) == "Nothing logged this week yet. The first meal starts the story.")
        #expect(CompanionWeekWords.emptyPodium(walk) == "No walks yet this week. The podium is wide open.")
        var companion = week.report.companion
        companion.captionTone = .cheeky
        #expect(CompanionWeekWords.captionsMeta(companion) == "captions: Cheeky")
        companion.captionTone = .off
        #expect(CompanionWeekWords.captionsMeta(companion) == nil)

        let dinner = try #require(week.meals.missed.first { $0.day == week.yesterday })
        #expect(CompanionWeekWords.missedTitle(dinner, companion: week.report.companion) == "Feed Yo-Yo · Dinner")
        let abbreviated = week.yesterday.formatted(.dateTime.weekday(.abbreviated), calendar: week.calendar)
        #expect(CompanionWeekWords.missedDetail(dinner, calendar: week.calendar) == "\(abbreviated) · usually \(CareTime.range(17 * 60, 19 * 60))")
        #expect(CompanionWeekWords.missedDay(dinner, today: week.today, calendar: week.calendar) == "yesterday")

        let morning = CareLogic.date(week.today, minute: 8 * 60, calendar: week.calendar)
        #expect(CompanionWeekWords.when(morning, today: week.today, calendar: week.calendar) == "Today \(CareTime.hour(8 * 60))")
        let lastNight = CareLogic.date(week.yesterday, minute: 18 * 60, calendar: week.calendar)
        #expect(CompanionWeekWords.when(lastNight, today: week.today, calendar: week.calendar) == "\(abbreviated) \(CareTime.hour(18 * 60))")

        #expect(week.report.aboutLine(calendar: week.calendar) == "Toy poodle · 4 yrs")
        #expect(week.report.moodText.hasSuffix(week.report.moodLabel?.label ?? "-"))
    }
}
