import SwiftUI

/// A companion's page (STUB).
struct CompanionScreen: View {
    var companionId: Int64
    var body: some View { EmptyState(symbol: "pawprint", title: "Companion", message: "Coming soon.") }
}

/// The small face used as the rail icon (STUB).
struct CompanionRailIcon: View {
    var companionId: Int64
    var body: some View { Image(systemName: "pawprint") }
}

/// Companion cards for Today, one per companion (STUB).
struct CompanionTodayCards: View {
    var body: some View { EmptyView() }
}

/// Companions section inside Settings (STUB).
struct CompanionSettingsSection: View {
    var body: some View { EmptyView() }
}

/// Onboarding step: who else lives here (STUB).
struct CompanionOnboardingStep: View {
    var body: some View { EmptyView() }
}
