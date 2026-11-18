import Foundation

/// Where the household actually lives right now, as every screen that names it says it:
/// Family & devices on the wall, You and the invite page on the phone. It follows sync's
/// state, never the share alone: with sync off, nothing is in anyone's iCloud.
enum HouseholdHome: Equatable {
    /// Sync is off by choice: the household is on this device only.
    case thisDeviceOnly
    /// Sync can't run in this build or launch (sample data, no entitlement, failed to start).
    case syncUnavailable
    /// Syncing, in this user's own iCloud, said as "your" on someone's own device.
    case yourICloud
    /// Syncing, in its owner's iCloud, named: someone else's, or the owner's own as a
    /// shared screen says it ("James's iCloud" on the hallway wall). Nil when unknown.
    case ownersICloud(String?)
    /// iCloud can't be used with this device's account: here only until that changes.
    case noICloud(ICloudAccountProblem)
    /// Sync waits for a choice (a different account, a restored copy).
    case waitingForChoice

    /// - Parameters:
    ///   - isOwner: Whether this device's iCloud user owns the household's share (true
    ///     when nobody has been invited yet).
    ///   - ownerName: The owner's name, when known.
    ///   - onSharedScreen: A shared screen names the owner rather than saying "your", since
    ///     anyone in the family may be reading it.
    static func from(_ status: SyncStatus, isOwner: Bool, ownerName: String?, onSharedScreen: Bool = false) -> HouseholdHome {
        switch status {
        case .off(.switchedOff): .thisDeviceOnly
        case .off: .syncUnavailable
        case let .account(problem) where problem != .couldNotCheck: .noICloud(problem)
        case .needsDecision: .waitingForChoice
        // Not knowing the account says nothing about where the household is.
        case .upToDate, .notChecked, .syncing, .waiting, .iCloudFull, .notAccepted, .account:
            isOwner && (!onSharedScreen || ownerName == nil) ? .yourICloud : .ownersICloud(ownerName)
        }
    }

    /// "stored in James's iCloud", "on this iPad only".
    func whereText(device: String) -> String {
        switch self {
        case .thisDeviceOnly, .syncUnavailable: "on this \(device) only"
        case .yourICloud: "stored in your iCloud"
        case let .ownersICloud(name): "stored in \(name.map { $0.possessive } ?? "its owner's") iCloud"
        case .noICloud(.signedOut), .noICloud(.couldNotCheck): "on this \(device) until iCloud is on for Porchlight"
        case .noICloud(.restricted): "on this \(device) only, since iCloud isn't allowed here"
        case .noICloud(.needsSignIn): "on this \(device) until you sign in to iCloud again"
        case .waitingForChoice: "on this \(device) until you choose what to do about iCloud sync"
        }
    }

    /// Why inviting can't work now, in plain words; nil when it can.
    func inviteBlocker(device: String) -> String? {
        switch self {
        case .yourICloud, .ownersICloud: nil
        case .thisDeviceOnly: "Turn on iCloud sync to invite phones."
        case .syncUnavailable: "Inviting needs iCloud sync, which can't run on this \(device) now."
        case .noICloud(.signedOut), .noICloud(.couldNotCheck): "Sign in to iCloud, or turn it on for Porchlight, in the Settings app to invite phones."
        case .noICloud(.restricted): "iCloud isn't allowed on this \(device), so phones can't be invited from it."
        case .noICloud(.needsSignIn): "Sign in to iCloud again in the Settings app to invite phones."
        case .waitingForChoice: "Choose what to do about iCloud sync to invite phones."
        }
    }

    /// Sync is off by choice, so turning it on is the fix.
    var turnsOnWithTheSwitch: Bool { self == .thisDeviceOnly }
}
