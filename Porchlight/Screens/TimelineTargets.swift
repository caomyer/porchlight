import SwiftUI

extension View {
    /// Lets anything inside open a `TimelineTarget` (a walk, a meal, an event, a chore) with
    /// the same sheet it opens everywhere else. Applied once around the wall's screens.
    func opensTimelineTargets() -> some View {
        modifier(TimelineTargetHost())
    }
}

private struct TimelineTargetHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(FoodStore.self) private var food
    @Environment(HomeStore.self) private var home

    @State private var careRequest: CareLogRequest?
    @State private var openMeal: OpenMeal?
    @State private var openEvent: CalendarEvent?
    @State private var choreSheet: ChoreSheet?

    /// A meal, looked up live so edits show at once.
    private struct OpenMeal: Identifiable {
        var id: JournalEntry.ID
    }

    func body(content: Content) -> some View {
        content
            .environment(\.openTimelineTarget, OpenTimelineTargetAction { open($0) })
            .careLogFlow($careRequest)
            .wallCover(item: $openMeal) { meal in
                if let entry = food.snapshot.entries.first(where: { $0.id == meal.id }) {
                    MealDetailSheet(entry: entry) { CompanionCover.instantly { openMeal = nil } }
                }
            }
            .wallCover(item: $openEvent) { event in
                WallSheet(width: 540, onClose: { CompanionCover.instantly { openEvent = nil } }) {
                    EventDetail(event: event, calendar: model.calendar)
                }
            }
            .choreSheets($choreSheet)
    }

    private func open(_ target: TimelineTarget) {
        CompanionCover.instantly {
            switch target {
            case let .careLog(companionId, routineId, logId):
                careRequest = CareLogRequest(companionId: companionId, routineId: routineId, logId: logId)
            case let .careDue(companionId, routineId):
                careRequest = CareLogRequest(companionId: companionId, routineId: routineId)
            case let .careMissed(companionId, routineId, day, slot):
                careRequest = .catchUp(companionId: companionId, routineId: routineId, day: day, slot: slot)
            case let .meal(id):
                openMeal = OpenMeal(id: id)
            case let .event(id):
                openEvent = calendarStore.events.first { $0.id == id }
            case let .chore(choreId, day):
                choreSheet = home.snapshot.chores.first { $0.id == choreId }.map { .task($0, day) }
            }
        }
    }
}
