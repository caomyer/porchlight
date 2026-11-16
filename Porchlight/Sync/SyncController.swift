import CloudKit
import Foundation
import Observation
import SQLiteData
import SwiftData

/// Owns the sync engine: starts it when the device's switch is on and iCloud is there,
/// stops it otherwise, and publishes a small `SyncStatus` for Settings.
///
/// The wall must never lose data or stop working because of sync, so nothing here
/// erases the household on its own: signing out only pauses sync, and a different
/// account waits for the owner to choose (docs/design/sync-icloud.md, "Account changes").
@MainActor
@Observable
final class SyncController {
    nonisolated static let containerIdentifier = "iCloud.com.porchlight.porchlight"

    enum Setup {
        /// Sync this database, on this device.
        case sync(any DatabaseWriter, device: any SyncDevice)
        /// Sync can't run in this launch or build.
        case unavailable(SyncOffReason)
    }

    private(set) var isEnabled: Bool
    private(set) var needsDecision: Bool
    private(set) var lastSynced: Date?
    private var unavailable: SyncOffReason?
    private var startFailure: String?
    /// Nil until the account has been checked.
    private var hasAccount: Bool?
    private var isOnline = true
    private var isFull = false
    private var isSynchronizing = false

    /// Nil when sync can't run in this launch or build.
    @ObservationIgnored let engine: SyncEngine?
    @ObservationIgnored private let device: (any SyncDevice)?
    @ObservationIgnored private let preferences: SyncPreferences
    @ObservationIgnored private let removeFiles: () -> Void
    @ObservationIgnored private let events = SyncEvents()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?

    /// - Parameters:
    ///   - hasHousehold: Whether this device already has a household, which decides the
    ///     switch the first time: on for a new install, off on a wall that already has data,
    ///     so its first upload is a deliberate act.
    ///   - removeFiles: Removes the household's files when the owner removes its data.
    init(_ setup: Setup, preferences: SyncPreferences, hasHousehold: Bool, removeFiles: @escaping () -> Void) {
        self.preferences = preferences
        self.removeFiles = removeFiles
        switch setup {
        case let .sync(database, device):
            if preferences.isEnabled == nil {
                preferences.isEnabled = !hasHousehold
            }
            do {
                engine = try SyncMirror.engine(for: database, delegate: events)
            } catch {
                engine = nil
                unavailable = .failed(error.localizedDescription)
            }
            self.device = device
        case let .unavailable(reason):
            engine = nil
            device = nil
            unavailable = reason
        }
        isEnabled = preferences.isEnabled ?? false
        needsDecision = preferences.needsDecision
        lastSynced = preferences.lastSynced
        events.controller = self
        guard engine != nil else { return }
        listenForChanges()
        watchActivity()
        refresh()
    }

    /// The controller for this launch. Sample data never syncs, and a build without the
    /// iCloud entitlement can't (creating a `CKContainer` would trap), so neither gets an engine.
    static func live(database: AppDatabase) -> SyncController {
        let setup: Setup
        if AppFiles.isSandboxed {
            setup = .unavailable(.sampleData)
        } else if !hasEntitlement {
            setup = .unavailable(.noEntitlement)
        } else {
            setup = .sync(database.writer, device: LiveSyncDevice(container: CKContainer(identifier: containerIdentifier)))
        }
        let hasHousehold = (try? database.snapshot().household) != nil
        return SyncController(
            setup,
            preferences: SyncPreferences(defaults: .standard),
            hasHousehold: hasHousehold,
            removeFiles: AppFiles.removeHouseholdFiles
        )
    }

    /// Whether this build is signed with the household's iCloud container. SwiftData reads
    /// the entitlement without touching CloudKit, so this is safe in any build.
    private static var hasEntitlement: Bool {
        ModelConfiguration(groupContainer: .automatic).cloudKitContainerIdentifier == containerIdentifier
    }

    var status: SyncStatus {
        if let unavailable { return .off(unavailable) }
        if needsDecision { return .needsDecision }
        if !isEnabled { return .off(.switchedOff) }
        if let startFailure { return .off(.failed(startFailure)) }
        switch hasAccount {
        case nil: return .waiting(lastSynced: lastSynced)
        case false?: return .noAccount
        case true?: break
        }
        if isFull { return .iCloudFull }
        if isSynchronizing { return .syncing }
        if !isOnline { return .waiting(lastSynced: lastSynced) }
        return .upToDate(lastSynced: lastSynced)
    }

    /// Whether the switch can do anything in this launch.
    var isAvailable: Bool { unavailable == nil }

    // MARK: Owner actions

    func setEnabled(_ isOn: Bool) {
        preferences.isEnabled = isOn
        isEnabled = isOn
        refresh()
    }

    /// Keeps the earlier account's household on this device, without sync. Turning sync
    /// back on asks again while the different account is signed in.
    func keepDataWithoutSync() {
        preferences.needsDecision = false
        needsDecision = false
        setEnabled(false)
    }

    /// Removes the earlier account's household from this device, then syncs with the
    /// account signed in now.
    func removeDataFromDevice() async {
        guard let engine else { return }
        refreshTask?.cancel()
        do {
            try await engine.deleteLocalData()
        } catch {
            startFailure = error.localizedDescription
            return
        }
        removeFiles()
        preferences.accountName = nil
        preferences.lastSynced = nil
        lastSynced = nil
        preferences.needsDecision = false
        needsDecision = false
        setEnabled(true)
    }

    // MARK: Engine and device events

    /// Brings the engine in line with the switch, the account and any pending decision.
    /// Later calls replace earlier ones, so the last change always wins.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await reconcile() }
    }

    /// Waits until the latest `refresh()` has finished, including any that started while
    /// waiting (an account change can arrive meanwhile and replace it).
    func settle() async {
        while let task = refreshTask {
            await task.value
            if task == refreshTask { return }
        }
    }

    private func reconcile() async {
        guard let engine, let device else { return }
        guard isEnabled, !needsDecision else {
            engine.stop()
            return
        }
        let status = try? await device.accountStatus()
        guard !Task.isCancelled else { return }
        hasAccount = status == .available
        guard status == .available else {
            engine.stop()
            return
        }
        // Offline the name can't be read; the engine still reports a switch itself.
        if let name = try? await device.accountName() {
            guard !Task.isCancelled else { return }
            if let known = preferences.accountName, known != name {
                accountSwitched()
                return
            }
            preferences.accountName = name
        }
        do {
            try await engine.start()
            startFailure = nil
        } catch {
            startFailure = error.localizedDescription
        }
    }

    func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        switch change {
        case .signIn:
            refresh()
        case .signOut:
            // The data stays and the wall keeps working; signing back in resumes.
            refreshTask?.cancel()
            engine?.stop()
            hasAccount = false
        case .switchAccounts:
            accountSwitched()
        @unknown default:
            refresh()
        }
    }

    private func accountSwitched() {
        refreshTask?.cancel()
        engine?.stop()
        preferences.needsDecision = true
        needsDecision = true
    }

    func quotaChanged(isExceeded: Bool) {
        isFull = isExceeded
    }

    func networkChanged(isOnline: Bool) {
        self.isOnline = isOnline
    }

    /// Records the end of a round of syncing as the last-synced time, when it ended online.
    func activityChanged(isSynchronizing active: Bool, at date: Date = .now) {
        if isSynchronizing, !active, isOnline {
            lastSynced = date
            preferences.lastSynced = date
        }
        isSynchronizing = active
    }

    private func listenForChanges() {
        guard let changes = device?.changes() else { return }
        changesTask = Task { [weak self] in
            for await change in changes {
                guard let self else { return }
                switch change {
                case .account: refresh()
                case let .network(isOnline): networkChanged(isOnline: isOnline)
                }
            }
        }
    }

    private func watchActivity() {
        guard let engine else { return }
        let active = withObservationTracking {
            engine.isSynchronizing
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchActivity() }
        }
        activityChanged(isSynchronizing: active)
    }
}

/// Hands the engine's events to the controller, so the engine never keeps it alive.
@MainActor
private final class SyncEvents: SyncEngineDelegate {
    weak var controller: SyncController?

    nonisolated func syncEngine(
        _ syncEngine: SyncEngine,
        accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
    ) async {
        await forward(changeType)
    }

    nonisolated func syncEngine(_ syncEngine: SyncEngine, quotaExceeded: Bool, scope: CKDatabase.Scope) {
        // Only the household's own iCloud matters to this device; shared scopes come with M2.
        guard scope == .private else { return }
        Task { await self.forward(quotaExceeded: quotaExceeded) }
    }

    private func forward(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        controller?.accountChanged(change)
    }

    private func forward(quotaExceeded: Bool) {
        controller?.quotaChanged(isExceeded: quotaExceeded)
    }
}
