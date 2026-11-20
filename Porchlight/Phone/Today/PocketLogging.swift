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
    /// Logging from a sheet: its toast waits until the sheet has closed.
    var fromSheet = false

    /// The same, for a sheet to log with.
    var inSheet: PocketLogging {
        var logging = self
        logging.fromSheet = true
        return logging
    }

    /// The same, for a toast's action: the sheet is long gone by then, so its word shows at once.
    private var direct: PocketLogging {
        var logging = self
        logging.fromSheet = false
        return logging
    }

    private func present(_ toast: UndoToast) {
        if fromSheet { toasts.showAfterSheet(toast) } else { toasts.show(toast) }
    }

    private var names: [Person.ID: String] { companions.snapshot.names }
    private var calendar: Calendar { companions.snapshot.calendar }

    // MARK: Care

    /// Logs a slot now, by `people`.
    func log(_ action: PocketToday.CareAction, companion: String, people: [Person.ID]) {
        let now = CompanionClock.now()
        let draft = CareLogDraft(people: people, occurredAt: now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        log(action.routine, slot: action.slot.index, on: DayKey(now, calendar: calendar), draft, companion: companion, now: now)
    }

    /// Logs one slot of a day with a draft, unless someone already did it: one tap from a
    /// card. A write that is turned down says so in a toast.
    func log(_ routine: CareRoutine, slot: Int, on day: DayKey, _ draft: CareLogDraft, companion: String, now: Date = CompanionClock.now()) {
        guard let result = companions.log(routineId: routine.id, slot: slot, on: day, draft, now: now) else { return failed() }
        said(result, routine: routine, slot: slot, companion: companion, people: draft.people)
    }

    /// Saves a new log from the care sheet: for the slot being caught up on (unless someone
    /// already did it), else at the time chosen. True when the sheet can close, its toast
    /// waiting for it; false, with `companions.lastError` set, when the write was turned
    /// down, so the sheet stays open and says why.
    func save(_ routine: CareRoutine, _ draft: CareLogDraft, catchingUp slot: Int?, on day: DayKey, companion: String) -> Bool {
        let now = CompanionClock.now()
        if let slot {
            guard let result = companions.log(routineId: routine.id, slot: slot, on: day, draft, now: now) else { return false }
            said(result, routine: routine, slot: slot, companion: companion, people: draft.people)
            return true
        }
        guard let log = companions.log(routineId: routine.id, draft, now: now) else { return false }
        logged(log, routine: routine, people: draft.people)
        return true
    }

    /// The toast for logging one slot: logged, with Undo, or who got there first.
    private func said(_ result: CareSlotLog, routine: CareRoutine, slot: Int, companion: String, people: [Person.ID]) {
        switch result {
        case let .logged(log):
            let slotName = CareCatchUp.slotName(routine.effectiveWindows[safe: slot] ?? .anyTime, of: routine)
            present(UndoToast(
                emoji: routine.emoji,
                title: PocketCareWords.capitalized(slotName) + " logged",
                detail: detail(people: people, stars: routine.stars),
                action: .init(title: "Undo") { [direct] in direct.remove(log.id) }
            ))
        case let .alreadyLogged(entry):
            alreadyLogged(entry, routine: routine, companion: companion, joining: people)
        }
    }

    /// Someone logged the slot first: say so, and offer to join their log.
    private func alreadyLogged(_ entry: CareEntry, routine: CareRoutine, companion: String, joining people: [Person.ID]) {
        let sentence = PocketToday.alreadyDone(entry, routine: routine, companion: companion, me: me, names: names, calendar: calendar)
        let newcomers = people.filter { !entry.people.contains($0) }
        guard !newcomers.isEmpty else {
            present(UndoToast(emoji: routine.emoji, title: sentence, detail: "Already logged, so nothing was added"))
            return
        }
        present(UndoToast(
            emoji: routine.emoji,
            title: sentence,
            detail: "Already logged, so nothing was added",
            action: .init(title: me.map { newcomers == [$0] } == true ? "I went too" : "We went too") { [direct] in direct.join(entry, routine: routine, adding: newcomers) }
        ))
    }

    private func join(_ entry: CareEntry, routine: CareRoutine, adding people: [Person.ID]) {
        guard companions.addPeople(people, toLog: entry.id) else { return failed() }
        let who = PocketToday.who(people, me: me, names: names)
        present(UndoToast(
            emoji: routine.emoji,
            title: "Added \(who) to the \(routine.kind.noun(title: routine.title))",
            detail: "\(StarWords.earned(routine.stars)) each",
            action: .init(title: "Undo") { [direct] in if !direct.companions.removePeople(people, fromLog: entry.id) { direct.failed() } }
        ))
    }

    /// After the full care sheet saved a log.
    private func logged(_ log: CareLog, routine: CareRoutine, people: [Person.ID]) {
        present(UndoToast(
            emoji: routine.emoji,
            title: PocketCareWords.capitalized(routine.kind.noun(title: routine.title)) + " logged",
            detail: detail(people: people, stars: routine.stars),
            action: .init(title: "Undo") { [direct] in direct.remove(log.id) }
        ))
    }

    // MARK: Chores

    /// Checks off a chore today, credited to `person` when anyone could take it.
    func complete(_ chore: Chore, by person: Person.ID?) {
        let emoji = chore.emoji ?? "✅"
        switch home.complete(chore, by: person, now: CompanionClock.now()) {
        case let .done(completion):
            present(UndoToast(
                emoji: emoji,
                title: "\(chore.title) done",
                detail: StarWords.earned(completion.stars),
                action: .init(title: "Undo") { home.undo(completion) }
            ))
        case let .alreadyDone(completion):
            let who = completion.personId.map { PocketToday.who([$0], me: me, names: names) } ?? "Someone"
            let time = CareText.timeWithPeriod(completion.completedAt, calendar: home.calendar)
            present(UndoToast(
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
        let earned = StarWords.earned(stars)
        guard !others.isEmpty, me != nil else { return earned }
        return "With \(CaptionEngine.whoText(others, names: names)) · \(earned)"
    }

    /// Saves a fix made in the care sheet, which closed as soon as Save was tapped; if the
    /// write is turned down after all, a toast says so.
    func saveFix(_ id: CareLog.ID, _ draft: CareLogDraft) {
        if !companions.updateLog(id: id, draft) { failed() }
    }

    /// Removes a log from the care sheet, which closed as soon as Remove was confirmed.
    func remove(_ id: CareLog.ID) {
        if !companions.deleteLog(id: id) { failed() }
    }

    private func failed(_ message: String? = nil) {
        present(UndoToast(emoji: "⚠️", title: "That didn't save", detail: message ?? companions.lastError))
    }
}
