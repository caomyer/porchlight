import SwiftUI

/// The phone: an invite that opened the app, or the household having left, first; else a
/// welcome when there is no household yet, "Which one is you?" until a personal device
/// knows whose it is, then the four tabs.
struct PocketRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device
    @Environment(ShareInbox.self) private var inbox

    var body: some View {
        Group {
            if let invitation = inbox.invitation {
                JoinFlowView(invitation: invitation)
            } else if let removed = model.removedHousehold {
                RemovedHouseholdView(removed: removed)
            } else if let household = model.household, household.setupCompleted {
                let me = device.me(in: household.id).flatMap(model.people.person)
                if device.role == .personal && me == nil {
                    WhoAreYouView { device.setMe($0, in: household.id) }
                } else {
                    PocketShell()
                        .environment(\.me, me)
                }
            } else {
                PocketStart()
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

/// Opens the You sheet, at its top or on one of its pages (an empty tab opens Household).
struct OpenYouAction {
    let open: @MainActor (YouPage?) -> Void
    @MainActor func callAsFunction(_ page: YouPage? = nil) { open(page) }
}

/// The first screen on a phone that isn't in a household (`a2welcome`): two doors, start
/// a household here or join one, and how joining works (an invite someone sent, or the code
/// on the family's shared screen).
///
/// A fresh install signed in to iCloud first looks for a household there, as the wall does;
/// while it looks, starting one waits a few seconds, so a family's household opens instead
/// of a second one being made.
struct PocketWelcome: View {
    let onStart: () -> Void

    @Environment(SyncController.self) private var sync
    @State private var showsJoin = false
    @State private var waited = false

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
                VStack(spacing: 10) {
                    if sync.isLookingForHousehold {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking for a household in your iCloud")
                                .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                                .foregroundStyle(Theme.muted)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("household-search")
                    }
                    Button("Start a household", action: start)
                        .buttonStyle(PhoneButtonStyle())
                        .disabled(sync.isLookingForHousehold && !waited)
                        .accessibilityIdentifier("start-household")
                    Button("Join one") { withAnimation(.easeOut(duration: 0.2)) { showsJoin.toggle() } }
                        .buttonStyle(PhoneButtonStyle(kind: .ghost))
                        .accessibilityIdentifier("join-one")
                    if showsJoin {
                        VStack(alignment: .leading, spacing: 0) {
                            way("✉️", "Open the invite someone sent you", "It opens Porchlight and asks if you want to join.")
                            RowDivider()
                            way("📷", "Or scan your family's code", "On the shared screen, open Settings › Family & devices › Show a code to join, and point the Camera app at it.")
                        }
                        .padding(.horizontal, 14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    } else {
                        Text("To join, open the invite someone sent you or scan the code on your family's screen.")
                            .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 40)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)
            .padding(.horizontal, 24)
            .padding(.top, 90)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Scrolled text never shows under the clock: these screens stand alone, outside
        // the tabs, so they keep their content inside the safe area as well as painting
        // paper behind the status bar.
        .clipped()
        .paperUnderStatusBar()
        .task {
            try? await Task.sleep(for: HouseholdSearchView.freshStartDelay)
            waited = true
        }
    }

    /// Starting here ends the search: this iCloud has no household, or the person wants a new one.
    private func start() {
        if sync.isLookingForHousehold { sync.stopLookingForHousehold() }
        onStart()
    }

    private func way(_ emoji: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).phoneFont(.body, 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                Text(detail)
                    .phoneFont(.body, 12.5, weight: 600, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
