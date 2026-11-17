import Foundation

/// What the phone's Today shows: mine first, then ours. It is worked out from the same
/// stores and rules as the wall (CompanionReport, CareLogic, ChoreBoard), so every count
/// matches the wall. Pure, and covered by PocketTodayTests.
enum PocketToday {
    // MARK: Care

    /// Something one tap can log: a routine's slot.
    struct CareAction: Equatable {
        var routine: CareRoutine
        var slot: CareSlot
    }

    /// How much a companion needs someone right now; cards are ordered by it.
    enum Standing: Int, Comparable {
        /// A window is open now and waiting.
        case due
        /// Something is still to come today, or was missed.
        case waiting
        /// Every slot today is done (or nothing is due today).
        case allSet

        static func < (lhs: Standing, rhs: Standing) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One companion's card.
    struct CareCard: Identifiable {
        var report: CompanionReport
        /// What the big button logs, when one tap can log something now.
        var lead: CareAction?
        /// The routine whose slots the card shows.
        var shown: RoutineToday?
        /// The other routines one tap can log now.
        var others: [CareAction]
        var standing: Standing

        var id: Companion.ID { report.id }
    }

    /// The slot a tap logs for a routine right now: the one a log at `now` belongs to by
    /// the wall's rule (`CareLogic.windowIndex`), while it is still waiting and its window
    /// hasn't closed. A closed window is caught up on instead, at the time it happened.
    static func oneTapSlot(_ today: RoutineToday, now: Date, calendar: Calendar) -> CareSlot? {
        let index = CareLogic.windowIndex(forMinute: CareLogic.minuteOfDay(now, calendar: calendar), in: today.routine.effectiveWindows)
        guard let slot = today.slots[safe: index], !slot.isDone else { return nil }
        switch slot.state {
        case .open, .due, .upcoming: return slot
        case .done, .late, .missed, .future: return nil
        }
    }

    static func card(_ report: CompanionReport, calendar: Calendar) -> CareCard {
        let todays = [report.primary].compactMap { $0 } + report.others
        let actions = todays.compactMap { today in
            oneTapSlot(today, now: report.now, calendar: calendar).map { CareAction(routine: today.routine, slot: $0) }
        }
        // An open window leads; a slot one tap can log ahead comes next.
        let lead = actions.first { $0.slot.state == .open || $0.slot.state == .due } ?? actions.first
        let shown = lead.flatMap { action in todays.first { $0.id == action.routine.id } }
            ?? todays.first { $0.slots.contains(where: \.isPendingToday) }
            ?? report.primary
        let standing: Standing = if lead.map({ $0.slot.state == .open || $0.slot.state == .due }) == true {
            .due
        } else if todays.contains(where: { $0.slots.contains(where: \.isPendingToday) }) {
            .waiting
        } else {
            .allSet
        }
        return CareCard(
            report: report, lead: lead, shown: shown,
            others: actions.filter { $0.routine.id != lead?.routine.id }, standing: standing
        )
    }

    /// Every companion's card, the ones that need someone now first, otherwise in the
    /// household's order.
    static func cards(_ reports: [CompanionReport], calendar: Calendar) -> [CareCard] {
        reports.map { card($0, calendar: calendar) }
            .enumerated()
            .sorted { ($0.element.standing, $0.offset) < ($1.element.standing, $1.offset) }
            .map(\.element)
    }

    /// Whether a card that is all set should still show what was just done ("✓ Logged")
    /// rather than folding into its quiet one-line form.
    static func isFresh(_ card: CareCard, within minutes: Double = 15) -> Bool {
        guard card.standing == .allSet else { return false }
        let todays = [card.report.primary].compactMap { $0 } + card.report.others
        let latest = todays.flatMap(\.slots).compactMap(\.entry?.time).max()
        return latest.map { card.report.now.timeIntervalSince($0) < minutes * 60 } ?? false
    }

    // MARK: Catching up

    /// The one missed slot Today offers to catch up on: the newest whose window closed
    /// without a log, today or earlier in the catch-up week (`CareCatchUp`), skipping the
    /// ones this device was told to leave alone.
    static func catchUp(_ reports: [CompanionReport], snapshot: CompanionSnapshot, dismissed: Set<String>) -> (report: CompanionReport, missed: MissedCare)? {
        let calendar = snapshot.calendar
        let candidates = reports.flatMap { report -> [(CompanionReport, MissedCare)] in
            let late = ([report.primary].compactMap { $0 } + report.others).flatMap { today in
                today.slots.filter {
                    $0.state == .late && CareCatchUp.isOwed($0, of: today.routine, on: report.today, since: report.companion.createdAt, calendar: calendar)
                }.map { slot in
                    MissedCare(
                        routine: today.routine, day: report.today, slot: slot,
                        usual: CareCatchUp.usualTime(slot.index, of: today.routine, on: report.today, entries: snapshot.entries(of: today.routine.id), now: report.now, calendar: calendar)
                    )
                }
            }
            return (late + report.missed).map { (report, $0) }
        }
        return candidates
            .filter { !dismissed.contains($0.1.id) }
            .max { $0.1.usual < $1.1.usual }
    }

    // MARK: Chores

    struct Chores {
        /// Today's chores that belong to me, in board order.
        var mine: [ChoreBoard.Task]
        /// Today's chores anyone can take, in board order.
        var anyone: [ChoreBoard.Task]
    }

    /// My column and the "Anyone" column of the wall's board for today.
    static func chores(_ board: ChoreBoard, me: Person.ID) -> Chores {
        Chores(
            mine: board.columns.first { $0.owner == .person(me) }?.tasks ?? [],
            anyone: board.columns.first { $0.owner == .everyone }?.tasks ?? []
        )
    }

    /// Stars I earned today, from chores and care, as Glow counts them.
    static func stars(_ earnings: [StarEarning], me: Person.ID, on day: DayKey) -> Int {
        earnings.filter { $0.personId == me && $0.day == day }.map(\.stars).reduce(0, +)
    }

    // MARK: Words

    /// "you", "Mia", "Mia & you": who did something, with me as "you".
    static func who(_ people: [Person.ID], me: Person.ID?, names: [Person.ID: String]) -> String {
        var names = names
        if let me { names[me] = "you" }
        // Me last, so "Mia & you".
        let ordered = people.filter { $0 != me } + people.filter { $0 == me }
        return CaptionEngine.whoText(ordered, names: names)
    }

    /// "Mia walked Yo-Yo at 5:40pm": what someone else already did, said before
    /// offering to join it.
    static func alreadyDone(_ entry: CareEntry, routine: CareRoutine, companion: String, me: Person.ID?, names: [Person.ID: String], calendar: Calendar) -> String {
        let who = who(entry.people, me: me, names: names)
        let sentence = routine.kind.sentence(who: who.prefix(1).uppercased() + who.dropFirst(), name: companion, title: routine.title)
        return sentence + " at " + CareText.timeWithPeriod(entry.time, calendar: calendar)
    }

    /// "Walked at 6:12pm by you · fed at 5:30pm by Mia": what a companion had today.
    static func allSetLine(_ report: CompanionReport, me: Person.ID?, names: [Person.ID: String], calendar: Calendar) -> String {
        let parts = ([report.primary].compactMap { $0 } + report.others).compactMap { today -> String? in
            guard let last = today.slots.compactMap(\.entry).max(by: { $0.time < $1.time }) else { return nil }
            return "\(today.routine.kind.pastVerb.lowercased()) at \(CareText.timeWithPeriod(last.time, calendar: calendar)) by \(who(last.people, me: me, names: names))"
        }
        guard let first = parts.first else { return "Nothing due today" }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: " · ")
    }

    /// "Walked 9h ago by Mia" under a companion's name.
    static func lastLine(_ today: RoutineToday?, report: CompanionReport, me: Person.ID?, names: [Person.ID: String]) -> String {
        guard let today else { return report.companion.species.label }
        guard let last = today.lastEntry else { return "Waiting for the first \(today.routine.kind.noun(title: today.routine.title))" }
        return "\(today.routine.kind.pastVerb) \(CareText.ago(last.time, now: report.now)) by \(who(last.people, me: me, names: names))"
    }

    /// "Evening", "Water": a slot's name on its tile.
    static func slotTitle(_ slot: CareSlot, of routine: CareRoutine) -> String {
        slot.window.isAllDay ? routine.title : slot.window.label
    }

    /// "5-8pm · open now", "8:40am": a slot's line on its tile.
    static func slotDetail(_ slot: CareSlot, calendar: Calendar) -> String {
        if let entry = slot.entry { return CareText.timeWithPeriod(entry.time, calendar: calendar) }
        let range = slot.window.isAllDay ? "Today" : slot.window.rangeText
        switch slot.state {
        case .open: return "\(range) · open now"
        case .due: return "\(range) · due now"
        case .late: return "\(range) · not logged"
        case .upcoming, .done, .missed, .future: return range
        }
    }
}
