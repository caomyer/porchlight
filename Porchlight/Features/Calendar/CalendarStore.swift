import Foundation
import Observation

/// Live calendar state for the wall (STUB: owned by the Calendar feature).
@MainActor
@Observable
final class CalendarStore {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// Timed events for the Today agenda.
    func timelineItems(for day: DayKey) -> [TimelineItem] { [] }

    /// All-day / multi-day chips for the Today agenda.
    func allDayItems(for day: DayKey) -> [AllDayItem] { [] }
}
