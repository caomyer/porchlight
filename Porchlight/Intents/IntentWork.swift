import Foundation
import GRDB

/// What every widget, Siri and Shortcuts action does, on a database it is handed, so each
/// one is tested on a test database (`IntentWorkTests`). Every write is the same write as
/// one tap on the phone's Today: it reads the slot or chore again inside the write (rule 10),
/// is stamped with this device's id by the database, and credits this device's person.
@MainActor
enum IntentWork {
    /// Why an action can't run on this device.
    enum Refusal: Error, Equatable, Sendable {
        /// The app couldn't open its data at launch.
        case notOpen
        case noHousehold
        case noMe
        /// A shared screen asks who did something, which Siri and widgets can't.
        case sharedScreen

        var text: String {
            switch self {
            case .notOpen: "Porchlight couldn't open its data. Open the app to see why."
            case .noHousehold: "Porchlight isn't set up on this phone yet. Open it to join or start a household."
            case .noMe: "Porchlight doesn't know who you are on this phone yet. Open it and pick yourself."
            case .sharedScreen: "This screen is shared, so it asks who did each thing. Log it on the screen itself."
            }
        }

        /// Whether opening the app is how to fix it, so Siri offers to.
        var opensApp: Bool { self != .sharedScreen }
    }

    /// What an action says when it ran: spoken, and shown as its dialog.
    struct Answer: Equatable, Sendable {
        var text: String
        /// A second line, shown under the first.
        var detail: String?
        /// Whether anything was written, so the widgets and sync need to hear of it.
        var wrote: Bool
    }

    enum Outcome: Equatable, Sendable {
        case answer(Answer)
        case refused(Refusal)

        var wrote: Bool {
            if case let .answer(answer) = self { return answer.wrote }
            return false
        }
    }

    /// The household and the person this device belongs to, or why there is none.
    struct Who {
        var snapshot: CompanionSnapshot
        var household: Household
        var me: Person?
        /// This phone belongs to more than one household, so answers say which.
        var isOneOfSeveral = false

        /// "At Grandma Rosa's · ", before an answer's detail, when it could be either.
        var place: String { isOneOfSeveral ? "At \(household.name) · " : "" }
    }

    /// Who is acting. `needsMe` is false for answers that only read the household.
    /// - Parameter householdId: The household the action is about (a widget's routine, a
    ///   chore); nil means the one on screen.
    static func who(database: AppDatabase, settings: DeviceSettings, needsMe: Bool = true, householdId: Household.ID? = nil) async -> Result<Who, Refusal> {
        guard let (snapshot, count) = try? await database.writer.read({ db -> (CompanionSnapshot, Int) in
                  let snapshot = try householdId.map { try CompanionSnapshot.fetch(db, householdId: $0) } ?? CompanionSnapshot.fetch(db)
                  return (snapshot, try Household.fetchCount(db))
              }),
              let household = snapshot.household else { return .failure(.noHousehold) }
        let me = settings.me(in: household.id).flatMap { id in snapshot.people.first { $0.id == id } }
        if needsMe {
            guard settings.role == .personal else { return .failure(.sharedScreen) }
            guard me != nil else { return .failure(.noMe) }
        }
        return .success(Who(snapshot: snapshot, household: household, me: me, isOneOfSeveral: count > 1))
    }

    // MARK: Care

    /// Logs one slot of one day: the companion widget's button.
    static func logSlot(routineId: CareRoutine.ID, slot: Int, day: DayKey, database: AppDatabase, settings: DeviceSettings, now: Date) async -> Outcome {
        // The routine's own household: a widget drawn before a switch still logs where it said.
        let householdId = try? await database.writer.read { db in
            try Household.ID.fetchOne(db, sql: """
                SELECT companion.householdId FROM careRoutine JOIN companion ON companion.id = careRoutine.companionId
                WHERE careRoutine.id = ?
                """, arguments: [routineId])
        }
        let who: Who
        switch await self.who(database: database, settings: settings, householdId: householdId ?? nil) {
        case let .success(found): who = found
        case let .failure(refusal): return .refused(refusal)
        }
        guard let routine = who.snapshot.routines.first(where: { $0.id == routineId }),
              let companion = who.snapshot.companions.first(where: { $0.id == routine.companionId }),
              let me = who.me else {
            return .answer(Answer(text: "That routine isn't in Porchlight anymore.", wrote: false))
        }
        return log(routine: routine, companion: companion, slot: slot, day: day, me: me, who: who, database: database, now: now)
    }

    /// Logs a companion's care now: "I walked Yo-Yo". Without a routine it picks the one
    /// whose window is open (as one tap on Today does), else the companion's main routine;
    /// the slot is the one a log now belongs to by the wall's rule.
    static func logCare(companionId: Companion.ID, routineId: CareRoutine.ID?, kind: CareKind? = nil, database: AppDatabase, settings: DeviceSettings, now: Date) async -> Outcome {
        let who: Who
        switch await self.who(database: database, settings: settings) {
        case let .success(found): who = found
        case let .failure(refusal): return .refused(refusal)
        }
        guard let companion = who.snapshot.companions.first(where: { $0.id == companionId }), let me = who.me else {
            return .answer(Answer(text: "That companion isn't in Porchlight anymore.", wrote: false))
        }
        let routines = who.snapshot.routines(of: companionId)
        let routine: CareRoutine
        if let routineId {
            guard let chosen = routines.first(where: { $0.id == routineId }) else {
                return .answer(Answer(text: "\(companion.name) doesn't have that routine anymore.", wrote: false))
            }
            routine = chosen
        } else if let kind {
            // "I walked Yo-Yo": the companion's walk, the open one first when it has several.
            let ofKind = routines.filter { $0.kind == kind }
            let report = CompanionReport.make(snapshot: who.snapshot, companionId: companionId, now: now)
            let lead = report.map { PocketToday.card($0, calendar: who.snapshot.calendar) }
            let open = ([lead?.lead].compactMap { $0 } + (lead?.others ?? [])).first { $0.routine.kind == kind }?.routine
            guard let chosen = open ?? ofKind.first else {
                return .answer(Answer(text: "\(companion.name) has no \(CareWords(kind: kind, title: kind.defaultTitle, species: companion.species).noun) routine in Porchlight.", wrote: false))
            }
            routine = chosen
        } else {
            let report = CompanionReport.make(snapshot: who.snapshot, companionId: companionId, now: now)
            guard let chosen = report.flatMap({ PocketToday.card($0, calendar: who.snapshot.calendar).lead?.routine }) ?? routines.first else {
                return .answer(Answer(text: "\(companion.name) has no routines yet. Add one in Porchlight.", wrote: false))
            }
            routine = chosen
        }
        let calendar = who.snapshot.calendar
        let day = DayKey(now, calendar: calendar)
        guard routine.occurs(on: day, calendar: calendar) else {
            return .answer(Answer(text: "\(companion.name.possessive) \(CareWords(routine, species: companion.species).noun) isn't due today.", wrote: false))
        }
        let slot = CareLogic.windowIndex(forMinute: CareLogic.minuteOfDay(now, calendar: calendar), in: routine.effectiveWindows)
        return log(routine: routine, companion: companion, slot: slot, day: day, me: me, who: who, database: database, now: now)
    }

    private static func log(routine: CareRoutine, companion: Companion, slot: Int, day: DayKey, me: Person, who: Who, database: AppDatabase, now: Date) -> Outcome {
        let calendar = who.snapshot.calendar
        let slotName = CareCatchUp.slotName(routine.effectiveWindows[safe: slot] ?? .anyTime, of: routine)
        let draft = CareLogDraft(people: [me.id], occurredAt: now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        switch try? database.logCare(routineId: routine.id, slot: slot, on: day, draft, now: now) {
        case .logged:
            let stars = routine.stars > 0 ? " · +\(StarWords.count(routine.stars))" : ""
            return .answer(Answer(
                text: "Logged \(companion.name.possessive) \(slotName)",
                detail: "\(who.place)For \(me.name) at \(CareText.timeWithPeriod(now, calendar: calendar))\(stars)",
                wrote: true
            ))
        case let .alreadyLogged(entry):
            return .answer(Answer(
                text: PocketToday.alreadyDone(entry, words: CareWords(routine, species: companion.species), companion: companion.name, me: me.id, names: who.snapshot.names, calendar: calendar),
                detail: "Already logged, so nothing was added.",
                wrote: false
            ))
        case nil:
            return .answer(Answer(text: "That didn't save. Open Porchlight to log \(companion.name.possessive) \(slotName).", wrote: false))
        }
    }

    // MARK: Chores

    /// Checks a chore off for me on a day.
    static func checkChore(choreId: Chore.ID, day: DayKey, database: AppDatabase, settings: DeviceSettings, now: Date) async -> Outcome {
        guard let chore = try? await database.writer.read({ try Chore.fetchOne($0, id: choreId) }), !chore.archived else {
            return .answer(Answer(text: "That chore isn't in Porchlight anymore.", wrote: false))
        }
        // The chore's own household, and "me" there: never someone from another household.
        let who: Who
        switch await self.who(database: database, settings: settings, householdId: chore.householdId) {
        case let .success(found): who = found
        case let .failure(refusal): return .refused(refusal)
        }
        guard let me = who.me else {
            return .answer(Answer(text: "That chore isn't in Porchlight anymore.", wrote: false))
        }
        let calendar = who.snapshot.calendar
        switch try? database.completeChore(id: choreId, day: day, personId: me.id, now: now) {
        case let .done(completion):
            let stars = completion.stars > 0 ? "+\(StarWords.count(completion.stars)) for \(completion.personId == me.id ? "you" : who.snapshot.names[completion.personId ?? me.id] ?? "them")" : nil
            return .answer(Answer(text: "Checked off \(chore.title)", detail: stars.map { who.place + $0 } ?? (who.isOneOfSeveral ? "At \(who.household.name)" : nil), wrote: true))
        case let .alreadyDone(completion):
            let by = PocketToday.who(completion.personId.map { [$0] } ?? [], me: me.id, names: who.snapshot.names)
            let name = by == "you" ? "You" : by.prefix(1).uppercased() + by.dropFirst()
            return .answer(Answer(
                text: "\(name) already did \(chore.title) at \(CareText.timeWithPeriod(completion.completedAt, calendar: calendar))",
                detail: "Already checked off, so nothing changed.",
                wrote: false
            ))
        case nil:
            return .answer(Answer(text: "That didn't save. Open Porchlight to check off \(chore.title).", wrote: false))
        }
    }

    /// The chores Siri and Shortcuts offer: mine and anyone's today, not yet done.
    static func choresToday(database: AppDatabase, settings: DeviceSettings, now: Date) async -> [Chore] {
        guard case let .success(who) = await self.who(database: database, settings: settings), let me = who.me,
              let home = try? await database.writer.read({ try HomeSnapshot.fetch($0, since: DayKey(now, calendar: who.snapshot.calendar)) }) else { return [] }
        let calendar = who.snapshot.calendar
        let board = ChoreBoard(
            people: home.people, chores: home.chores, completions: home.completions, earnings: home.earnings,
            redemptions: home.redemptions, rewards: home.rewards, today: DayKey(now, calendar: calendar), calendar: calendar
        )
        let chores = PocketToday.chores(board, me: me.id)
        let open: [ChoreBoard.Task] = (chores.mine + chores.anyone).filter { task in !task.isDone }
        return open.map(\.chore)
    }

    // MARK: Lists

    /// Adds an item to a list (the household's groceries when none is named), unless it
    /// is already on it and not yet checked.
    static func addItem(_ title: String, listId: HomeList.ID?, database: AppDatabase, settings: DeviceSettings, now: Date) async -> Outcome {
        let who: Who
        switch await self.who(database: database, settings: settings) {
        case let .success(found): who = found
        case let .failure(refusal): return .refused(refusal)
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let me = who.me, !trimmed.isEmpty else { return .answer(Answer(text: "What should I add?", wrote: false)) }
        let lists = (try? await database.writer.read { db in
            try HomeList.filter(Column("householdId") == who.household.id).order(Column("sortOrder"), Column("createdAt")).fetchAll(db)
        }) ?? []
        guard let list = listId.flatMap({ id in lists.first { $0.id == id } }) ?? lists.first(where: { $0.kind == .grocery }) ?? lists.first else {
            return .answer(Answer(text: "There's no list yet. Make one in Porchlight.", wrote: false))
        }
        let items = (try? await database.writer.read { db in
            try ListItem.filter(Column("listId") == list.id && Column("checked") == false).fetchAll(db)
        }) ?? []
        if let existing = items.first(where: { $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .answer(Answer(text: "\(existing.title) is already on \(list.title).", wrote: false))
        }
        guard (try? database.addListItem(title: trimmed, to: list.id, addedBy: me.id, now: now)) != nil else {
            return .answer(Answer(text: "That didn't save. Open Porchlight to add \(trimmed).", wrote: false))
        }
        return .answer(Answer(text: "Added \(trimmed) to \(list.title)", detail: "\(who.place)\(items.count + 1) on the list", wrote: true))
    }

    static func lists(database: AppDatabase) async -> [HomeList] {
        (try? await database.writer.read { db in
            guard let household = try Household.current(db) else { return [] }
            return try HomeList.filter(Column("householdId") == household.id).order(Column("sortOrder"), Column("createdAt")).fetchAll(db)
        }) ?? []
    }

    // MARK: What's next

    /// "Yo-Yo's evening walk is open until 8 pm. You have 2 chores left: …". It only reads,
    /// so a shared screen answers it too, without the chores.
    static func whatsNext(database: AppDatabase, settings: DeviceSettings, now: Date) async -> Outcome {
        let who: Who
        switch await self.who(database: database, settings: settings, needsMe: false) {
        case let .success(found): who = found
        case let .failure(refusal): return .refused(refusal)
        }
        let calendar = who.snapshot.calendar
        let reports = who.snapshot.companions.compactMap { CompanionReport.make(snapshot: who.snapshot, companionId: $0.id, now: now) }
        var sentences: [String] = []
        for card in PocketToday.cards(reports, calendar: calendar) {
            guard let lead = card.lead else { continue }
            let name = CareCatchUp.slotName(lead.slot.window, of: lead.routine)
            switch lead.slot.state {
            case .open, .due:
                let until = lead.slot.window.isAllDay ? "today" : "until \(CareTime.hour(lead.slot.window.end))"
                sentences.append("\(card.report.name.possessive) \(name) is open \(until).")
            default:
                sentences.append("\(card.report.name.possessive) \(name) opens at \(CareTime.hour(lead.slot.window.start)).")
            }
        }
        if settings.role == .personal, let me = who.me,
           let home = try? await database.writer.read({ try HomeSnapshot.fetch($0, since: DayKey(now, calendar: calendar)) }) {
            let board = ChoreBoard(
                people: home.people, chores: home.chores, completions: home.completions, earnings: home.earnings,
                redemptions: home.redemptions, rewards: home.rewards, today: DayKey(now, calendar: calendar), calendar: calendar
            )
            let left = PocketToday.chores(board, me: me.id).mine.filter { !$0.isDone }.map(\.chore.title)
            if left.count == 1 {
                sentences.append("You have 1 chore left: \(left[0]).")
            } else if !left.isEmpty {
                sentences.append("You have \(left.count) chores left: \(ListFormatter.localizedString(byJoining: left)).")
            }
        }
        let home = who.isOneOfSeveral ? "at \(who.household.name)" : "at home"
        guard !sentences.isEmpty else { return .answer(Answer(text: "Nothing is waiting \(home) right now.", wrote: false)) }
        return .answer(Answer(text: sentences.joined(separator: " "), detail: who.isOneOfSeveral ? who.household.name : nil, wrote: false))
    }
}
