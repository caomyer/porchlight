import SwiftUI

/// The phone: a welcome when there is no household yet, "Which one is you?" until a
/// personal device knows whose it is, then the four tabs.
struct PocketRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device

    var body: some View {
        Group {
            if let household = model.household, household.setupCompleted {
                let me = device.me(in: household.id).flatMap(model.people.person)
                if device.role == .personal && me == nil {
                    WhoAreYouView { device.setMe($0, in: household.id) }
                } else {
                    PocketShell()
                        .environment(\.me, me)
                }
            } else {
                PocketWelcome()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }
}

extension EnvironmentValues {
    /// The person this device belongs to, on a personal device. Nil on a shared screen,
    /// which asks who did something instead.
    @Entry var me: Person? = nil

    /// Opens the You sheet; every tab's avatar calls it.
    @Entry var openYou: OpenYouAction? = nil
}

/// Opens the You sheet.
struct OpenYouAction {
    let open: @MainActor () -> Void
    @MainActor func callAsFunction() { open() }
}

/// The first screen on a phone that isn't in a household. Joining happens from an
/// invite link, which a later version brings, so this only says so.
struct PocketWelcome: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Logo(size: 64)
                Text("Porchlight")
                    .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Your family's day in one place: who walked the dog, what's for dinner, who pitched in.")
                    .phoneFont(.body, 15, weight: 500)
                    .foregroundStyle(Theme.muted)
                Text("On iPhone, Porchlight joins a household from an invite link sent from your family's shared screen. Invites arrive in a coming version.")
                    .phoneFont(.body, 15, weight: 500)
                    .foregroundStyle(Theme.muted)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)
            .padding(.horizontal, 24)
            .padding(.top, 110)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
