import Foundation

/// What the UI can say about sync (docs/design/sync-icloud.md, "Status the UI can show").
enum SyncStatus: Equatable, Sendable {
    case off(SyncOffReason)
    case noAccount
    case upToDate(lastSynced: Date?)
    case syncing
    /// Offline, or still checking the account; changes keep saving on the device meanwhile.
    case waiting(lastSynced: Date?)
    case iCloudFull
    /// Nothing syncs until the owner chooses what to do.
    case needsDecision(SyncDecision)
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
        case .waiting, .noAccount, .iCloudFull, .needsDecision: true
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
/// screen until "Start fresh instead".
enum SyncDebugStatus: String, CaseIterable, Sendable {
    case off, upToDate, syncing, waiting, noAccount, iCloudFull, needsDecision, restoredCopy, lookingForHousehold
}
#endif
