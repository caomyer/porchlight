import Foundation
import Testing
@testable import Porchlight

/// Pure rules: recurrence, board, stars, rewards, sections, meals and night hours.
@Suite("Home logic")
struct HomeLogicTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private var calendar: Calendar { Self.calendar }

    /// 2026-11-01 is a Sunday.
    private func day(_ raw: String) -> DayKey { DayKey(rawValue: raw) }

    static func chore(
        id: Int = 1,
        owner: Person.ID? = 1,
        _ recurrence: Recurrence,
        anchor: String = "2026-11-01",
        stars: Int = 1,
        archived: Bool = false
    ) -> Chore {
        var chore = Chore(
            id: .number(id), householdId: 1, title: "Chore \(id)", ownerId: owner, repeatKind: "daily", weekdayMask: 0,
            intervalDays: 1, anchorDay: anchor, stars: stars, archived: archived, sortOrder: Int(id), createdAt: .now
        )
        chore.recurrence = recurrence
        return chore
    }

    static func done(_ choreId: Chore.ID, _ day: String, by person: Person.ID?, stars: Int = 1) -> ChoreCompletion {
        ChoreCompletion(choreId: choreId, day: DayKey(rawValue: day), personId: person, stars: stars, completedAt: .now)
    }

    /// The ledger's view of completions (what star totals and rewards add up).
    static func earnings(_ completions: [ChoreCompletion]) -> [StarEarning] {
        completions.enumerated().map { index, completion in
            StarEarning(
                source: .chore(choreId: completion.choreId, completionId: .number(index + 1)),
                personId: completion.personId, stars: completion.stars, day: completion.dayKey,
                at: completion.completedAt, recordedAt: completion.completedAt, title: "Chore \(completion.choreId.number)", emoji: "✅"
            )
        }
    }

    // MARK: Recurrence

    @Test("Daily chores occur every day from their start day on")
    func daily() {
        let chore = Self.chore(.daily, anchor: "2026-11-03")
        #expect(!ChoreSchedule.occurs(chore, on: day("2026-11-02"), calendar: calendar))
        #expect(ChoreSchedule.occurs(chore, on: day("2026-11-03"), calendar: calendar))
        #expect(ChoreSchedule.occurs(chore, on: day("2027-02-28"), calendar: calendar))
    }

    @Test("Weekday chores occur only on the chosen weekdays")
    func weekdays() {
        // Monday (2) and Thursday (5)
        let chore = Self.chore(.weekdays([2, 5]))
        let hits = (1...14).map { String(format: "2026-11-%02d", $0) }.filter {
            ChoreSchedule.occurs(chore, on: day($0), calendar: calendar)
        }
        #expect(hits == ["2026-11-02", "2026-11-05", "2026-11-09", "2026-11-12"])
    }

    @Test("Weekday chores don't occur before their start day")
    func weekdaysStart() {
        let chore = Self.chore(.weekdays([2]), anchor: "2026-11-05")
        #expect(!ChoreSchedule.occurs(chore, on: day("2026-11-02"), calendar: calendar))
        #expect(ChoreSchedule.occurs(chore, on: day("2026-11-09"), calendar: calendar))
    }

    @Test("Every-N-days chores count from their anchor day")
    func everyNDays() {
        let chore = Self.chore(.everyNDays(3), anchor: "2026-11-02")
        #expect(!ChoreSchedule.occurs(chore, on: day("2026-10-30"), calendar: calendar))
        #expect(ChoreSchedule.occurs(chore, on: day("2026-11-02"), calendar: calendar))
        #expect(!ChoreSchedule.occurs(chore, on: day("2026-11-03"), calendar: calendar))
        #expect(!ChoreSchedule.occurs(chore, on: day("2026-11-04"), calendar: calendar))
        #expect(ChoreSchedule.occurs(chore, on: day("2026-11-05"), calendar: calendar))
        // Across a month end and the US DST change on 2026-11-01.
        #expect(ChoreSchedule.occurs(chore, on: day("2026-12-02"), calendar: calendar))
    }

    @Test("Every-N-days stays on rhythm across a DST change")
    func everyNDaysAcrossDST() {
        // Clocks fall back in Los Angeles on 2026-11-01.
        let chore = Self.chore(.everyNDays(2), anchor: "2026-10-30")
        #expect(ChoreSchedule.occurs(chore, on: day("2026-11-01"), calendar: calendar))
        #expect(ChoreSchedule.occurs(chore, on: day("2026-11-03"), calendar: calendar))
        #expect(!ChoreSchedule.occurs(chore, on: day("2026-11-02"), calendar: calendar))
    }

    @Test("One-off chores occur on their due day only, but stay on the board until done")
    func once() {
        let chore = Self.chore(id: 7, .once, anchor: "2026-11-06")
        #expect(ChoreSchedule.occurs(chore, on: day("2026-11-06"), calendar: calendar))
        #expect(!ChoreSchedule.occurs(chore, on: day("2026-11-05"), calendar: calendar))
        // Open: on the board early and when overdue.
        #expect(ChoreSchedule.isOnBoard(chore, on: day("2026-11-02"), completions: [], calendar: calendar))
        #expect(ChoreSchedule.isOnBoard(chore, on: day("2026-11-09"), completions: [], calendar: calendar))
        // Done on the 4th: only on the board that day.
        let done = [Self.done(7, "2026-11-04", by: 1)]
        #expect(ChoreSchedule.isOnBoard(chore, on: day("2026-11-04"), completions: done, calendar: calendar))
        #expect(!ChoreSchedule.isOnBoard(chore, on: day("2026-11-05"), completions: done, calendar: calendar))
    }

    @Test("Archived chores never show on the board")
    func archived() {
        let chore = Self.chore(.daily, archived: true)
        #expect(!ChoreSchedule.isOnBoard(chore, on: day("2026-11-04"), completions: [], calendar: calendar))
    }

    @Test("Recurrence round-trips through its stored columns")
    func recurrenceStorage() {
        for recurrence: Recurrence in [.daily, .weekdays([1, 4, 7]), .everyNDays(10), .once] {
            #expect(Self.chore(recurrence).recurrence == recurrence)
        }
        #expect(Recurrence.mask(for: [1, 7]) == 0b100_0001)
        #expect(Recurrence.weekdays(fromMask: 0b100_0001) == [1, 7])
    }

    @Test("Subtitles prefer the time hint, then describe the schedule")
    func subtitles() {
        var chore = Self.chore(.everyNDays(3))
        let today = day("2026-11-04")
        #expect(ChoreSchedule.subtitle(for: chore, today: today, calendar: calendar) == "every 3 days")
        chore.timeHint = "before noon"
        #expect(ChoreSchedule.subtitle(for: chore, today: today, calendar: calendar) == "before noon")
        #expect(ChoreSchedule.describe(Self.chore(.weekdays([2, 3, 4, 5, 6])), today: today, calendar: calendar) == "weekdays")
        #expect(ChoreSchedule.describe(Self.chore(.weekdays([1, 7])), today: today, calendar: calendar) == "weekends")
        #expect(ChoreSchedule.describe(Self.chore(.weekdays([6, 2])), today: today, calendar: calendar) == "Mon, Fri")
        #expect(ChoreSchedule.describe(Self.chore(.once, anchor: "2026-11-04"), today: today, calendar: calendar) == "due today")
        #expect(ChoreSchedule.describe(Self.chore(.once, anchor: "2026-11-05"), today: today, calendar: calendar) == "due tomorrow")
        #expect(ChoreSchedule.describe(Self.chore(.once, anchor: "2026-11-07"), today: today, calendar: calendar) == "due Saturday")
        #expect(ChoreSchedule.describe(Self.chore(.once, anchor: "2026-11-02"), today: today, calendar: calendar) == "overdue")
    }

    @Test("Weekdays are listed from the calendar's first weekday")
    func orderedWeekdays() {
        var monday = calendar
        monday.firstWeekday = 2
        #expect(Recurrence.orderedWeekdays(calendar: calendar) == [1, 2, 3, 4, 5, 6, 7])
        #expect(Recurrence.orderedWeekdays(calendar: monday) == [2, 3, 4, 5, 6, 7, 1])
    }

    // MARK: Board and stars

    private func person(_ id: Int, _ name: String) -> Person {
        Person(id: .number(id), householdId: 1, name: name, color: .blue, sortOrder: id, createdAt: .now)
    }

    @Test("The board has a column per person and an Anyone column only when needed")
    func boardColumns() {
        let people = [person(1, "A"), person(2, "B")]
        let today = day("2026-11-04")
        let owned = [Self.chore(id: 1, owner: 1, .daily), Self.chore(id: 2, owner: 1, .weekdays([1]))]
        let board = ChoreBoard(people: people, chores: owned, completions: [], earnings: [], rewards: [], today: today, calendar: calendar)
        #expect(board.columns.map(\.owner) == [.person(1), .person(2)])
        // Sunday-only chore isn't due on a Wednesday.
        #expect(board.columns[0].tasks.map(\.id) == [1])
        #expect(board.columns[1].tasks.isEmpty)

        let shared = owned + [Self.chore(id: 3, owner: nil, .daily)]
        let withShared = ChoreBoard(people: people, chores: shared, completions: [], earnings: [], rewards: [], today: today, calendar: calendar)
        #expect(withShared.columns.map(\.owner) == [.person(1), .person(2), .everyone])
    }

    @Test("Done counts and week stars per column")
    func boardStars() {
        let people = [person(1, "A"), person(2, "B")]
        let today = day("2026-11-04")
        let chores = [
            Self.chore(id: 1, owner: 1, .daily, stars: 2),
            Self.chore(id: 2, owner: 2, .daily),
            Self.chore(id: 3, owner: nil, .daily, stars: 3),
        ]
        let completions = [
            Self.done(1, "2026-11-04", by: 1, stars: 2),
            Self.done(1, "2026-11-02", by: 1, stars: 2),
            Self.done(1, "2026-10-31", by: 1, stars: 2), // last week
            Self.done(3, "2026-11-03", by: 2, stars: 3), // B did a shared chore
            Self.done(3, "2026-11-04", by: 1, stars: 3),
        ]
        let board = ChoreBoard(people: people, chores: chores, completions: completions, earnings: Self.earnings(completions), rewards: [], today: today, calendar: calendar)
        let columns = Dictionary(uniqueKeysWithValues: board.columns.map { ($0.owner, $0) })
        #expect(columns[.person(1)]?.doneCount == 1)
        #expect(columns[.person(1)]?.weekStars == 2 + 2 + 3)
        #expect(columns[.person(2)]?.doneCount == 0)
        #expect(columns[.person(2)]?.weekStars == 3)
        #expect(columns[.everyone]?.doneCount == 1)
        #expect(columns[.everyone]?.weekStars == 6)

        let totals = StarTotals.byPerson(Self.earnings(completions), in: HomeWeek(containing: today, calendar: calendar))
        #expect(totals == [1: 7, 2: 3])
    }

    @Test("The household week follows the first weekday")
    func week() {
        let week = HomeWeek(containing: day("2026-11-04"), calendar: calendar)
        #expect(week.first == day("2026-11-01"))
        #expect(week.last == day("2026-11-07"))
        #expect(week.contains(day("2026-11-07")))
        #expect(!week.contains(day("2026-11-08")))
        var monday = calendar
        monday.firstWeekday = 2
        #expect(HomeWeek(containing: day("2026-11-01"), calendar: monday).first == day("2026-10-26"))
    }

    // MARK: Rewards

    private func reward(id: Reward.ID, owner: Person.ID?, target: Int, start: String) -> Reward {
        Reward(id: id, householdId: 1, title: "R", targetStars: target, ownerId: owner, startDay: start, archived: false, sortOrder: 0, createdAt: .now)
    }

    @Test("Personal rewards count their owner's stars since they started")
    func personalReward() {
        let completions = [
            Self.done(1, "2026-10-30", by: 1, stars: 5), // before start
            Self.done(1, "2026-11-01", by: 1, stars: 2),
            Self.done(2, "2026-11-02", by: 2, stars: 4), // someone else
            Self.done(3, "2026-11-03", by: 1, stars: 3),
        ]
        let reward = reward(id: 1, owner: 1, target: 10, start: "2026-11-01")
        #expect(RewardProgress.earned(for: reward, earnings: Self.earnings(completions)) == 5)
    }

    @Test("Shared goals count everyone's stars, and progress caps at the target")
    func sharedReward() {
        let completions = [
            Self.done(1, "2026-11-01", by: 1, stars: 2),
            Self.done(2, "2026-11-02", by: 2, stars: 4),
            Self.done(3, "2026-11-03", by: nil, stars: 1), // person since removed
        ]
        let goal = reward(id: 1, owner: nil, target: 5, start: "2026-11-01")
        let status = ChoreBoard.RewardStatus(reward: goal, earned: RewardProgress.earned(for: goal, earnings: Self.earnings(completions)))
        #expect(status.earned == 7)
        #expect(status.isReached)
        #expect(status.fraction == 1)
        let half = ChoreBoard.RewardStatus(reward: reward(id: 2, owner: nil, target: 14, start: "2026-11-01"), earned: 7)
        #expect(half.fraction == 0.5)
        #expect(!half.isReached)
    }

    @Test("Rewards land in their owner's column; shared goals in Anyone")
    func rewardColumns() {
        let people = [person(1, "A")]
        let rewards = [
            reward(id: 1, owner: 1, target: 10, start: "2026-11-01"),
            reward(id: 2, owner: nil, target: 100, start: "2026-11-01"),
        ]
        let board = ChoreBoard(people: people, chores: [], completions: [], earnings: [], rewards: rewards, today: day("2026-11-04"), calendar: calendar)
        #expect(board.columns.map(\.owner) == [.person(1), .everyone])
        #expect(board.columns[0].rewards.map(\.id) == [1])
        #expect(board.columns[1].rewards.map(\.id) == [2])
    }

    // MARK: Week overview

    @Test("Week marks show done, open and unscheduled days")
    func weekMarks() {
        let chore = Self.chore(id: 1, .weekdays([2, 4]))
        let completions = [Self.done(1, "2026-11-02", by: 2)]
        #expect(WeekMark.mark(for: chore, on: day("2026-11-02"), completions: completions, calendar: calendar) == .done(personId: 2))
        #expect(WeekMark.mark(for: chore, on: day("2026-11-04"), completions: completions, calendar: calendar) == .open)
        #expect(WeekMark.mark(for: chore, on: day("2026-11-03"), completions: completions, calendar: calendar) == .none)

        let once = Self.chore(id: 2, .once, anchor: "2026-11-06")
        #expect(WeekMark.mark(for: once, on: day("2026-11-06"), completions: [], calendar: calendar) == .open)
        let early = [Self.done(2, "2026-11-03", by: 1)]
        #expect(WeekMark.mark(for: once, on: day("2026-11-03"), completions: early, calendar: calendar) == .done(personId: 1))
        #expect(WeekMark.mark(for: once, on: day("2026-11-06"), completions: early, calendar: calendar) == .none)
    }

    // MARK: Groceries

    @Test("Grocery sections are guessed from keywords", arguments: [
        ("Avocados ×3", "Produce"), ("Basil", "Produce"), ("Scallions", "Produce"), ("Limes", "Produce"),
        ("Oat milk", "Dairy"), ("Parmesan", "Dairy"), ("Greek yogurt", "Dairy"), ("Eggs", "Dairy"),
        ("White miso", "Pantry"), ("Rice", "Pantry"), ("Peanut butter", "Pantry"), ("Tomato paste", "Pantry"),
        ("Sourdough loaf", "Bakery"), ("Chicken thighs", "Meat & fish"), ("Ice cream", "Frozen"),
        ("Paper towels", "Household"), ("Candles", "Household"), ("Sparkling water", "Drinks"),
        ("Cherries", "Produce"), ("Potatoes", "Produce"), ("Gift wrap for Sam", "Household"), ("Thing-a-ma-jig", "Other"),
    ])
    func grocerySections(item: String, section: String) {
        #expect(GrocerySections.guess(item) == section)
    }

    @Test("Sections sort by aisle, custom ones next, Other last")
    func sectionOrder() {
        let ordered = GrocerySections.ordered(["Other", "Pantry", "For the party", "Produce", "Dairy", "Camping", "Pantry"])
        #expect(ordered == ["Produce", "Dairy", "Pantry", "Camping", "For the party", "Other"])
    }

    @Test("Grocery columns split where the taller column is shortest")
    func columnSplit() {
        #expect(GrocerySections.columnSplit([4, 3, 3, 2]) == 2)
        #expect(GrocerySections.columnSplit([10, 1, 1]) == 1)
        #expect(GrocerySections.columnSplit([1, 1, 10]) == 2)
        #expect(GrocerySections.columnSplit([5]) == 1)
    }

    // MARK: Meals

    @Test("Meal emoji are suggested from the dinner title", arguments: [
        ("Taco Tuesday", "🌮"), ("Pesto pasta", "🍝"), ("Sushi night", "🍣"), ("Dan dan noodles", "🍜"),
        ("Miso salmon", "🐟"), ("Grandma's birthday dinner", "🎂"), ("Pizza", "🍕"),
    ])
    func mealEmoji(title: String, emoji: String) {
        #expect(MealEmoji.guess(title) == emoji)
    }

    @Test("Unknown dinners get no emoji guess, and words don't match inside other words")
    func mealEmojiMisses() {
        #expect(MealEmoji.guess("Something new") == nil)
        // "mac" must not match inside "stomach", "out" not inside "sprouts".
        #expect(MealEmoji.guess("Stomach-friendly sprouts") == nil)
    }

    // MARK: Night

    @Test("Night hours across midnight")
    func nightAcrossMidnight() {
        let night = NightWindow(start: 22 * 60, end: 6 * 60 + 30)
        #expect(night.contains(minuteOfDay: 22 * 60))
        #expect(night.contains(minuteOfDay: 23 * 60 + 59))
        #expect(night.contains(minuteOfDay: 0))
        #expect(night.contains(minuteOfDay: 6 * 60 + 29))
        #expect(!night.contains(minuteOfDay: 6 * 60 + 30))
        #expect(!night.contains(minuteOfDay: 12 * 60))
        #expect(!night.contains(minuteOfDay: 21 * 60 + 59))
    }

    @Test("Night hours within one day, and an empty window")
    func nightSameDay() {
        let nap = NightWindow(start: 13 * 60, end: 15 * 60)
        #expect(nap.contains(minuteOfDay: 14 * 60))
        #expect(!nap.contains(minuteOfDay: 15 * 60))
        #expect(!nap.contains(minuteOfDay: 12 * 60))
        #expect(!NightWindow(start: 600, end: 600).contains(minuteOfDay: 600))
    }

    @Test("Night hours use the calendar's time zone")
    func nightDate() throws {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 15)))
        #expect(NightWindow.default.contains(date, calendar: calendar))
        var tokyo = calendar
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        // 23:15 in Los Angeles is 16:15 in Tokyo.
        #expect(!NightWindow.default.contains(date, calendar: tokyo))
    }

    @Test("Emoji fields keep one whole character")
    func emojiText() {
        #expect(HomeText.emoji(" 🍳x ") == "🍳")
        #expect(HomeText.emoji("👨‍👩‍👧") == "👨‍👩‍👧")
        #expect(HomeText.emoji("  ") == nil)
        #expect(HomeText.emoji(nil) == nil)
    }

    // MARK: Care on the board, and Glow

    private func careTask(done: Bool) -> CareTask {
        let routine = CareRoutine(
            id: 9, companionId: 1, kind: .walk, title: "Walk", emoji: "🦮", everyDays: 1,
            windows: [.hours("Morning", 6, 10), .hours("Evening", 17, 20)], trackedFields: [], stars: 2,
            nudgeAfterMinutes: nil, sortOrder: 0
        )
        let log = CareLog(id: 1, careRoutineId: 9, occurredAt: .now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil, stars: 2, createdAt: .now)
        let slot = CareSlot(index: 0, window: routine.windows[0], entry: done ? CareEntry(log: log, people: [1]) : nil, state: done ? .done(onTime: true) : .open)
        return CareTask(companionId: 1, companionName: "Yo-Yo", routine: routine, slot: slot)
    }

    @Test("Companion care sits in Anyone with the shared chores, and counts toward its progress")
    func careOnBoard() {
        let people = [person(1, "A")]
        let board = ChoreBoard(
            people: people, chores: [], completions: [], earnings: [], care: [careTask(done: true), careTask(done: false)],
            rewards: [], today: day("2026-11-04"), calendar: calendar
        )
        let anyone = board.columns.first { $0.owner == .everyone }
        #expect(anyone?.totalCount == 2)
        #expect(anyone?.doneCount == 1)
        #expect(careTask(done: false).title == "Walk Yo-Yo · morning")
    }

    @Test("Glow adds up each person's week, compares fairly with last week, and lists what happened")
    func glow() {
        let people = [person(1, "A"), person(2, "B")]
        let completions = [
            Self.done(1, "2026-11-02", by: 1, stars: 2),
            Self.done(1, "2026-11-03", by: 1, stars: 2),
            Self.done(2, "2026-11-04", by: 2, stars: 3),
            Self.done(2, "2026-10-26", by: 2, stars: 1), // last Monday: before this point last week
            Self.done(2, "2026-10-30", by: 2, stars: 5), // last Friday: after it
        ]
        let redemption = RewardRedemption(id: 1, rewardId: 7, personId: 1, stars: 10, day: "2026-11-04", redeemedAt: .now)
        let treat = Reward(id: 7, householdId: 1, title: "Ice cream", emoji: "🍦", targetStars: 10, ownerId: 1, startDay: "2026-11-04", archived: false, sortOrder: 0, createdAt: .now)
        let summary = GlowSummary(
            people: people, earnings: Self.earnings(completions), redemptions: [redemption], rewards: [treat],
            lifetime: [1: 40], week: HomeWeek(containing: day("2026-11-04"), calendar: calendar), today: day("2026-11-04"), calendar: calendar
        )
        #expect(summary.weekStars == 7)
        #expect(summary.lastWeekStars == 6)
        #expect(summary.lastWeekSoFar == 1)
        #expect(summary.people[0].weekStars == 4 && summary.people[0].choresDone == 2 && summary.people[0].lifetimeStars == 40)
        #expect(summary.people[0].byDay == [0, 2, 2, 0, 0, 0, 0])
        #expect(summary.people[0].favorite == GlowSummary.Favorite(emoji: "✅", title: "Chore 1", count: 2))
        #expect(summary.sparks.count == 3)
        #expect(summary.feed.first?.isCashIn == true || summary.feed.first?.day == day("2026-11-04"))
        #expect(summary.feed.contains { $0.isCashIn && $0.text == "Cashed in Ice cream" })
    }

    // MARK: A day's chores

    @Test("A day's chores: done ones in the order they were done, then what is still open")
    func dayMarks() {
        let daily = Self.chore(id: 1, .daily)
        let monday = Self.chore(id: 2, owner: nil, .weekdays([2]))
        let archived = Self.chore(id: 3, .daily, archived: true)
        let oneOff = Self.chore(id: 4, .once, anchor: "2026-11-03")
        var early = Self.done(3, "2026-11-02", by: 2)
        early.completedAt = Date(timeIntervalSince1970: 1_000)
        var late = Self.done(2, "2026-11-02", by: 1)
        late.completedAt = Date(timeIntervalSince1970: 2_000)
        let chores = [daily, monday, archived, oneOff]

        let marks = ChoreDay.marks(on: day("2026-11-02"), chores: chores, completions: [late, early], calendar: calendar)
        #expect(marks.map(\.chore.id) == [3, 2, 1], "Archived chores still show what was done; open ones come last")
        #expect(marks.map(\.isDone) == [true, true, false])

        let tuesday = ChoreDay.marks(on: day("2026-11-03"), chores: chores, completions: [], calendar: calendar)
        #expect(tuesday.map(\.chore.id) == [1, 4], "A one-off shows on its due day; Monday chores don't")

        let doneEarly = [Self.done(4, "2026-11-01", by: 1)]
        let afterDone = ChoreDay.marks(on: day("2026-11-03"), chores: chores, completions: doneEarly, calendar: calendar)
        #expect(afterDone.map(\.chore.id) == [1], "A one-off done early is no longer due")
    }

    @Test("A completion sits at its check-off time, or the end of its day when checked off later")
    func completionTime() {
        let dayStart = day("2026-11-02").startDate(in: calendar)
        var onTime = Self.done(1, "2026-11-02", by: 1)
        onTime.completedAt = dayStart.addingTimeInterval(9 * 3600)
        #expect(ChoreDay.time(of: onTime, calendar: calendar) == onTime.completedAt)
        var later = onTime
        later.completedAt = dayStart.addingTimeInterval(30 * 3600)
        #expect(ChoreDay.time(of: later, calendar: calendar) == dayStart.addingTimeInterval(24 * 3600 - 60))
    }
}
