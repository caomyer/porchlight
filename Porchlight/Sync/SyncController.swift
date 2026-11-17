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
    nonisolated static let containerIdentifier = "iCloud.com.mingyucao.porchlight"

    enum Setup {
        /// Sync this database, on this device.
        case sync(any DatabaseWriter, device: any SyncDevice)
        /// Sync can't run in this launch or build.
        case unavailable(SyncOffReason)
        #if DEBUG
        /// No engine, showing a fixed status: `-debugSyncStatus`, for screenshots and UI tests.
        case debug(SyncDebugStatus)
        #endif
    }

    /// How long things take; tests make them short.
    struct Timing {
        /// The most a launch with no household waits for one to arrive from iCloud.
        var householdSearch: Duration = .seconds(30)
        /// How long sync is stuck before the gear on the rail shows a dot.
        var attention: Duration = .seconds(60 * 60)
        /// How long after the engine goes quiet it looks for rows iCloud never took.
        var unsentCheck: Duration = .seconds(30)
        /// How often rows iCloud turned down are offered to it again.
        var resend: Duration = .seconds(10 * 60)
    }

    private(set) var isEnabled: Bool
    /// A different account signed in, until the owner chooses.
    private var accountDecision: Bool
    /// A restored copy of the database, until the owner chooses (`DatabaseIdentity`).
    private var restoredCopy: RestoredCopy?
    private(set) var lastSynced: Date?
    /// The iCloud user's record name, once read: this device's row carries it, so the
    /// household can match the device to a participant of its share.
    private(set) var userName: String?
    private var unavailable: SyncOffReason?
    private var startFailure: String?
    /// Nil until the account has been checked.
    private var hasAccount: Bool?
    private var isOnline = true
    private var isFull = false
    private var isSynchronizing = false
    /// True while a launch with no household looks for one in iCloud before onboarding
    /// (docs/design/sync-icloud.md, "A fresh install looks for a household first").
    private(set) var isLookingForHousehold = false
    /// Sync has been stuck (see `SyncStatus.isStuck`) for `Timing.attention`, so the gear on
    /// the wall's rail shows a dot (journey D3). Nothing about sync shows on Today itself.
    private(set) var needsAttention = false

    /// Nil when sync can't run in this launch or build.
    @ObservationIgnored let engine: SyncEngine?
    /// The database the engine syncs, to find rows iCloud never took.
    @ObservationIgnored private let writer: (any DatabaseWriter)?
    /// Rows iCloud turned down and that wait here to be sent again (`SyncUnsent`).
    private(set) var unsentCount = 0
    @ObservationIgnored private var unsentTask: Task<Void, Never>?
    @ObservationIgnored private let device: (any SyncDevice)?
    @ObservationIgnored private let preferences: SyncPreferences
    @ObservationIgnored private let removeFiles: () -> Void
    @ObservationIgnored private let events = SyncEvents()
    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var searchTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var stuckSince: Date?
    @ObservationIgnored private var attentionTask: Task<Void, Never>?

    /// - Parameters:
    ///   - hasHousehold: Whether this device already has a household, which decides the
    ///     switch the first time: on for a new install, off on a wall that already has data,
    ///     so its first upload is a deliberate act.
    ///   - removeFiles: Removes the household's files when the owner removes its data.
    init(
        _ setup: Setup, preferences: SyncPreferences, hasHousehold: Bool, timing: Timing = Timing(),
        removeFiles: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.removeFiles = removeFiles
        self.timing = timing
        #if DEBUG
        var debugStatus: SyncDebugStatus?
        #endif
        switch setup {
        case let .sync(database, device):
            if preferences.isEnabled == nil {
                preferences.isEnabled = !hasHousehold
            }
            writer = database
            do {
                engine = try SyncMirror.engine(for: database, delegate: events)
            } catch {
                engine = nil
                unavailable = .failed(error.localizedDescription)
            }
            self.device = device
        case let .unavailable(reason):
            engine = nil
            writer = nil
            device = nil
            unavailable = reason
        #if DEBUG
        case let .debug(status):
            engine = nil
            writer = nil
            device = nil
            debugStatus = status
        #endif
        }
        isEnabled = preferences.isEnabled ?? false
        accountDecision = preferences.needsDecision
        restoredCopy = preferences.restoredCopy
        lastSynced = preferences.lastSynced
        userName = preferences.accountName
        events.controller = self
        #if DEBUG
        if let debugStatus {
            show(debugStatus)
            watchStatus()
            return
        }
        #endif
        guard engine != nil else { return }
        listenForChanges()
        watchActivity()
        watchStatus()
        refresh()
        if !hasHousehold && isEnabled && decision == nil {
            lookForHousehold()
        }
    }

    /// The controller for this launch. Sample data never syncs, and a build without the
    /// iCloud entitlement can't (creating a `CKContainer` would trap), so neither gets an engine.
    static func live(database: AppDatabase) -> SyncController {
        #if DEBUG
        // Only on sample data, which never syncs: on real data a launch without the engine
        // would leave its writes unrecorded.
        if AppFiles.isSandboxed, let name = UserDefaults.standard.string(forKey: "debugSyncStatus") {
            guard let status = SyncDebugStatus(rawValue: name) else {
                fatalError("-debugSyncStatus \(name) is not one of \(SyncDebugStatus.allCases.map(\.rawValue))")
            }
            // Its own throwaway preferences: a debug launch never changes the device's sync switch.
            let defaults = UserDefaults(suiteName: "Porchlight.debugSync")!
            defaults.removePersistentDomain(forName: "Porchlight.debugSync")
            return SyncController(.debug(status), preferences: SyncPreferences(defaults: defaults), hasHousehold: true, removeFiles: {})
        }
        #endif
        let setup: Setup
        if AppFiles.isSandboxed {
            setup = .unavailable(.sampleData)
        } else if !isSignedForICloud {
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
    static var isSignedForICloud: Bool {
        ModelConfiguration(groupContainer: .automatic).cloudKitContainerIdentifier == containerIdentifier
    }

    /// What the owner has to decide before anything syncs. A restored copy comes first: it
    /// is the one that could send old data over newer data.
    var decision: SyncDecision? {
        if restoredCopy == .undecided { return .restoredCopy }
        if accountDecision { return .accountChanged }
        return nil
    }

    var status: SyncStatus {
        if let unavailable { return .off(unavailable) }
        if let decision { return .needsDecision(decision) }
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
        if unsentCount > 0 { return .notAccepted(count: unsentCount) }
        return .upToDate(lastSynced: lastSynced)
    }

    /// Whether the switch can do anything in this launch.
    var isAvailable: Bool { unavailable == nil }

    // MARK: Owner actions

    func setEnabled(_ isOn: Bool) {
        // A restored copy kept without sync is asked about again before it could send.
        if isOn && restoredCopy == .keptWithoutSync {
            setRestoredCopy(.undecided)
        }
        preferences.isEnabled = isOn
        isEnabled = isOn
        refresh()
    }

    /// Keeps the earlier account's household on this device, without sync. Turning sync
    /// back on asks again while the different account is signed in.
    func keepDataWithoutSync() {
        preferences.needsDecision = false
        accountDecision = false
        setEnabled(false)
    }

    /// Keeps a restored copy on this device, without sync. Turning sync back on asks again,
    /// since the copy may still be older than iCloud.
    func keepRestoredCopyWithoutSync() {
        setRestoredCopy(.keptWithoutSync)
        setEnabled(false)
    }

    /// Drops this device's restored copy and brings the household back from iCloud. The
    /// copy is never sent: the household in iCloud is everyone's latest.
    func useCopyInICloud() async {
        guard await clearLocalData() else { return }
        setRestoredCopy(nil)
        setEnabled(true)
        lookForHousehold()
    }

    private func setRestoredCopy(_ value: RestoredCopy?) {
        preferences.restoredCopy = value
        restoredCopy = value
    }

    /// Removes the earlier account's household from this device, then syncs with the
    /// account signed in now.
    func removeDataFromDevice() async {
        guard await clearLocalData() else { return }
        preferences.accountName = nil
        userName = nil
        preferences.lastSynced = nil
        lastSynced = nil
        preferences.needsDecision = false
        accountDecision = false
        setEnabled(true)
    }

    /// Clears every synced table and the engine's metadata, and the household's files.
    private func clearLocalData() async -> Bool {
        guard let engine else { return false }
        refreshTask?.cancel()
        do {
            try await engine.deleteLocalData()
        } catch {
            startFailure = error.localizedDescription
            return false
        }
        removeFiles()
        return true
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
        guard isEnabled, decision == nil else {
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
            userName = name
        }
        do {
            try await engine.start()
            startFailure = nil
            // Rows iCloud turned down in an earlier launch go again: SQLiteData only queues
            // them by itself when the account signs in.
            await resendUnsent()
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
        accountDecision = true
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
        if isSynchronizing, !active {
            checkUnsentSoon()
        }
        isSynchronizing = active
    }

    // MARK: Changes iCloud turned down

    /// Looks for rows iCloud never took once the engine has been quiet a while, so rows
    /// that are only waiting their turn in a long upload aren't counted.
    private func checkUnsentSoon() {
        guard writer != nil else { return }
        unsentTask?.cancel()
        let delay = timing.unsentCheck
        unsentTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.checkUnsent()
        }
    }

    /// Counts the rows iCloud turned down. While there are any, sync says so (a stuck
    /// state: the data is safe here) and offers them again every `Timing.resend`, so once
    /// iCloud accepts them (the schema was deployed) sync is up to date by itself.
    func checkUnsent() async {
        guard let writer, let engine, engine.isRunning, !isSynchronizing else { return }
        let count = (try? await writer.read(SyncUnsent.count)) ?? 0
        unsentCount = count
        guard count > 0 else { return }
        unsentTask?.cancel()
        let delay = timing.resend
        unsentTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.resendUnsent()
        }
    }

    /// Offers every row iCloud never took to it again, and sends.
    func resendUnsent() async {
        guard let writer, let engine, engine.isRunning else { return }
        guard (try? await writer.read(SyncUnsent.count)) ?? 0 > 0 else {
            unsentCount = 0
            return
        }
        try? await writer.write(SyncUnsent.requeue)
        try? await engine.sendChanges()
        await checkUnsent()
    }

    // MARK: Looking for a household

    /// Starts the engine and waits for its first fetch, at most `Timing.householdSearch`, so
    /// a new or wiped device signed in to an account that has a household opens it instead
    /// of walking through setup. A household that arrives ends it early by itself: the root
    /// view opens any household that appears.
    private func lookForHousehold() {
        isLookingForHousehold = true
        let timeout = timing.householdSearch
        searchTasks = [
            Task { [weak self] in
                await self?.fetchFirstChanges()
                self?.stopLookingForHousehold()
            },
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.stopLookingForHousehold()
            },
        ]
    }

    private func fetchFirstChanges() async {
        await settle()
        guard let engine, engine.isRunning else { return }
        try? await engine.fetchChanges()
    }

    /// Ends the search: it found nothing in time, or the owner chose to start fresh. Sync
    /// keeps running, so a household that arrives later still opens.
    func stopLookingForHousehold() {
        for task in searchTasks { task.cancel() }
        searchTasks = []
        isLookingForHousehold = false
    }

    #if DEBUG
    /// Sets the state behind a `-debugSyncStatus` status. A stuck one shows the dot at once.
    private func show(_ debug: SyncDebugStatus) {
        isEnabled = debug != .off
        hasAccount = debug != .noAccount
        switch debug {
        case .off, .upToDate, .noAccount: break
        case .syncing: isSynchronizing = true
        case .waiting: isOnline = false
        case .iCloudFull: isFull = true
        case .needsDecision: accountDecision = true
        case .restoredCopy: restoredCopy = .undecided
        case .lookingForHousehold: isLookingForHousehold = true
        }
        if debug == .upToDate || debug == .waiting {
            lastSynced = Date.now.addingTimeInterval(-25 * 60)
        }
        needsAttention = status.isStuck
    }
    #endif

    // MARK: Being stuck

    /// Follows the status, so the dot appears once it has been stuck long enough.
    private func watchStatus() {
        let status = withObservationTracking {
            self.status
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchStatus() }
        }
        statusChanged(to: status)
    }

    /// Starts the clock when sync becomes stuck and stops it when it isn't. Going from one
    /// stuck state to another (offline, then signed out) keeps the clock running.
    func statusChanged(to status: SyncStatus, at date: Date = .now) {
        guard status.isStuck else {
            stuckSince = nil
            attentionTask?.cancel()
            needsAttention = false
            return
        }
        guard stuckSince == nil else { return }
        stuckSince = date
        let delay = timing.attention
        attentionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.needsAttention = true
        }
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
        // The household lives in its owner's iCloud: the private database on the owner's
        // devices, the shared one on everyone else's. Either full pauses this device's sync.
        Task { await self.forward(quotaExceeded: quotaExceeded) }
    }

    private func forward(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        controller?.accountChanged(change)
    }

    private func forward(quotaExceeded: Bool) {
        controller?.quotaChanged(isExceeded: quotaExceeded)
    }
}
