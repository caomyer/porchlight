import Foundation

/// One routine's last seven days on a companion's page: its paw trail, diary, numbers,
/// standings and milestones. The wall's page shows the primary routine's; the phone's
/// shows any routine's, one at a time. Pure and covered by CompanionWeekTests.
struct RoutineWeek: Identifiable {
    var routine: CareRoutine
    /// The routine's slots for each day of the week, oldest day first.
    var trail: [[CareSlot]]
    var stats: CareLogic.WeekStats
    var streak: Int
    var leaderboard: [CareLogic.Standing]
    /// What was logged this week, newest first.
    var diary: [DiaryItem]
    /// The routine's slots this week that were never logged, newest first.
    var missed: [MissedCare]
    /// Today's slots whose window closed without a log: caught up on for the slot itself,
    /// as Today's banner does, so a breakfast logged at 1:30 pm is breakfast, not dinner.
    var late: [MissedCare] = []
    var milestones: [Milestone]
    /// This week's, ending today; false on an earlier week, where the streak is still today's.
    var isThisWeek = true

    /// What the routine's care is called, for what its companion is.
    var words: CareWords

    var id: CareRoutine.ID { routine.id }
    /// "walk", "meal", "watering", "refill".
    var noun: String { words.noun }
    /// The diary's rows: what was logged, with what wasn't in its place, newest first.
    var rows: [DiaryRow] { DiaryRow.rows(diary, missed: missed) }

    static func make(
        _ routine: CareRoutine, companion: Companion, snapshot: CompanionSnapshot,
        weekDays: [DayKey], missed: [MissedCare], now: Date
    ) -> RoutineWeek {
        let calendar = snapshot.calendar
        let entries = snapshot.entries(of: routine.id)
        let byDay = CareLogic.byDay(entries, calendar: calendar)
        let weekEntries = entries.filter { weekDays.contains(DayKey($0.time, calendar: calendar)) }
        let words = CareWords(routine, species: companion.species)
        let added = companion.createdAt
        let captions = CaptionEngine.captions(
            for: entries, tone: companion.captionTone, name: companion.name, routine: routine, words: words,
            names: snapshot.names, calendar: calendar
        )
        let trail = weekDays.map { CareLogic.slots(for: routine, on: $0, byDay: byDay, now: now, calendar: calendar) }
        let today = DayKey(now, calendar: calendar)
        let late = (weekDays.last == today ? trail.last ?? [] : [])
            .filter { $0.state == .late && CareLogic.isOwed($0, of: routine, on: today, since: added, now: now, calendar: calendar) }
            .map { slot in
                MissedCare(
                    routine: routine, day: today, slot: slot,
                    usual: CareCatchUp.usualTime(slot.index, of: routine, on: today, entries: entries, now: now, calendar: calendar)
                )
            }
        return RoutineWeek(
            routine: routine,
            trail: trail,
            stats: CareLogic.weekStats(for: routine, entries: entries, days: weekDays, now: now, calendar: calendar, since: added),
            streak: CareLogic.streak(for: routine, entries: entries, now: now, calendar: calendar, since: added),
            leaderboard: CareLogic.leaderboard(weekEntries, people: snapshot.everyone.map(\.id)),
            diary: weekEntries.reversed().map { DiaryItem(entry: $0, caption: captions[$0.id]) },
            missed: missed,
            late: late,
            milestones: CompanionReport.milestones(routine: routine, words: words, entries: entries, snapshot: snapshot, now: now, calendar: calendar, since: added),
            isThisWeek: weekDays.last == today,
            words: words
        )
    }

    // MARK: The week in a line

    /// "13 walks · 5h 50m outside · 4 squirrels pursued, 0 caught".
    var summary: String { summary(short: false) }

    /// The same facts in fewer words, for a line that also says who the pet is:
    /// "12 walks · 5h 50m out · 24 stars", "2 squirrels chased".
    var shortSummary: String { summary(short: true) }

    private func summary(short: Bool) -> String {
        var parts = ["\(stats.count) \(stats.count == 1 ? noun : noun + "s")"]
        if stats.totalMinutes > 0 {
            let time = stats.totalMinutes >= 60 ? "\(stats.totalMinutes / 60)h \(stats.totalMinutes % 60)m" : "\(stats.totalMinutes) min"
            parts.append(routine.kind == .walk ? "\(time) \(short ? "out" : "outside")" : time)
        }
        let squirrels = diary.filter { $0.entry.log.vibe == .squirrel }.count
        if squirrels > 0 {
            let chased = "\(squirrels) \(squirrels == 1 ? "squirrel" : "squirrels")"
            parts.append(short ? "\(chased) chased" : "\(chased) pursued, 0 caught")
        } else if stats.stars > 0 {
            parts.append(short ? "\(stats.stars) stars" : "\(stats.stars) stars earned")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Stat tiles

    /// One number on the page: "2 days" over "2×/day streak 🔥".
    struct Tile: Equatable {
        var value: String
        var unit: String?
        var label: String
    }

    /// The four numbers under the mood: the streak, the average length (or the count),
    /// slots on time, and the business log (or the stars).
    func tiles(calendar: Calendar) -> [Tile] {
        let cadence = routine.isDaily ? "\(routine.slotsPerDay)×/day" : routine.cadenceText(calendar: calendar)
        // The streak is today's on any week: on an earlier one it says so, short enough
        // for the wall's tile.
        var tiles = [Tile(value: "\(streak)", unit: streak == 1 ? "day" : "days", label: isThisWeek ? "\(cadence) streak 🔥" : "streak today 🔥")]
        let week = isThisWeek ? "this week" : "that week"
        if routine.tracks(.duration) {
            tiles.append(Tile(value: stats.averageMinutes.map(String.init) ?? "-", unit: "min", label: "avg \(noun)"))
        } else {
            tiles.append(Tile(value: "\(stats.count)", unit: nil, label: "\(noun)s \(week)"))
        }
        // Nothing owed yet (a companion added today) is no score at all, not a failing one.
        tiles.append(Tile(value: stats.slotsSoFar == 0 ? "-" : "\(stats.slotsOnTime)/\(stats.slotsSoFar)", unit: nil, label: "slots on time"))
        if routine.tracks(.pee) || routine.tracks(.poo) {
            let business = [routine.tracks(.pee) ? "💧\(stats.pee)" : nil, routine.tracks(.poo) ? "💩\(stats.poo)" : nil]
            tiles.append(Tile(value: business.compactMap { $0 }.joined(separator: " "), unit: nil, label: "business log"))
        } else {
            tiles.append(Tile(value: "⭐\(stats.stars)", unit: nil, label: "stars \(week)"))
        }
        return tiles
    }

    // MARK: Paw trail

    /// What tapping a slot of the paw trail does, on the wall and the phone alike.
    enum TrailTap: Equatable {
        /// A logged slot opens its log to fix.
        case edit(CareEntry)
        /// A slot whose window closed without a log, earlier this week or today, is logged
        /// for its own day and for that slot (`CareLogic.slot`), however late.
        case catchUp(MissedCare)
        /// A slot still open or to come today starts a new log.
        case log
    }

    /// Nil for a slot that asks nothing: one in the future, a day it wasn't due, or one that
    /// closed before the companion arrived, which was never owed.
    func tap(_ slot: CareSlot?, on day: DayKey) -> TrailTap? {
        guard let slot else { return nil }
        if let entry = slot.entry { return .edit(entry) }
        switch slot.state {
        case .upcoming, .open, .due:
            return .log
        case .late, .missed:
            return (late + missed).first { $0.day == day && $0.slot.index == slot.index }.map(TrailTap.catchUp)
        case .done, .future:
            return nil
        }
    }

    /// "Morning walk, Monday, Mia": what VoiceOver reads for a slot of the trail. A log
    /// that names nobody known reads "Who? Tap to say", as its diary row does.
    func trailLabel(_ slot: CareSlot?, window: CareWindow, on day: DayKey, snapshot: CompanionSnapshot) -> String {
        let name = CompanionWeekWords.capitalized(CareCatchUp.slotName(window, of: routine))
        let weekday = day.formatted(.dateTime.weekday(.wide), calendar: snapshot.calendar)
        let status: String
        if let entry = slot?.entry {
            status = snapshot.namesNobody(entry) ? CareLogWording.nobody : CaptionEngine.whoText(entry.people, names: snapshot.names)
        } else {
            switch tap(slot, on: day) {
            case .catchUp: status = slot?.state == .late ? "late" : "missed"
            case .log: status = "to do"
            default: status = "not due"
            }
        }
        return "\(name), \(weekday), \(status)"
    }
}

/// A row of a companion's diary: what was logged, or a slot that wasn't, in its place.
enum DiaryRow: Identifiable, Equatable {
    case logged(DiaryItem)
    case missed(MissedCare)

    var id: String {
        switch self {
        case let .logged(item): "log-\(item.id)"
        case let .missed(missed): "missed-\(missed.id)"
        }
    }

    var time: Date {
        switch self {
        case let .logged(item): item.entry.time
        case let .missed(missed): missed.usual
        }
    }

    /// Newest first.
    static func rows(_ diary: [DiaryItem], missed: [MissedCare]) -> [DiaryRow] {
        (diary.map(DiaryRow.logged) + missed.map(DiaryRow.missed)).sorted { $0.time > $1.time }
    }
}

extension CareLogic {
    /// The top three as they stand on a podium: second, first, third.
    static func podium(_ standings: [Standing]) -> [Standing] {
        let top = Array(standings.prefix(3))
        switch top.count {
        case 3: return [top[1], top[0], top[2]]
        case 2: return [top[1], top[0]]
        default: return top
        }
    }

    /// Who wears the crown: the leader, when nobody ties them.
    static func leader(_ standings: [Standing]) -> Standing? {
        guard let first = standings.first else { return nil }
        return standings.count == 1 || standings[1].count < first.count ? first : nil
    }
}

/// The words of a companion's page, the same on the wall and the phone.
enum CompanionWeekWords {
    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Log a walk", "Log a refill": the page's own log button.
    static func logButton(_ words: CareWords) -> String {
        "Log a \(words.noun)"
    }

    /// "who walked, each slot", beside Paw trail.
    static func trailMeta(_ words: CareWords) -> String {
        "who \(words.trailVerb), each slot"
    }

    /// "Walk diary", "Meal diary", "Water diary".
    static func diaryTitle(_ words: CareWords) -> String {
        "\(capitalized(words.diaryNoun)) diary"
    }

    /// "captions: Cheeky", beside the diary's title, unless captions are off.
    static func captionsMeta(_ companion: Companion) -> String? {
        companion.captionTone == .off ? nil : "captions: \(companion.captionTone.label)"
    }

    static func emptyDiary(_ words: CareWords) -> String {
        "Nothing logged this week yet. The first \(words.noun) starts the story."
    }

    /// "Walker of the week", "Chef of the week", "Bartender of the week".
    static func podiumTitle(_ words: CareWords) -> String {
        "\(words.agentNoun) of the week"
    }

    static func emptyPodium(_ words: CareWords) -> String {
        "No \(words.noun)s yet this week. The podium is wide open."
    }

    /// "Waiting for first walk": the mood before anything was logged.
    static func waitingForFirst(_ words: CareWords) -> String {
        "Waiting for first \(words.noun)"
    }

    /// "Refill logged": the toast after a log from the care sheet.
    static func logged(_ words: CareWords) -> String {
        "\(capitalized(words.noun)) logged"
    }

    /// "Today 8:12am", "Fri 6:40pm": when a diary row happened.
    static func when(_ date: Date, today: DayKey, calendar: Calendar) -> String {
        let time = CareText.timeWithPeriod(date, calendar: calendar)
        let day = DayKey(date, calendar: calendar)
        if day == today { return "Today \(time)" }
        return day.formatted(.dateTime.weekday(.abbreviated), calendar: calendar) + " \(time)"
    }

    /// "Morning walk", "Feed Yo-Yo · Dinner": a missed slot's row in the diary.
    static func missedTitle(_ missed: MissedCare, companion: Companion) -> String {
        CompanionTimeline.expectedTitle(missed.slot, routine: missed.routine, companion: companion)
    }

    /// "Fri · usually 6-10am".
    static func missedDetail(_ missed: MissedCare, calendar: Calendar) -> String {
        ([missed.day.formatted(.dateTime.weekday(.abbreviated), calendar: calendar)]
            + (missed.slot.window.isAllDay ? [] : ["usually \(missed.slot.window.rangeText)"])).joined(separator: " · ")
    }

    /// "yesterday", "Friday": the missed slot's day in a sentence.
    static func missedDay(_ missed: MissedCare, today: DayKey, calendar: Calendar) -> String {
        missed.day == today.adding(days: -1, calendar: calendar)
            ? "yesterday"
            : missed.day.formatted(.dateTime.weekday(.wide), calendar: calendar)
    }

    /// "M": a day's letter over its column of the trail.
    static func weekdayLetter(_ day: DayKey, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: day.startDate(in: calendar))
        return calendar.veryShortWeekdaySymbols[weekday - 1]
    }

    /// "17": a day's number under its letter.
    static func dayNumber(_ day: DayKey, calendar: Calendar) -> String {
        "\(calendar.component(.day, from: day.startDate(in: calendar)))"
    }
}
