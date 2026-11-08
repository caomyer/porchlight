import Foundation
import Observation

/// One companion as the rail needs it.
struct CompanionSummary: Identifiable, Equatable, Sendable {
    var id: Int64
    var name: String
}

/// Live companion state (STUB: owned by the Companions feature).
@MainActor
@Observable
final class CompanionStore {
    let database: AppDatabase
    private(set) var companions: [CompanionSummary] = []

    init(database: AppDatabase) {
        self.database = database
    }

    /// Walks and expected walks for the Today agenda.
    func timelineItems(for day: DayKey) -> [TimelineItem] { [] }

    /// Paw lanes for the week grid and month cells.
    func calendarLanes() -> [CalendarLane] { [] }
}
