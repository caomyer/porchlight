import AppIntents
import SwiftUI

// Siri and Shortcuts (journey C4). These live only in the app, so iOS runs them in the
// app's process, launching it in the background when it isn't running. The work itself is
// `IntentWork`, on the database this launch opened (docs/design/beyond-the-app.md).

/// What a background action works on: this launch's database, the widgets' keeper and
/// sync, or a test's. Launching the app opens all three (`PorchlightApp`), also when iOS
/// launches it in the background just to run an intent or a reminder's action.
@MainActor
struct IntentLaunch {
    var database: AppDatabase?
    var settings: DeviceSettings
    var keeper: WidgetSummaryKeeper?
    var sync: SyncController?
    /// Asks for a later try at what didn't reach iCloud (`SyncSendRetry`).
    var retry: (SyncController.SendOutcome) -> Void

    static var current: IntentLaunch {
        IntentLaunch(
            database: AppDatabase.launched, settings: DeviceSettings(), keeper: WidgetSummaryKeeper.shared,
            sync: SyncController.current, retry: { SyncSendRetry.after($0) }
        )
    }
}

/// Runs an intent's work on this launch's database, then tells the widgets and sync.
@MainActor
enum IntentRunner {
    @discardableResult
    static func run(in launch: IntentLaunch = .current, _ work: (AppDatabase, DeviceSettings, Date) async -> IntentWork.Outcome) async -> IntentWork.Outcome {
        guard let database = launch.database else { return .refused(.notOpen) }
        let outcome = await work(database, launch.settings, CompanionClock.now())
        if outcome.wrote { await afterWrite(launch) }
        return outcome
    }

    /// The widgets draw the change at once; sync sends it before iOS suspends the app, and
    /// what doesn't make it in time is tried again a little later, in the background.
    static func afterWrite(_ launch: IntentLaunch = .current) async {
        await launch.keeper?.refresh()
        guard let sync = launch.sync else { return }
        launch.retry(await sync.sendSoon())
    }

    @discardableResult
    static func logSlot(routineId: String, slot: Int, day: String, in launch: IntentLaunch = .current) async -> IntentWork.Outcome? {
        guard let routine = CareRoutine.ID(routineId) else { return nil }
        return await run(in: launch) { await IntentWork.logSlot(routineId: routine, slot: slot, day: DayKey(rawValue: day), database: $0, settings: $1, now: $2) }
    }

    static func checkChore(choreId: String, day: String) async {
        guard let chore = Chore.ID(choreId) else { return }
        await run { await IntentWork.checkChore(choreId: chore, day: DayKey(rawValue: day), database: $0, settings: $1, now: $2) }
    }

    static func companions() async -> [CompanionEntity] {
        guard let database = AppDatabase.launched,
              let snapshot = try? await database.writer.read(CompanionSnapshot.fetch) else { return [] }
        return snapshot.companions.map { CompanionEntity(id: $0.id.description, name: $0.name, face: $0.species.emoji) }
    }

    /// An intent's answer as Siri's dialog, or the error that asks to open the app.
    static func dialog(_ outcome: IntentWork.Outcome, continuing intent: some ForegroundContinuableIntent) throws -> IntentWork.Answer {
        switch outcome {
        case let .answer(answer):
            return answer
        case let .refused(refusal) where refusal.opensApp:
            throw intent.needsToContinueInForegroundError(IntentDialog(stringLiteral: refusal.text))
        case let .refused(refusal):
            return IntentWork.Answer(text: refusal.text, wrote: false)
        }
    }
}

/// What an answer shows under Siri's words: the atlas's card ("Logged Yo-Yo's evening
/// walk", "For James at 6:12 pm · +1 star").
struct IntentAnswerView: View {
    let answer: IntentWork.Answer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(answer.text)
                .font(.body(17, weight: 700))
            if let detail = answer.detail {
                Text(detail)
                    .font(.body(14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

// MARK: - Care

/// A kind of care, for "I walked Yo-Yo" and "I fed Miso".
enum CareKindOption: String, AppEnum {
    case walk, feed, litter, water, groom, meds, play, clean

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Care")
    static let caseDisplayRepresentations: [CareKindOption: DisplayRepresentation] = [
        .walk: "Walk", .feed: "Meal", .litter: "Litter", .water: "Watering",
        .groom: "Grooming", .meds: "Meds", .play: "Play", .clean: "Cleanup",
    ]

    var kind: CareKind { CareKind(rawValue: rawValue) ?? .custom }
}

/// A routine, for Shortcuts that log one routine exactly.
struct RoutineEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Routine")
    static let defaultQuery = RoutineQuery()

    var id: String
    var title: String
    var companion: String
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(companion) · \(title)", subtitle: "\(emoji)")
    }
}

struct RoutineQuery: EntityStringQuery {
    @MainActor
    func suggestedEntities() async throws -> [RoutineEntity] {
        guard let database = AppDatabase.launched,
              let snapshot = try? await database.writer.read(CompanionSnapshot.fetch) else { return [] }
        let names = Dictionary(uniqueKeysWithValues: snapshot.companions.map { ($0.id, $0.name) })
        return snapshot.routines.map {
            RoutineEntity(id: $0.id.description, title: $0.title, companion: names[$0.companionId] ?? "", emoji: $0.emoji)
        }
    }

    func entities(for identifiers: [String]) async throws -> [RoutineEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [RoutineEntity] {
        try await suggestedEntities().filter { $0.title.localizedStandardContains(string) || $0.companion.localizedStandardContains(string) }
    }
}

/// "I walked Yo-Yo", "Log care for Miso": logs the slot one tap on Today would, for me.
struct LogCareIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Log care"
    static let description = IntentDescription("Logs a companion's care for you, like one tap on Today. If someone already did it, says who.")

    @Parameter(title: "Companion") var companion: CompanionEntity
    @Parameter(title: "Care") var care: CareKindOption?
    @Parameter(title: "Routine") var routine: RoutineEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$care) for \(\.$companion)") { \.$routine }
    }

    init() {}

    init(companion: CompanionEntity, care: CareKindOption?) {
        self.companion = companion
        self.care = care
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let companionId = Companion.ID(companion.id)
        let routineId = routine.flatMap { CareRoutine.ID($0.id) }
        let outcome = await IntentRunner.run { database, settings, now in
            guard let companionId else { return .answer(.init(text: "That companion isn't in Porchlight anymore.", wrote: false)) }
            return await IntentWork.logCare(companionId: companionId, routineId: routineId, kind: care?.kind, database: database, settings: settings, now: now)
        }
        let answer = try IntentRunner.dialog(outcome, continuing: self)
        return .result(dialog: IntentDialog(stringLiteral: answer.text), view: IntentAnswerView(answer: answer))
    }
}

/// "I walked Yo-Yo": log care with the walk already chosen, so the phrase needs nothing more.
struct LogWalkIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Log a walk"
    static let description = IntentDescription("Logs a walk for you. If someone already walked them, says who.")

    @Parameter(title: "Companion") var companion: CompanionEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try await LogCareIntent.perform(companion: companion, kind: .walk, continuing: self)
    }
}

/// "I fed Miso".
struct LogMealIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Log a meal"
    static let description = IntentDescription("Logs a meal for you. If someone already fed them, says who.")

    @Parameter(title: "Companion") var companion: CompanionEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try await LogCareIntent.perform(companion: companion, kind: .feed, continuing: self)
    }
}

extension LogCareIntent {
    @MainActor
    static func perform(companion: CompanionEntity, kind: CareKind, continuing intent: some ForegroundContinuableIntent) async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let companionId = Companion.ID(companion.id)
        let outcome = await IntentRunner.run { database, settings, now in
            guard let companionId else { return .answer(.init(text: "That companion isn't in Porchlight anymore.", wrote: false)) }
            return await IntentWork.logCare(companionId: companionId, routineId: nil, kind: kind, database: database, settings: settings, now: now)
        }
        let answer = try IntentRunner.dialog(outcome, continuing: intent)
        return .result(dialog: IntentDialog(stringLiteral: answer.text), view: IntentAnswerView(answer: answer))
    }
}

// MARK: - Chores

/// One of today's chores I can check off: mine, or anyone's.
struct ChoreEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Chore")
    static let defaultQuery = ChoreQuery()

    var id: String
    var title: String
    var emoji: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: emoji.map { "\($0)" })
    }
}

struct ChoreQuery: EntityStringQuery {
    @MainActor
    func suggestedEntities() async throws -> [ChoreEntity] {
        guard let database = AppDatabase.launched else { return [] }
        return await IntentWork.choresToday(database: database, settings: DeviceSettings(), now: CompanionClock.now())
            .map { ChoreEntity(id: $0.id.description, title: $0.title, emoji: $0.emoji) }
    }

    func entities(for identifiers: [String]) async throws -> [ChoreEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ChoreEntity] {
        try await suggestedEntities().filter { $0.title.localizedStandardContains(string) }
    }
}

/// "Done with recycling": checks a chore off for me today.
struct CheckOffChoreIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Check off a chore"
    static let description = IntentDescription("Checks one of today's chores off for you. If someone already did it, says who.")

    @Parameter(title: "Chore") var chore: ChoreEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check off \(\.$chore)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let choreId = Chore.ID(chore.id)
        let outcome = await IntentRunner.run { database, settings, now in
            guard let choreId else { return .answer(.init(text: "That chore isn't in Porchlight anymore.", wrote: false)) }
            let calendar = (try? await database.writer.read(CompanionSnapshot.fetch))?.calendar ?? .current
            return await IntentWork.checkChore(choreId: choreId, day: DayKey(now, calendar: calendar), database: database, settings: settings, now: now)
        }
        let answer = try IntentRunner.dialog(outcome, continuing: self)
        return .result(dialog: IntentDialog(stringLiteral: answer.text), view: IntentAnswerView(answer: answer))
    }
}

// MARK: - Lists

struct ListEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "List")
    static let defaultQuery = ListQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ListQuery: EntityStringQuery {
    @MainActor
    func suggestedEntities() async throws -> [ListEntity] {
        guard let database = AppDatabase.launched else { return [] }
        return await IntentWork.lists(database: database).map { ListEntity(id: $0.id.description, title: $0.title) }
    }

    func entities(for identifiers: [String]) async throws -> [ListEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ListEntity] {
        try await suggestedEntities().filter { $0.title.localizedStandardContains(string) }
    }
}

/// "Add oat milk to groceries".
struct AddListItemIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Add to a list"
    static let description = IntentDescription("Adds an item to one of the household's lists, groceries unless you pick another.")

    @Parameter(title: "Item", requestValueDialog: "What should I add?") var item: String
    @Parameter(title: "List") var list: ListEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to \(\.$list)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let listId = list.flatMap { HomeList.ID($0.id) }
        let outcome = await IntentRunner.run { await IntentWork.addItem(item, listId: listId, database: $0, settings: $1, now: $2) }
        let answer = try IntentRunner.dialog(outcome, continuing: self)
        return .result(dialog: IntentDialog(stringLiteral: answer.text), view: IntentAnswerView(answer: answer))
    }
}

// MARK: - What's next

/// "What's on at home today?": open care and my chores left.
struct WhatsNextIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "What's next"
    static let description = IntentDescription("Says which care is open now and which of your chores are left today.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let outcome = await IntentRunner.run { await IntentWork.whatsNext(database: $0, settings: $1, now: $2) }
        let answer = try IntentRunner.dialog(outcome, continuing: self)
        return .result(dialog: IntentDialog(stringLiteral: answer.text), view: IntentAnswerView(answer: answer))
    }
}

// MARK: - App Shortcuts

/// Phrases that work as soon as the app is installed, and the actions' tiles in Shortcuts.
struct PorchlightShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWalkIntent(),
            phrases: [
                "I walked \(\.$companion) in \(.applicationName)",
                "Log a walk in \(.applicationName)",
                "Log \(\.$companion)'s walk in \(.applicationName)",
            ],
            shortTitle: "Log a walk",
            systemImageName: "pawprint"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "I fed \(\.$companion) in \(.applicationName)",
                "Log a meal in \(.applicationName)",
            ],
            shortTitle: "Log a meal",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogCareIntent(),
            phrases: [
                "Log care for \(\.$companion) in \(.applicationName)",
                "Log care in \(.applicationName)",
            ],
            shortTitle: "Log care",
            systemImageName: "heart"
        )
        AppShortcut(
            intent: CheckOffChoreIntent(),
            phrases: [
                "Check off a chore in \(.applicationName)",
                "Check off \(\.$chore) in \(.applicationName)",
            ],
            shortTitle: "Check off a chore",
            systemImageName: "checkmark.square"
        )
        AppShortcut(
            intent: AddListItemIntent(),
            phrases: [
                "Add to my list in \(.applicationName)",
                "Add to groceries in \(.applicationName)",
            ],
            shortTitle: "Add to a list",
            systemImageName: "cart"
        )
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "What's on at home in \(.applicationName)",
            ],
            shortTitle: "What's next",
            systemImageName: "house"
        )
    }
}
