import Foundation
import Observation

/// Live food diary state (STUB: owned by the Food feature).
@MainActor
@Observable
final class FoodStore {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// Whether the household uses the food diary (controls the rail entry).
    var isEnabled: Bool { false }

    /// Logged meals for the Today agenda.
    func timelineItems(for day: DayKey) -> [TimelineItem] { [] }

    /// Mini-plate lanes for the week grid and month cells.
    func calendarLanes() -> [CalendarLane] { [] }

    /// Recent meal photos, offered to Ambient mode as a photo source.
    func recentPhotoURLs(limit: Int) -> [URL] { [] }
}
