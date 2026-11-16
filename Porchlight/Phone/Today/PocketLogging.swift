import Foundation

/// Logging from the phone: one tap writes it, credited to the people given, and a toast
/// says what happened with a way to take it back. When someone got there first,
/// nothing is added and the toast says who did it instead.
@MainActor
struct PocketLogging {
    let companions: CompanionStore
    let home: HomeStore
    let toasts: ToastCenter
    /// Who "you" is in the words, on a personal device.
    let me: Person.ID?

    private var names: [Person.ID: String] { companions.snapshot.names }
    private var calendar: Calendar { companions.snapshot.calendar }

    // MARK: Care

    /// Logs a slot now, by `people`.
    func log(_ action: PocketToday.CareAction, companion: String, people: [Person.ID]) {
        let now = CompanionClock.now()
        let draft = CareLogDraft(people: people, occurredAt: now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        log(action.routine, slot: action.slot.index, on: DayKey(now, calendar: calendar), draft, companion: companion, now: now)
    }

    /// Logs a slot with a draft: one tap, or a missed slot caught up on at its time.
    func log(_ routine: CareRoutine, slot: Int, on day: DayKey, _ draft: CareLogDraft, companion: String, now: Date = CompanionClock.now()) {
        let slotName = CareCatchUp.slotName(routine.effectiveWindows[safe: slot] ?? .anyTime, of: routine)
        switch companions.log(routineId: routine.id, slot: slot, on: day, draft, now: now) {
        case let .logged(log):
            toasts.show(UndoToast(
                emoji: routine.emoji,
                title: PocketCareWords.capitalized(slotName) + " logged",
                detail: detail(people: draft.people, stars: routine.stars),
                action: .init(title: "Undo") { companions.deleteLog(id: log.id) }
            ))
        case let .alreadyLogged(entry):
            alreadyLogged(entry, routine: routine, companion: companion, joining: draft.people)
        case nil:
            failed()
        }
    }

    /// Someone logged the slot first: say so, and offer to join their log.
    private func alreadyLogged(_ entry: CareEntry, routine: CareRoutine, companion: String, joining people: [Person.ID]) {
        let sentence = PocketToday.alreadyDone(entry, routine: routine, companion: companion, me: me, names: names, calendar: calendar)
        let newcomers = people.filter { !entry.people.contains($0) }
        guard !newcomers.isEmpty else {
            toasts.show(UndoToast(emoji: routine.emoji, title: sentence, detail: "Already logged, so nothing was added"))
            return
        }
        toasts.show(UndoToast(
            emoji: routine.emoji,
            title: sentence,
            detail: "Already logged, so nothing was added",
            action: .init(title: me.map { newcomers == [$0] } == true ? "I went too" : "We went too") { join(entry, routine: routine, adding: newcomers) }
        ))
    }

    private func join(_ entry: CareEntry, routine: CareRoutine, adding people: [Person.ID]) {
        guard companions.addPeople(people, toLog: entry.id) else { return failed() }
        let who = PocketToday.who(people, me: me, names: names)
        toasts.show(UndoToast(
            emoji: routine.emoji,
            title: "Added \(who) to the \(routine.kind.noun(title: routine.title))",
            detail: "+\(routine.stars) \(routine.stars == 1 ? "star" : "stars") each",
            action: .init(title: "Undo") { companions.removePeople(people, fromLog: entry.id) }
        ))
    }

    /// After the full care sheet saved a log.
    func logged(_ log: CareLog, routine: CareRoutine, people: [Person.ID]) {
        toasts.show(UndoToast(
            emoji: routine.emoji,
            title: PocketCareWords.capitalized(routine.kind.noun(title: routine.title)) + " logged",
            detail: detail(people: people, stars: routine.stars),
            action: .init(title: "Undo") { companions.deleteLog(id: log.id) }
        ))
    }

    // MARK: Chores

    /// Checks off a chore today, credited to `person` when anyone could take it.
    func complete(_ chore: Chore, by person: Person.ID?) {
        let emoji = chore.emoji ?? "✅"
        switch home.complete(chore, by: person, now: CompanionClock.now()) {
        case let .done(completion):
            toasts.show(UndoToast(
                emoji: emoji,
                title: "\(chore.title) done",
                detail: "+\(completion.stars) \(completion.stars == 1 ? "star" : "stars")",
                action: .init(title: "Undo") { home.undo(completion) }
            ))
        case let .alreadyDone(completion):
            let who = completion.personId.map { PocketToday.who([$0], me: me, names: names) } ?? "Someone"
            let time = CareText.timeWithPeriod(completion.completedAt, calendar: home.calendar)
            toasts.show(UndoToast(
                emoji: emoji,
                title: "\(PocketCareWords.capitalized(who)) did it at \(time)",
                detail: "\(chore.title) was already done"
            ))
        case nil:
            failed(home.lastError)
        }
    }

    // MARK: Words

    /// "With Mia · +2 stars": who else came, and what it earned.
    private func detail(people: [Person.ID], stars: Int) -> String {
        let others = people.filter { $0 != me }
        let earned = "+\(stars) \(stars == 1 ? "star" : "stars")"
        guard !others.isEmpty, me != nil else { return earned }
        return "With \(CaptionEngine.whoText(others, names: names)) · \(earned)"
    }

    private func failed(_ message: String? = nil) {
        toasts.show(UndoToast(emoji: "⚠️", title: "That didn't save", detail: message ?? companions.lastError))
    }
}
