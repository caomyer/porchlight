import AppIntents
import Foundation

// The intents a widget's buttons and configuration use. This file is compiled into the
// app and the widget extension: the extension needs the types to draw `Button(intent:)`,
// but `perform()` always runs in the app (docs/design/beyond-the-app.md, "Intents").

/// Logs one slot of a routine on a day for "me", from a widget's button.
///
/// A `LiveActivityIntent` because iOS 17 runs those in the app's process even when a widget
/// starts them, so the write goes through the app's one database and its sync engine.
struct LogSlotIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a care slot"
    static let description = IntentDescription("Logs one care slot from a widget.")
    /// Only widgets use it; people use "Log care" (`LogCareIntent`).
    static let isDiscoverable = false

    @Parameter(title: "Routine") var routineId: String
    @Parameter(title: "Slot") var slot: Int
    @Parameter(title: "Day") var day: String

    init() {}

    init(routineId: String, slot: Int, day: String) {
        self.routineId = routineId
        self.slot = slot
        self.day = day
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await IntentRunner.logSlot(routineId: routineId, slot: slot, day: day)
        #endif
        return .result()
    }
}

/// Checks one of my chores off on a day, from a widget's check box.
struct CheckChoreIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Check off a chore from a widget"
    static let description = IntentDescription("Checks one chore off from a widget.")
    static let isDiscoverable = false

    @Parameter(title: "Chore") var choreId: String
    @Parameter(title: "Day") var day: String

    init() {}

    init(choreId: String, day: String) {
        self.choreId = choreId
        self.day = day
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await IntentRunner.checkChore(choreId: choreId, day: day)
        #endif
        return .result()
    }
}

/// A companion, for Siri ("I walked Yo-Yo"), Shortcuts and the companion widget's setting.
struct CompanionEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Companion")
    static let defaultQuery = CompanionQuery()

    var id: String
    var name: String
    var face: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(face)")
    }
}

/// Finds companions: in the app from the database, in the widget extension from the
/// summary (the extension never opens the database).
struct CompanionQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CompanionEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [CompanionEntity] {
        try await suggestedEntities().filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [CompanionEntity] {
        #if WIDGET_EXTENSION
        (WidgetSummaryFile.read()?.companions ?? []).map { CompanionEntity(id: $0.id, name: $0.name, face: $0.face) }
        #else
        await IntentRunner.companions()
        #endif
    }
}

/// The companion widget's one setting: which companion it shows.
struct SelectCompanionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Companion"
    static let description = IntentDescription("Shows one companion's care, with a button to log it.")

    @Parameter(title: "Companion") var companion: CompanionEntity?

    init() {}

    init(companion: CompanionEntity?) {
        self.companion = companion
    }
}
