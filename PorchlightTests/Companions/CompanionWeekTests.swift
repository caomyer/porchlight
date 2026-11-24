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
        let snapshot: CompanionSnapshot
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
    private func week(atMinute minute: Int = 18 * 60 + 30, weeksBack: Int = 0, earlier: Bool = false) throws -> Week {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [
            PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral),
        ])
        let people = try db.snapshot().people.map(\.id)
        let calendar = try #require(try db.snapshot().household).calendar
        let today = DayKey(CompanionClock.now(), calendar: calendar)
        let now = CareLogic.date(today, minute: minute, calendar: calendar)
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
        if earlier {
            // Two walks last week, nine days ago: Mia's long one and James's.
            let nine = today.adding(days: -9, calendar: calendar)
            try db.logCare(routineId: walk.id, CareLogDraft(people: [people[1]], occurredAt: at(nine, 8, 0), durationMinutes: 40, poo: true), now: now)
            try db.logCare(routineId: walk.id, CareLogDraft(people: [people[0]], occurredAt: at(nine, 18, 0), durationMinutes: 20), now: now)
        }

        let snapshot = try db.writer.read(CompanionSnapshot.fetch)
        let report = try #require(CompanionReport.make(snapshot: snapshot, companionId: id, now: now, weeksBack: weeksBack))
        return Week(report: report, snapshot: snapshot, calendar: calendar, today: today, james: people[0], mia: people[1])
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

        let weekday = week.yesterday.formatted(.dateTime.weekday(.wide), calendar: week.calendar)
        #expect(meals.trailLabel(yesterday[1], window: yesterday[1].window, on: week.yesterday, snapshot: week.snapshot) == "Dinner, \(weekday), missed")
        #expect(meals.trailLabel(yesterday[0], window: yesterday[0].window, on: week.yesterday, snapshot: week.snapshot) == "Breakfast, \(weekday), Mia")
        let todayName = week.today.formatted(.dateTime.weekday(.wide), calendar: week.calendar)
        #expect(meals.trailLabel(today[1], window: today[1].window, on: week.today, snapshot: week.snapshot) == "Dinner, \(todayName), to do")
        #expect(week.walks.trailLabel(nil, window: .hours("Morning", 6, 10), on: week.today, snapshot: week.snapshot).hasSuffix("not due"))
    }

    @Test("Today's slot whose window closed is caught up on for that slot, not logged now")
    func lateToday() throws {
        let week = try week(atMinute: 21 * 60)
        let dinner = try #require(week.meals.trail[6].first { $0.index == 1 })
        #expect(dinner.state == .late)
        guard case let .catchUp(missed) = week.meals.tap(dinner, on: week.today) else {
            Issue.record("A late dinner is caught up on")
            return
        }
        #expect(missed.day == week.today && missed.slot.index == 1, "for tonight's dinner, the slot tapped")
        let todayName = week.today.formatted(.dateTime.weekday(.wide), calendar: week.calendar)
        #expect(week.meals.trailLabel(dinner, window: dinner.window, on: week.today, snapshot: week.snapshot) == "Dinner, \(todayName), late")
        #expect(week.meals.missed.allSatisfy { $0.day != week.today }, "It isn't in the diary's missed rows, which are earlier days")
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
        // The phone page's line: the same facts in fewer words, after who the pet is.
        #expect(week.meals.shortSummary == "2 meals · 2 stars")
        #expect(week.walks.shortSummary.hasPrefix(week.walks.summary.components(separatedBy: " · ")[0]))
        #expect(!week.walks.shortSummary.contains("outside") && !week.walks.shortSummary.contains("earned"))
        let line = week.report.aboutAndWeekLine(calendar: week.calendar).replacingOccurrences(of: "\u{00A0}", with: " ")
        #expect(week.report.aboutAndWeekLine(calendar: week.calendar).contains("\u{00A0}"), "a fact is never broken over two lines")
        #expect(line == week.report.aboutLine(calendar: week.calendar) + " · " + week.walks.shortSummary, "who the pet is, never dropped: \(line)")
    }

    @Test("An earlier week is that week's: its trail, numbers and diary; the streak and the catching up stay now's")
    func earlierWeek() throws {
        let now = try week(earlier: true)
        #expect(now.report.weeksBack == 0 && now.report.weeksBackLimit == 1, "back to the week it arrived, eleven days ago")
        let last = try week(weeksBack: 1, earlier: true)
        let report = last.report
        #expect(report.weekDays.first == last.today.adding(days: -13, calendar: last.calendar))
        #expect(report.weekDays.last == last.today.adding(days: -7, calendar: last.calendar))
        #expect(last.walks.stats.count == 2, "that week's two walks")
        #expect(last.walks.diary.count == 2)
        #expect(last.walks.streak == now.walks.streak, "the streak is today's")
        let tiles = last.walks.tiles(calendar: last.calendar)
        #expect(tiles.map(\.label) == ["streak today 🔥", "avg walk", "slots on time", "business log"])
        #expect(tiles[1].value == "30" && tiles[3].value == "💧0 💩1")
        #expect(last.meals.tiles(calendar: last.calendar)[1].label == "meals that week")
        // Catching up is now's rule (the last six days): nothing that week can be.
        #expect(report.missed.isEmpty && last.walks.missed.isEmpty)
        #expect(last.walks.late.isEmpty)
        // Asking further back than it goes stays at its first week.
        #expect(try week(weeksBack: 5, earlier: true).report.weeksBack == 1)
        #expect(try week(weeksBack: 3).report.weeksBack == 1, "its arrival's week, with nothing logged before this one")
        #expect(report.weekSpoken(last.walks, calendar: last.calendar).hasPrefix("Last week, "))
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

    @Test("Water is a plant's watering and an animal's refill, everywhere it is named")
    func waterWords() {
        let water = F.water
        for species in [Species.dog, .cat] {
            let bowl = CareWords(water, species: species)
            #expect(bowl.isBowl)
            #expect(CompanionWeekWords.logButton(bowl) == "Log a refill")
            #expect(CompanionWeekWords.diaryTitle(bowl) == "Water diary")
            #expect(CompanionWeekWords.trailMeta(bowl) == "who refilled, each slot")
            #expect(CompanionWeekWords.podiumTitle(bowl) == "Bartender of the week")
            #expect(CompanionWeekWords.emptyPodium(bowl) == "No refills yet this week. The podium is wide open.")
            #expect(CompanionWeekWords.logged(bowl) == "Refill logged", "the toast")
            #expect(CompanionWeekWords.waitingForFirst(bowl) == "Waiting for first refill")
            #expect(bowl.sentence(who: "Mia", name: "Yo-Yo") == "Mia refilled Yo-Yo's water", "the timeline and arrivals")
            #expect(bowl.buttonTitle(name: "Yo-Yo") == "I refilled Yo-Yo's water", "Today's button and the reminder's action")
            #expect(bowl.question(name: "Yo-Yo") == "Who refilled Yo-Yo's water?", "the wall's care sheet")
            #expect(bowl.pastVerb == "Refilled", "Today's card and the widgets")
            #expect(CareLogWording.editTitle(bowl) == "Edit refill")
            #expect(CareLogWording.confirmRemove(bowl) == "Remove refill")
        }

        let plant = CareWords(water, species: .plant)
        #expect(!plant.isBowl)
        #expect(CompanionWeekWords.logButton(plant) == "Log a watering")
        #expect(CompanionWeekWords.diaryTitle(plant) == "Watering diary")
        #expect(CompanionWeekWords.trailMeta(plant) == "who watered, each slot")
        #expect(CompanionWeekWords.podiumTitle(plant) == "Gardener of the week")
        #expect(plant.sentence(who: "Mia", name: "Fern") == "Mia watered Fern")
        #expect(plant.pastVerb == "Watered")

        // Every other kind reads the same for any companion.
        #expect(CareWords(F.walk, species: .dog) == CareWords(kind: .walk, title: "Walk", species: .dog))
        #expect(CareWords(kind: .feed, title: "Feed", species: .cat).noun == CareWords(kind: .feed, title: "Feed", species: .plant).noun)
        #expect(CompanionPresets.welcome(name: "Yo-Yo", species: .dog, routines: [CareRoutineDraft(kind: .water, windows: [.hours("Morning", 7, 11)], stars: 1)])
            == "Yo-Yo has joined the household and expects one refill a day. Zero excuses.")
    }

    @Test("The words follow the companion, from the snapshot and on the page")
    func wordsOnThePage() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        var dog = CompanionDraft.new(species: .dog)
        dog.name = "Yo-Yo"
        dog.routines.append(CareRoutineDraft(kind: .water, windows: [.hours("Morning", 7, 11)], stars: 1))
        var fern = CompanionDraft.new(species: .plant)
        fern.name = "Fern"
        let dogId = try db.saveCompanion(dog, householdId: household.id)
        let fernId = try db.saveCompanion(fern, householdId: household.id)
        let snapshot = try db.writer.read(CompanionSnapshot.fetch)
        let bowl = try #require(snapshot.routines(of: dogId).first { $0.kind == .water })
        let soil = try #require(snapshot.routines(of: fernId).first { $0.kind == .water })
        #expect(snapshot.words(bowl).noun == "refill")
        #expect(snapshot.words(soil).noun == "watering")
        let report = try #require(CompanionReport.make(snapshot: snapshot, companionId: dogId, now: CompanionClock.now()))
        #expect(report.week(of: bowl.id)?.words.isBowl == true)
        #expect(report.week(of: bowl.id).map { CompanionWeekWords.podiumTitle($0.words) } == "Bartender of the week")
    }

    @Test("A slot that closed before the companion arrived is owed nowhere: trail, numbers, streak, missed")
    func owed() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let james = try db.snapshot().people[0].id
        let calendar = try #require(try db.snapshot().household).calendar
        let today = DayKey(CompanionClock.now(), calendar: calendar)
        let arrived = CareLogic.date(today, minute: 18 * 60 + 30, calendar: calendar)
        var draft = CompanionDraft.new(species: .rabbit)
        draft.name = "Pip"
        let id = try db.saveCompanion(draft, householdId: household.id, now: arrived)

        // Added at 6:30 pm: breakfast (6-9 am) was never owed, dinner (5-7 pm) is open.
        var snapshot = try db.writer.read(CompanionSnapshot.fetch)
        var report = try #require(CompanionReport.make(snapshot: snapshot, companionId: id, now: arrived))
        var meals = try #require(report.weeks.first { $0.routine.kind == .feed })
        let breakfast = try #require(meals.trail[6].first { $0.index == 0 })
        #expect(!CareLogic.isOwed(breakfast, of: meals.routine, on: today, since: arrived, now: arrived, calendar: calendar))
        #expect(meals.tap(breakfast, on: today) == nil, "the trail draws it as a plain dot")
        #expect(meals.trailLabel(breakfast, window: breakfast.window, on: today, snapshot: snapshot).hasSuffix("not due"))
        #expect(meals.stats.slotsSoFar == 0, "nothing owed yet")
        #expect(meals.tiles(calendar: calendar)[2] == .init(value: "-", unit: nil, label: "slots on time"), "no score, not a failing one")
        #expect(meals.missed.isEmpty && meals.late.isEmpty && report.missed.isEmpty)

        // Dinner at 6:40 pm completes the first day: breakfast doesn't count against it.
        let dinnerAt = CareLogic.date(today, minute: 18 * 60 + 40, calendar: calendar)
        try db.logCare(routineId: meals.routine.id, CareLogDraft(people: [james], occurredAt: dinnerAt), now: dinnerAt)
        snapshot = try db.writer.read(CompanionSnapshot.fetch)
        report = try #require(CompanionReport.make(snapshot: snapshot, companionId: id, now: dinnerAt))
        meals = try #require(report.weeks.first { $0.routine.kind == .feed })
        #expect(meals.stats.slotsSoFar == 1 && meals.stats.slotsOnTime == 1)
        #expect(meals.tiles(calendar: calendar)[2].value == "1/1")
        #expect(meals.streak == 1, "a whole first day")
        #expect(CareLogic.onTimeRun(for: meals.routine, entries: snapshot.entries(of: meals.routine.id), now: dinnerAt, calendar: calendar, since: arrived) == 1)
        #expect(CareLogic.streak(for: meals.routine, entries: snapshot.entries(of: meals.routine.id), now: dinnerAt, calendar: calendar, since: nil) == 0,
                "and the day would not be whole")
    }

    @Test("The page's words, from the routine's kind")
    func words() throws {
        let week = try week()
        let walk = week.walks.words
        let feed = week.meals.words
        #expect(CompanionWeekWords.diaryTitle(walk) == "Walk diary")
        #expect(CompanionWeekWords.diaryTitle(feed) == "Meal diary")
        #expect(CompanionWeekWords.podiumTitle(feed) == "Chef of the week")
        #expect(CompanionWeekWords.trailMeta(walk) == "who walked, each slot")
        #expect(CompanionWeekWords.trailMeta(feed) == "who fed, each slot")
        let litter = CareWords(kind: .litter, title: "Litter", species: .cat)
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
