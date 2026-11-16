import SwiftUI

extension View {
    /// Keeps this phone's reminders in step with the household: reschedules when the app
    /// comes to the front, when care or chores change in the database (a log on this
    /// phone now, from another device once sync delivers it), and when a choice changes.
    /// Changes in a burst are coalesced into one reschedule.
    func keepsRemindersScheduled() -> some View {
        modifier(ReminderKeeper())
    }
}

private struct ReminderKeeper: ViewModifier {
    @Environment(CompanionStore.self) private var companions
    @Environment(HomeStore.self) private var home
    @Environment(ReminderSettings.self) private var settings
    @Environment(\.me) private var me
    @Environment(\.scenePhase) private var phase

    /// Everything a plan depends on; a new value restarts the debounce.
    private struct Inputs: Equatable {
        var companions: CompanionSnapshot
        var chores: [Chore]
        var completions: [ChoreCompletion]
        var choices: ReminderChoices
        var me: Person.ID?
        var isActive: Bool
    }

    func body(content: Content) -> some View {
        let inputs = Inputs(
            companions: companions.snapshot, chores: home.snapshot.chores, completions: home.snapshot.completions,
            choices: settings.choices, me: me?.id, isActive: phase == .active
        )
        content
            .task(id: inputs) {
                guard inputs.isActive else { return }
                // A notification action may have changed the choices while the app was away.
                settings.reload()
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await ReminderScheduler.refresh(database: companions.database)
            }
    }
}
