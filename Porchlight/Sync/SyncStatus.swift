import CloudKit
import Foundation

/// What the UI can say about sync (docs/design/sync-icloud.md, "Status the UI can show").
enum SyncStatus: Equatable, Sendable {
    case off(SyncOffReason)
    /// iCloud can't be used with this device's account, and why.
    case account(ICloudAccountProblem)
    /// iCloud answered a check in the last few minutes.
    case upToDate(lastSynced: Date?)
    /// Sync is on and online, but no check has been answered lately: just opened, or the
    /// checks aren't running. Never shown as up to date.
    case notChecked(lastSynced: Date?)
    case syncing
    /// Offline, or still checking the account; changes keep saving on the device meanwhile.
    case waiting(lastSynced: Date?)
    case iCloudFull
    /// iCloud turned changes down (Production without the schema they need): they wait on
    /// this device, are offered again on their own, and nothing is lost.
    case notAccepted(count: Int)
    /// Nothing syncs until the owner chooses what to do.
    case needsDecision(SyncDecision)
}

/// Why iCloud can't be used with this device's account: CloudKit's account status, in the
/// person's terms (docs/design/sync-icloud.md, "When iCloud isn't there").
enum ICloudAccountProblem: Equatable, Sendable {
    /// No iCloud account for Porchlight. CloudKit answers alike for a device signed out of
    /// iCloud and for iCloud turned off for Porchlight in Settings, so the words cover both.
    case signedOut
    /// Screen Time, or whoever manages the device, doesn't allow iCloud.
    case restricted
    /// The account is there but needs signing in again: a new password, or new terms.
    case needsSignIn
    /// iCloud couldn't say: offline, or a passing error. Checked again on the next change of
    /// network or account; nothing about the account is assumed meanwhile.
    case couldNotCheck

    /// The problem in CloudKit's answer, nil when the account is available. No answer at
    /// all (the check threw) is `couldNotCheck`.
    init?(_ status: CKAccountStatus?) {
        switch status {
        case .available?: return nil
        case .noAccount?: self = .signedOut
        case .restricted?: self = .restricted
        case .temporarilyUnavailable?: self = .needsSignIn
        case .couldNotDetermine?, nil: self = .couldNotCheck
        @unknown default: self = .couldNotCheck
        }
    }
}

extension SyncStatus {
    /// What keeps this device's account from iCloud for sure: everything but "couldn't
    /// check", which may well pass on its own.
    var accountBlocker: ICloudAccountProblem? {
        if case let .account(problem) = self, problem != .couldNotCheck { return problem }
        return nil
    }
}

/// Why sync waits for the owner.
enum SyncDecision: Equatable, Sendable {
    /// A different iCloud account signed in: the data here belongs to the earlier one.
    case accountChanged
    /// The database was replaced underneath the app (a restored backup), so sending it
    /// could put old data over newer data in iCloud (`DatabaseIdentity`).
    case restoredCopy
}

/// What the owner said about a restored copy of the database.
enum RestoredCopy: String, Sendable {
    /// Not yet: sync waits.
    case undecided
    /// Kept on this device without sync; turning sync on asks again.
    case keptWithoutSync
}

extension SyncStatus {
    /// Sync can't get its changes through and needs something from someone: a network,
    /// an account, room in iCloud or a decision. Off is a choice, and syncing is progress.
    var isStuck: Bool {
        switch self {
        case .waiting, .notChecked, .account, .iCloudFull, .notAccepted, .needsDecision: true
        case .off, .upToDate, .syncing: false
        }
    }
}

/// Why sync is off.
enum SyncOffReason: Equatable, Sendable {
    /// The device's sync switch is off.
    case switchedOff
    /// A DEBUG launch on sample data, which must never reach iCloud.
    case sampleData
    /// The build has no iCloud entitlement (simulator and CI builds are unsigned).
    case noEntitlement
    /// The sync engine could not be set up or started.
    case failed(String)
}

/// What this device remembers about sync. Each device has its own switch, so this lives
/// in UserDefaults, never in the synced database.
struct SyncPreferences {
    let defaults: UserDefaults

    private enum Key {
        static let enabled = "sync.enabled"
        static let lastSynced = "sync.lastSynced"
        static let accountName = "sync.accountName"
        static let needsDecision = "sync.needsDecision"
        static let restoredCopy = "sync.restoredCopy"
        static let databaseTokens = "sync.databaseTokens"
    }

    /// The sync switch; nil until it was first decided on this device.
    var isEnabled: Bool? {
        get { defaults.object(forKey: Key.enabled) as? Bool }
        nonmutating set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var lastSynced: Date? {
        get { defaults.object(forKey: Key.lastSynced) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastSynced) }
    }

    /// The iCloud account this device's data syncs with, once it has signed in.
    var accountName: String? {
        get { defaults.string(forKey: Key.accountName) }
        nonmutating set { defaults.set(newValue, forKey: Key.accountName) }
    }

    /// True from the moment a different account is noticed until the owner chooses.
    var needsDecision: Bool {
        get { defaults.bool(forKey: Key.needsDecision) }
        nonmutating set { defaults.set(newValue, forKey: Key.needsDecision) }
    }

    /// A restored copy of the database this device found, until the owner chose for good.
    var restoredCopy: RestoredCopy? {
        get { defaults.string(forKey: Key.restoredCopy).flatMap(RestoredCopy.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Key.restoredCopy) }
    }

    /// The tokens that name the database this install last ran with (`DatabaseIdentity`).
    var databaseTokens: [String] {
        get { defaults.stringArray(forKey: Key.databaseTokens) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.databaseTokens) }
    }
}

#if DEBUG
/// `-debugSyncStatus <name>` shows the sync section in one state, with no engine, for
/// screenshots and UI tests. `needsDecision` is a different account, `restoredCopy` a
/// restored backup. `lookingForHousehold` (with `-resetData`) holds the first-launch search
/// screen until "Start fresh instead". `noAccount`, `restricted`, `needsSignIn` and
/// `couldNotCheck` are the account's answers (`ICloudAccountProblem`).
enum SyncDebugStatus: String, CaseIterable, Sendable {
    case off, upToDate, syncing, waiting, noAccount, restricted, needsSignIn, couldNotCheck, iCloudFull, needsDecision, restoredCopy, lookingForHousehold

    /// The account problem this status shows, if it is one.
    var accountProblem: ICloudAccountProblem? {
        switch self {
        case .noAccount: .signedOut
        case .restricted: .restricted
        case .needsSignIn: .needsSignIn
        case .couldNotCheck: .couldNotCheck
        default: nil
        }
    }
}
#endif

extension SyncStatus {
    /// One short line under the phone's sync switch.
    func phoneSummary(device: String) -> String {
        switch self {
        case .off(.switchedOff): "Off. Everything stays on this \(device)."
        case .off: "Can't sync on this \(device) now."
        case .account(.signedOut): "iCloud is off for Porchlight."
        case .account(.restricted): "iCloud isn't allowed on this \(device)."
        case .account(.needsSignIn): "iCloud needs you to sign in again."
        case .account(.couldNotCheck): "On, checking with iCloud."
        case .upToDate, .syncing: "On."
        case .notChecked: "On, checking with iCloud."
        case .waiting: "On, waiting for iCloud."
        case .iCloudFull: "Paused: iCloud is full."
        case .notAccepted: "On, but iCloud isn't taking changes yet."
        case .needsDecision: "Waiting for your choice above."
        }
    }
}
