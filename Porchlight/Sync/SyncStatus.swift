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
    /// A different iCloud account signed in; nothing syncs until the owner chooses.
    case needsDecision
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
}
