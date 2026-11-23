import Foundation

/// One routine's state today: its slots and the latest log.
struct RoutineToday: Identifiable, Equatable {
    var routine: CareRoutine
    var slots: [CareSlot]
    var lastEntry: CareEntry?

    var id: CareRoutine.ID { routine.id }
    var doneCount: Int { slots.filter(\.isDone).count }
    var isComplete: Bool { slots.allSatisfy(\.isDone) }
}

struct DiaryItem: Identifiable, Equatable {
    var entry: CareEntry
    var caption: String?
    var id: CareLog.ID { entry.id }
}

struct Milestone: Identifiable, Equatable {
    enum Tint: Equatable {
        case companion
        case person(Person.ID)
        case together
    }

    var id: String
    var emoji: String
    var title: String
    var detail: String
    var tint: Tint
}

/// Everything a companion's Today card and page show, computed from a snapshot at `now`.
struct CompanionReport {
    var companion: Companion
    var look: CompanionLook
    var routines: [CareRoutine]
    var primary: RoutineToday?
    var others: [RoutineToday]
    var mood: Double?
    var today: DayKey
    var now: Date
    /// The week the page shows: seven days, this week's ending today.
    var weekDays: [DayKey]
    /// Weeks before this one the page shows (`WeekPaging`); 0 is this week.
    var weeksBack = 0
    /// How far back the page goes: the week of the companion's arrival or first log.
    var weeksBackLimit = 0
    /// Each routine's week, in the routines' order. The first is the primary routine's,
    /// which the wall's companion page shows and the phone's opens on.
    var weeks: [RoutineWeek]
    /// Every routine's slots this week that were never logged, newest first.
    var missed: [MissedCare]

    var id: Companion.ID { companion.id }
    var name: String { companion.name }
    var expression: FaceExpression { FaceExpression(mood: mood) }
    var moodLabel: (emoji: String, label: String)? {
        mood.map { CompanionPresets.mood(for: companion.species, level: $0) }
    }

    var primaryRoutine: CareRoutine? { primary?.routine }
    var primaryWeek: RoutineWeek? { weeks.first }
    /// What the primary routine's care is called, for what this companion is.
    var words: CareWords? { primaryRoutine.map { CareWords($0, species: companion.species) } }
    var noun: String { words?.noun ?? "care" }

    /// The primary routine's slots for each day of the week.
    var trail: [[CareSlot]] { primaryWeek?.trail ?? weekDays.map { _ in [] } }
    var weekStats: CareLogic.WeekStats { primaryWeek?.stats ?? .init() }
    var streak: Int { primaryWeek?.streak ?? 0 }
    var leaderboard: [CareLogic.Standing] { primaryWeek?.leaderboard ?? [] }
    var diary: [DiaryItem] { primaryWeek?.diary ?? [] }
    var milestones: [Milestone] { primaryWeek?.milestones ?? [] }

    /// A routine's week, or nil when the routine is no longer this companion's.
    func week(of routineId: CareRoutine.ID?) -> RoutineWeek? {
        weeks.first { $0.id == routineId }
    }

    /// `weeksBack`: an earlier week for the page (docs/design/companion-care.md, "Earlier
    /// weeks"); everything about now (today's slots, the mood, the streak, what can be caught
    /// up on) stays now's.
    static func make(snapshot: CompanionSnapshot, companionId: Companion.ID, now: Date, weeksBack: Int = 0) -> CompanionReport? {
        guard let companion = snapshot.companions.first(where: { $0.id == companionId }) else { return nil }
        let calendar = snapshot.calendar
        let routines = snapshot.routines(of: companionId)
        let today = DayKey(now, calendar: calendar)
        // Back to the week of its arrival or its first log, whichever is earlier.
        let firstLog = routines.compactMap { snapshot.entries(of: $0.id).first.map { DayKey($0.time, calendar: calendar) } }.min()
        let limit = WeekPaging.weeksBackLimit(firstDay: [DayKey(companion.createdAt, calendar: calendar), firstLog].compactMap { $0 }.min(), today: today, calendar: calendar)
        let shown = min(max(weeksBack, 0), limit)
        // The 7 days ending today, so the page is never empty at the start of a week
        // (matches the food diary's week), or as many weeks before as asked.
        let weekDays = WeekPaging.week(endingOn: today, weeksBack: shown, calendar: calendar)

        let todays = routines.map { routine in
            routineToday(routine, entries: snapshot.entries(of: routine.id), today: today, now: now, calendar: calendar)
        }
        // What can be caught up on is now's rule (`CareCatchUp.daysBack`); on an earlier
        // week, only what of it falls in that week.
        let missed = CareCatchUp.missed(routines, entries: { snapshot.entries(of: $0.id) }, now: now, calendar: calendar, since: companion.createdAt)
            .filter { shown == 0 || weekDays.contains($0.day) }
        let weeks = routines.map { routine in
            RoutineWeek.make(
                routine, companion: companion, snapshot: snapshot, weekDays: weekDays,
                missed: missed.filter { $0.routine.id == routine.id }, now: now
            )
        }
        // The mood follows the primary routine, the one the companion waits for most.
        let mood = routines.first.flatMap { routine in
            CareLogic.mood(lastCare: snapshot.entries(of: routine.id).last?.time, interval: CareLogic.interval(for: routine), now: now)
        }
        return CompanionReport(
            companion: companion,
            look: snapshot.look(of: companion),
            routines: routines,
            primary: todays.first,
            others: Array(todays.dropFirst()),
            mood: mood,
            today: today,
            now: now,
            weekDays: weekDays,
            weeksBack: shown,
            weeksBackLimit: limit,
            weeks: weeks,
            missed: missed
        )
    }

    static func routineToday(_ routine: CareRoutine, entries: [CareEntry], today: DayKey, now: Date, calendar: Calendar) -> RoutineToday {
        let byDay = CareLogic.byDay(entries, calendar: calendar)
        let slots = CareLogic.slots(for: routine, on: today, byDay: byDay, now: now, calendar: calendar)
        return RoutineToday(routine: routine, slots: slots, lastEntry: entries.last)
    }

    // MARK: Milestones

    static func milestones(routine: CareRoutine, words: CareWords, entries: [CareEntry], snapshot: CompanionSnapshot, now: Date, calendar: Calendar, since added: Date?) -> [Milestone] {
        let noun = words.noun
        var list: [Milestone] = []

        if !entries.isEmpty && !routine.effectiveWindows.allSatisfy(\.isAllDay) {
            let run = CareLogic.onTimeRun(for: routine, entries: entries, now: now, calendar: calendar, since: added)
            let target = CareLogic.nextMilestone(after: run, in: CareLogic.runMilestones)
            list.append(Milestone(
                id: "run", emoji: "🏅", title: "\(target) \(noun)s in a row on time",
                detail: "\(target - run) more to go", tint: .companion
            ))
        }

        if let longest = entries.filter({ $0.log.durationMinutes != nil }).max(by: { ($0.log.durationMinutes ?? 0) < ($1.log.durationMinutes ?? 0) }),
           let minutes = longest.log.durationMinutes {
            list.append(Milestone(
                id: "longest", emoji: "🥾", title: "Longest \(noun): \(durationText(minutes))",
                detail: "\(CaptionEngine.whoText(longest.people, names: snapshot.names)) · \(dayText(longest.time, now: now, calendar: calendar))",
                tint: tint(for: longest.people)
            ))
        }

        let soggy = entries.filter { $0.log.vibe == .soggy }
        if !soggy.isEmpty {
            var counts: [Person.ID: Int] = [:]
            for entry in soggy { for person in entry.people { counts[person, default: 0] += 1 } }
            let order = snapshot.everyone.map(\.id)
            if let hero = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : (order.firstIndex(of: $0.key) ?? 0) > (order.firstIndex(of: $1.key) ?? 0) }) {
                let name = snapshot.names[hero.key] ?? "Someone"
                list.append(Milestone(
                    id: "rain", emoji: "🌧", title: "Rain \(noun) hero",
                    detail: "\(name) · \(hero.value) soggy \(hero.value == 1 ? noun : noun + "s")", tint: .person(hero.key)
                ))
            }
        }

        let squirrels = entries.filter { $0.log.vibe == .squirrel }.count
        if squirrels > 0 {
            list.append(Milestone(id: "squirrel", emoji: "🐿️", title: "Squirrel watch", detail: "\(squirrels) pursued · 0 caught, ever", tint: .companion))
        }

        let friends = entries.filter { $0.log.vibe == .friend }.count
        if friends > 0 {
            list.append(Milestone(id: "friends", emoji: "🐕", title: "Social butterfly", detail: "\(friends) new \(friends == 1 ? "friend" : "friends") made", tint: .together))
        }

        let total = entries.count
        let target = CareLogic.nextMilestone(after: total, in: CareLogic.countMilestones)
        list.append(Milestone(
            id: "total", emoji: "🎯",
            title: total == 0 ? "First \(noun) coming up" : "\(CaptionEngine.ordinal(target)) \(noun) coming up",
            detail: total == 0 ? "Log it to start the story" : "\(total) so far · \(target - total) more to go",
            tint: .companion
        ))
        return Array(list.prefix(4))
    }

    static func tint(for people: [Person.ID]) -> Milestone.Tint {
        people.count == 1 ? .person(people[0]) : .together
    }

    static func durationText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min")
    }

    /// "Today", "Sunday" within the last week, else "Oct 3".
    static func dayText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6:
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        default:
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return formatter.string(from: date)
    }
}

extension CompanionReport {
    /// "13 walks · 5h 50m outside · 4 squirrels pursued, 0 caught": the primary routine's
    /// week in a line, under the title of the wall's companion page and the phone's.
    var weekSummary: String { primaryWeek?.summary ?? "0 cares" }

    /// The week shown, for the pagers: "Last week, Nov 4 to 10, 9 walks".
    func weekSpoken(_ week: RoutineWeek?, calendar: Calendar) -> String {
        let count = week.map { "\($0.stats.count) \($0.stats.count == 1 ? $0.noun : $0.noun + "s")" }
        return ([WeekPaging.weekName(weeksBack: weeksBack), WeekPaging.range(weekDays, calendar: calendar)] + [count].compactMap { $0 }).joined(separator: ", ")
    }

    /// The page's line under its title: this week's summary, or which week it is and its.
    func weekLine(calendar: Calendar) -> String {
        guard weeksBack > 0 else { return weekSummary }
        let summary = (primaryWeek?.stats.count ?? 0) == 0 ? "nothing logged" : weekSummary
        return "\(WeekPaging.range(weekDays, calendar: calendar)) · \(summary)"
    }

    /// "Toy poodle · 4 yrs": what the companion is, and how old, under its name.
    func aboutLine(calendar: Calendar) -> String {
        var parts: [String] = []
        let about = companion.about
        parts.append(about.isEmpty ? companion.species.label : about)
        if let birth = companion.birthDate {
            let years = calendar.dateComponents([.year], from: birth, to: now).year ?? 0
            let months = calendar.dateComponents([.month], from: birth, to: now).month ?? 0
            parts.append(years >= 1 ? "\(years) \(years == 1 ? "yr" : "yrs")" : "\(max(months, 1)) mo")
        }
        return parts.joined(separator: " · ")
    }

    /// "🙂 Doing fine", or what it waits for before anything was logged.
    var moodText: String {
        guard let mood = moodLabel else { return words.map(CompanionWeekWords.waitingForFirst) ?? "Waiting for first care" }
        return "\(mood.emoji) \(mood.label)"
    }
}
