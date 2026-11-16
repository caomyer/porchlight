import SwiftUI

/// Shown on a launch with no household while sync looks for one in iCloud, so a new or wiped
/// iPad signed in to the family's account opens its household instead of setting up a new one
/// (docs/design/sync-icloud.md, "A fresh install looks for a household first").
///
/// After a few seconds it offers to start fresh, for an account that has no household yet.
struct HouseholdSearchView: View {
    @Environment(SyncController.self) private var sync
    @State private var offersFreshStart = false

    /// Long enough that a quick answer never shows the button, short enough not to feel stuck.
    static let freshStartDelay: Duration = .seconds(4)

    var body: some View {
        VStack(spacing: 22) {
            Logo(size: 56)
            VStack(spacing: 8) {
                Text("Looking for your household in iCloud")
                    .font(.display(38))
                Text("If this iPad's iCloud has a Porchlight household, it opens in a moment.")
                    .font(.body(16, weight: 500))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 560)
            }
            .multilineTextAlignment(.center)
            ProgressView()
                .controlSize(.large)
                .tint(Theme.muted)
                .padding(.top, 4)
            Button("Start fresh instead") { sync.stopLookingForHousehold() }
                .buttonStyle(SecondaryButtonStyle())
                .opacity(offersFreshStart ? 1 : 0)
                .disabled(!offersFreshStart)
                .accessibilityHidden(!offersFreshStart)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("household-search")
        .task {
            try? await Task.sleep(for: Self.freshStartDelay)
            withAnimation(.easeOut(duration: 0.3)) { offersFreshStart = true }
        }
    }
}
