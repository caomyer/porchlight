import SwiftUI
import UIKit

// MARK: - A companion (f2companion)

/// One companion in the wall's own editor, laid out for the phone; new when `companionId` is nil.
struct PocketCompanionPage: View {
    let companionId: Companion.ID?

    @Environment(CompanionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let companion = companionId.flatMap { id in store.snapshot.companions.first { $0.id == id } }
        CompanionEditSheet(initial: companion.map(store.draft(of:)) ?? .new(species: .dog)) { dismiss() }
            .navigationTitle(companion?.name ?? "New companion")
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
    }
}

// MARK: - Leaving (A6)

/// Leaving the household from the phone. A member leaves (`a6leave`): it goes from this
/// phone, and everything they logged stays with the household. The owner can't (`a6owner`):
/// the household is in their iCloud, so leaving would delete it for everyone; they're
/// pointed to removing someone instead.
struct PocketLeaveSheet: View {
    let onManage: () -> Void
    let onLeft: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(SyncController.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var isLeaving = false
    @State private var failure: String?

    var body: some View {
        let name = model.household?.name ?? "the household"
        let owner = sharing.ownerName(people: model.everyone, devices: model.devices)
        if sharing.members.isOwner {
            PhoneSheet(label: name, title: "You own \(name)") {
                Text(ownerText(name))
                    .phoneFont(.body, 14.5, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("leave-explanation")
            } footer: {
                VStack(spacing: 8) {
                    Button("Manage members", action: onManage)
                        .buttonStyle(PhoneButtonStyle())
                        .accessibilityIdentifier("manage-members")
                    Button("Close") { dismiss() }
                        .buttonStyle(PhoneButtonStyle(kind: .ghost))
                }
            }
        } else {
            PhoneSheet(label: name, title: "Leave \(name)?") {
                Text("It disappears from this \(DeviceWords.this) and your reminders for it stop. Everything you logged stays with the household, and \(owner ?? "its owner") can invite you back.")
                    .phoneFont(.body, 14.5, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("leave-explanation")
                if let failure {
                    Text(failure)
                        .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("leave-failure")
                }
            } footer: {
                VStack(spacing: 8) {
                    Button(action: leave) {
                        if isLeaving { ProgressView().tint(Theme.accentInk) } else { Text("Leave") }
                    }
                    .buttonStyle(PhoneButtonStyle(kind: .destructive))
                    .disabled(isLeaving)
                    .accessibilityIdentifier("confirm-leave")
                    Button("Cancel") { dismiss() }
                        .buttonStyle(PhoneButtonStyle(kind: .ghost))
                        .disabled(isLeaving)
                }
            }
        }
    }

    /// Why the owner can't just leave, true to where the household lives.
    private func ownerText(_ name: String) -> String {
        let others = model.people.count > 1 ? "everyone else" : "anyone you invite"
        switch HouseholdHome.from(sync.status, isOwner: true, ownerName: nil) {
        case .yourICloud, .ownersICloud:
            return "It's stored in your iCloud, so leaving would delete it for \(others). To stop sharing with one person, remove their phone in Household."
        default:
            return "It's \(HouseholdHome.from(sync.status, isOwner: true, ownerName: nil).whereText(device: DeviceWords.this)), so leaving would delete it. To stop sharing with one person, remove their phone in Household."
        }
    }

    private func leave() {
        guard let household = model.household else { return }
        isLeaving = true
        failure = nil
        Task {
            do {
                try await sharing.leave(household, app: model)
                dismiss()
                onLeft()
            } catch {
                failure = "Couldn't leave. Check that this \(DeviceWords.this) is online, then try again."
                isLeaving = false
            }
        }
    }
}

// MARK: - Storage (E4)

/// What the household takes up (`e4storage`): where it's stored, in `HouseholdHome`'s words;
/// a meter of photos, Pencil pages and everything else, summed from its rows; the photos you
/// added; and what to do when the owner's iCloud is full.
struct PocketStoragePage: View {
    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(SyncController.self) private var sync
    @Environment(\.me) private var me
    @State private var storage: HouseholdStorage?

    var body: some View {
        let owner = sharing.ownerName(people: model.everyone, devices: model.devices)
        let home = HouseholdHome.from(sync.status, isOwner: sharing.members.isOwner, ownerName: owner)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(small: model.household?.name, title: "iCloud storage")
                if sync.status == .iCloudFull {
                    fullBanner(owner: owner)
                }
                VStack(alignment: .leading, spacing: 10) {
                    let place = home.whereText(device: DeviceWords.this)
                    Text(place.prefix(1).uppercased() + place.dropFirst())
                        .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
                        .accessibilityIdentifier("storage-home")
                    if let storage {
                        StorageMeter(storage: storage)
                        Text(StorageWords.breakdown(storage))
                            .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("storage-breakdown")
                        if storage.lastMonth > 0 {
                            Text("Photos added in the last 30 days: \(StorageWords.size(storage.lastMonth)).")
                                .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    Text(whoseLine(home, owner: owner))
                        .phoneFont(.body, 13, weight: 500, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .phoneCard()
                if let storage {
                    PhoneList {
                        InfoRow(emoji: "🖼️", title: "Your photos here", detail: storage.mine > 0 ? "\(StorageWords.size(storage.mine)) · the meal photos you added" : "None yet: meal photos you add show here")
                            .accessibilityIdentifier("storage-mine")
                    }
                }
                Text("Every device in the household keeps every photo, at 2048 pixels on its long side, which is the photo itself. A busy family adds about 300 MB a year.")
                    .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("iCloud storage")
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        .task(id: model.snapshot) { await measure() }
    }

    private func measure() async {
        guard let household = model.household else { return }
        let mine = model.devices.filter { $0.owner != nil && $0.owner == me?.id }.map(\.id)
        let database = model.database
        storage = await Task.detached(priority: .userInitiated) {
            try? database.storage(of: household.id, mine: mine)
        }.value
    }

    /// Whose iCloud it counts against.
    private func whoseLine(_ home: HouseholdHome, owner: String?) -> String {
        switch home {
        case .yourICloud: "It counts toward your iCloud storage. Everyone you invite uses it through yours, at no cost to theirs."
        case .ownersICloud: "It counts toward \(owner.map { $0.possessive } ?? "its owner's") iCloud storage, and uses almost none of yours."
        default: "Nothing is in iCloud yet, so it takes room only on this \(DeviceWords.this)."
        }
    }

    /// Sync paused because the owner's iCloud is full, and what to do about it.
    private func fullBanner(owner: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if sharing.members.isOwner {
                StatusBanner(tone: .warn, emoji: "⏸️", title: "Sync is paused: your iCloud is full", detail: "Everything still works on this \(DeviceWords.this), and nothing is lost. Changes send as soon as there's room.")
                Text("In the Settings app, tap your name, then iCloud, to free up space or choose a bigger plan.")
                    .phoneFont(.body, 13, weight: 500, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
            } else {
                StatusBanner(tone: .warn, emoji: "⏸️", title: "Sync is paused: \(owner.map { $0.possessive } ?? "the owner's") iCloud is full", detail: "Your changes are safe on this \(DeviceWords.this), and send once \(owner ?? "they") free up space or choose a bigger plan.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storage-full")
    }
}

/// Photos, Pencil pages and everything else, as one bar.
private struct StorageMeter: View {
    let storage: HouseholdStorage

    var body: some View {
        GeometryReader { proxy in
            let total = max(storage.total, 1)
            let parts: [(Int, Color)] = [(storage.photos, PersonColor.coral.color), (storage.pages, PersonColor.ochre.color), (storage.other, PersonColor.blue.color)]
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if part.0 > 0 {
                        Rectangle().fill(part.1).frame(width: max(proxy.size.width * CGFloat(part.0) / CGFloat(total) - 2, 3))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 12)
        .background(Theme.surface2)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
