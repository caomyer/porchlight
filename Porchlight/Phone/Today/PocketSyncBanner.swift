import SwiftUI
import UIKit

/// The one sync banner at the top of the phone's Today (journey E5), most urgent first,
/// in plain words with one fix. Sync shows here only once it is stuck: offline only after
/// an hour without syncing, and never a spinner.
struct PocketSyncNotice: Equatable {
    enum Fix: Equatable {
        /// "Choose": opens the You sheet, where the choice is.
        case openYou
        /// "Settings": opens iOS Settings, to sign in.
        case openSettings

        var title: String {
            switch self {
            case .openYou: "Choose"
            case .openSettings: "Settings"
            }
        }
    }

    var tone: StatusBanner.Tone
    var emoji: String
    var title: String
    var detail: String
    var fix: Fix?

    /// - Parameters:
    ///   - stuckLong: Sync has been stuck an hour (`SyncController.needsAttention`).
    ///   - ownerName: Whose iCloud holds the household, when it isn't this user's.
    static func pick(
        _ status: SyncStatus, stuckLong: Bool, householdName: String, ownerName: String?, device: String,
        calendar: Calendar = .current
    ) -> PocketSyncNotice? {
        switch status {
        case .needsDecision:
            return PocketSyncNotice(
                tone: .warn, emoji: "✋", title: "Sync is waiting for you",
                detail: "Choose what to do with \(householdName) on this \(device).", fix: .openYou
            )
        case .account(.signedOut):
            return PocketSyncNotice(
                tone: .warn, emoji: "👤", title: "iCloud is off for Porchlight",
                detail: "Sign in to iCloud, or turn it on for Porchlight, in Settings. \(householdName) stays on this \(device) meanwhile.",
                fix: .openSettings
            )
        case .account(.restricted):
            return PocketSyncNotice(
                tone: .warn, emoji: "🔒", title: "iCloud isn't allowed on this \(device)",
                detail: "Screen Time, or whoever manages this \(device), has turned it off. \(householdName) stays here but can't sync.",
                fix: .openSettings
            )
        case .account(.needsSignIn):
            return PocketSyncNotice(
                tone: .warn, emoji: "🔑", title: "iCloud needs you to sign in again",
                detail: "Sign in to your Apple Account in Settings. \(householdName) stays on this \(device) meanwhile.",
                fix: .openSettings
            )
        case .account(.couldNotCheck) where stuckLong:
            // Like being offline: worth a word only once it has lasted.
            return PocketSyncNotice(
                tone: .info, emoji: "☁️", title: "Can't check iCloud",
                detail: "Everything you log saves here and sends once iCloud answers."
            )
        case .iCloudFull:
            let whose = ownerName.map { $0.possessive } ?? "your"
            return PocketSyncNotice(
                tone: .warn, emoji: "⏸️", title: "Sync paused: \(whose) iCloud is full",
                detail: "Your changes are safe on this \(device)."
            )
        case let .notAccepted(count):
            return PocketSyncNotice(
                tone: .warn, emoji: "⏸️", title: "iCloud isn't taking changes yet",
                detail: "\(count == 1 ? "1 change is" : "\(count) changes are") safe on this \(device) and \(count == 1 ? "goes" : "go") up by \(count == 1 ? "itself" : "themselves") later."
            )
        case let .waiting(lastSynced) where stuckLong:
            let since = lastSynced.map { date in
                calendar.isDateInToday(date)
                    ? "since \(date.formatted(date: .omitted, time: .shortened))"
                    : "since \(date.formatted(.dateTime.month(.abbreviated).day()))"
            }
            return PocketSyncNotice(
                tone: .info, emoji: "📴", title: ["Offline", since].compactMap { $0 }.joined(separator: " "),
                detail: "Everything you log saves here and sends later."
            )
        case .waiting, .notChecked, .off, .upToDate, .syncing, .account(.couldNotCheck):
            return nil
        }
    }
}

/// Shows `PocketSyncNotice` for the household on screen, or `otherwise` when sync has
/// nothing to say, so Today never stacks two banners.
struct PocketSyncBanner<Otherwise: View>: View {
    @ViewBuilder var otherwise: () -> Otherwise

    @Environment(SyncController.self) private var sync
    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(\.openYou) private var openYou
    @Environment(\.openURL) private var openURL

    var body: some View {
        let owner = sharing.members.isOwner ? nil : sharing.ownerName(people: model.everyone, devices: model.devices)
        if let notice = PocketSyncNotice.pick(
            sync.status, stuckLong: sync.needsAttention, householdName: model.household?.name ?? "The household",
            ownerName: owner, device: DeviceWords.this
        ) {
            StatusBanner(
                tone: notice.tone, emoji: notice.emoji, title: notice.title, detail: notice.detail,
                action: notice.fix.map { fix in (fix.title, { run(fix) }) }
            )
            .accessibilityIdentifier("sync-banner")
        } else {
            otherwise()
        }
    }

    private func run(_ fix: PocketSyncNotice.Fix) {
        switch fix {
        case .openYou:
            openYou?()
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
}
