import SwiftUI

/// "You", from the avatar on every tab: who you are (and a way to change it), the
/// household, and what this device does. Only what works today is here; inviting,
/// notifications, calendars, storage and leaving arrive with their own milestones.
struct YouSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss

    @State private var path: [Page] = []

    private enum Page: Hashable { case whoAreYou }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 18) {
                    identity
                    VStack(spacing: 0) {
                        if let household = model.household {
                            InfoRow(emoji: "🏡", title: household.name, detail: peopleLine)
                            RowDivider()
                        }
                        InfoRow(emoji: "📱", title: "This \(DeviceWords.this)", detail: roleLine)
                        if device.role == .personal {
                            RowDivider()
                            Button { path.append(.whoAreYou) } label: {
                                InfoRow(emoji: "🙋", title: "This \(DeviceWords.this) is \(me?.name ?? "me")", detail: "Change who you are here", chevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("change-me")
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .phoneFont(.body, 15, weight: 700)
                        .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(for: Page.self) { _ in
                WhoAreYouView(current: me?.id) { picked in
                    if let household = model.household { device.setMe(picked, in: household.id) }
                    path.removeAll()
                }
                .background(Theme.background)
            }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.background)
    }

    private var identity: some View {
        VStack(spacing: 6) {
            PersonAvatar(me, size: .large)
            Text(me?.name ?? "This \(DeviceWords.this)")
                .phoneFont(.display, 24, weight: 600, relativeTo: .title)
                .accessibilityAddTraits(.isHeader)
            if let household = model.household {
                Text([household.name, device.role == .personal ? "this \(DeviceWords.this) credits you" : "a shared screen"].joined(separator: " · "))
                    .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var peopleLine: String {
        let names = model.people.map(\.name)
        return names.count == 1 ? "Just \(names[0])" : "\(names.count) people · " + ListFormatter.localizedString(byJoining: names)
    }

    private var roleLine: String {
        switch device.role {
        case .personal: "Personal: what you log is credited to you"
        case .sharedScreen: "Shared screen: asks who did it"
        }
    }
}

/// A row in the You sheet: an emoji, a title and a line under it.
private struct InfoRow: View {
    let emoji: String
    let title: String
    let detail: String
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji).phoneFont(.body, 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                Text(detail)
                    .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The hairline between rows in a list card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}
