import SwiftUI

/// The Calendar destination: Week / Month / Day (STUB).
/// `lanes` come from other features (walks, meals) and are drawn under the week
/// grid and inside month cells.
struct CalendarScreen: View {
    var lanes: [CalendarLane]

    var body: some View {
        EmptyState(symbol: "calendar", title: "Calendar", message: "Coming soon.")
    }
}

/// "Coming up" countdown card for Today (STUB).
struct CountdownsCard: View {
    var body: some View { EmptyView() }
}

/// Calendar section inside Settings (STUB).
struct CalendarSettingsSection: View {
    var body: some View { EmptyView() }
}

/// Onboarding step: connect calendars (STUB).
struct CalendarOnboardingStep: View {
    var body: some View { EmptyView() }
}
