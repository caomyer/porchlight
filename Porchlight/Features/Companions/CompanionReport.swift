import Foundation

/// One routine's state today: its slots and the latest log.
struct RoutineToday: Identifiable, Equatable {
    var routine: CareRoutine
    var slots: [CareSlot]
    var lastEntry: CareEntry?

    var id: Int64 { routine.id ?? 0 }
    var doneCount: Int { slots.filter(\.isDone).count }
    var isComplete: Bool { slots.allSatisfy(\.isDone) }
}

struct DiaryItem: Identifiable, Equatable {
    var entry: CareEntry
    var caption: String?
    var id: Int64 { entry.id }
}

struct Milestone: Identifiable, Equatable {
    enum Tint: Equatable {
        case companion
        case person(Int64)
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
    var routines: [CareRoutine]
    var primary: RoutineToday?
    var others: [RoutineToday]
    var mood: Double?
    var streak: Int
    var today: DayKey
    var now: Date
    var weekDays: [DayKey]
    /// The primary routine's slots for each day of the week.
    var trail: [[CareSlot]]
    var weekStats: CareLogic.WeekStats
    var leaderboard: [CareLogic.Standing]
    var diary: [DiaryItem]
    var milestones: [Milestone]

    var id: Int64 { companion.id ?? 0 }
    var name: String { companion.name }
    var look: CompanionLook { CompanionLook(companion) }
    var expression: FaceExpression { FaceExpression(mood: mood) }
    var moodLabel: (emoji: String, label: String)? {
        mood.map { CompanionPresets.mood(for: companion.species, level: $0) }
    }

    var primaryRoutine: CareRoutine? { primary?.routine }
    var noun: String { primaryRoutine.map { $0.kind.noun(title: $0.title) } ?? "care" }

    static func make(snapshot: CompanionSnapshot, companionId: Int64, now: Date) -> CompanionReport? {
        guard let companion = snapshot.companions.first(where: { $0.id == companionId }) else { return nil }
        let calendar = snapshot.calendar
        let routines = snapshot.routines(of: companionId)
        let today = DayKey(now, calendar: calendar)
        // The last 7 days ending today, so the page is never empty at the start of a week
        // (matches the food diary's week).
        let weekDays = (-6...0).map { today.adding(days: $0, calendar: calendar) }
        let peopleOrder = snapshot.people.compactMap(\.id)

        let todays = routines.map { routine in
            routineToday(routine, entries: snapshot.entries(of: routine.id), today: today, now: now, calendar: calendar)
        }
        guard let primary = todays.first else {
            return CompanionReport(
                companion: companion, routines: [], primary: nil, others: [], mood: nil, streak: 0, today: today, now: now,
                weekDays: weekDays, trail: weekDays.map { _ in [] }, weekStats: .init(), leaderboard: [], diary: [], milestones: []
            )
        }
        let routine = primary.routine
        let entries = snapshot.entries(of: routine.id)
        let byDay = CareLogic.byDay(entries, calendar: calendar)
        let weekEntries = entries.filter { weekDays.contains(DayKey($0.time, calendar: calendar)) }
        let captions = CaptionEngine.captions(
            for: entries, tone: companion.captionTone, name: companion.name, routine: routine,
            names: snapshot.names, calendar: calendar
        )
        return CompanionReport(
            companion: companion,
            routines: routines,
            primary: primary,
            others: Array(todays.dropFirst()),
            mood: CareLogic.mood(lastCare: entries.last?.time, interval: CareLogic.interval(for: routine), now: now),
            streak: CareLogic.streak(for: routine, entries: entries, now: now, calendar: calendar),
            today: today,
            now: now,
            weekDays: weekDays,
            trail: weekDays.map { CareLogic.slots(for: routine, on: $0, byDay: byDay, now: now, calendar: calendar) },
            weekStats: CareLogic.weekStats(for: routine, entries: entries, days: weekDays, now: now, calendar: calendar),
            leaderboard: CareLogic.leaderboard(weekEntries, people: peopleOrder),
            diary: weekEntries.reversed().map { DiaryItem(entry: $0, caption: captions[$0.id]) },
            milestones: milestones(routine: routine, entries: entries, snapshot: snapshot, now: now, calendar: calendar)
        )
    }

    static func routineToday(_ routine: CareRoutine, entries: [CareEntry], today: DayKey, now: Date, calendar: Calendar) -> RoutineToday {
        let byDay = CareLogic.byDay(entries, calendar: calendar)
        let slots = CareLogic.slots(for: routine, on: today, byDay: byDay, now: now, calendar: calendar)
        return RoutineToday(routine: routine, slots: slots, lastEntry: entries.last)
    }

    // MARK: Milestones

    static func milestones(routine: CareRoutine, entries: [CareEntry], snapshot: CompanionSnapshot, now: Date, calendar: Calendar) -> [Milestone] {
        let noun = routine.kind.noun(title: routine.title)
        var list: [Milestone] = []

        if !entries.isEmpty && !routine.effectiveWindows.allSatisfy(\.isAllDay) {
            let run = CareLogic.onTimeRun(for: routine, entries: entries, now: now, calendar: calendar)
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
            var counts: [Int64: Int] = [:]
            for entry in soggy { for person in entry.people { counts[person, default: 0] += 1 } }
            let order = snapshot.people.compactMap(\.id)
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

    static func tint(for people: [Int64]) -> Milestone.Tint {
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
