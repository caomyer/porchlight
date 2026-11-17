import CloudKit
import Foundation
import GRDB
import Observation
import SQLiteData
import SwiftData
import UIKit

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
        /// How often a shared screen in front asks iCloud for changes: the wall must feel
        /// live, and one request that finds nothing is a few hundred bytes (see "Staying
        /// current" in docs/design/sync-icloud.md).
        var sharedScreenPoll: Duration = .seconds(15)
        /// How often someone's own phone in front asks.
        var personalPoll: Duration = .seconds(30)
        /// The longest wait between checks while they keep failing.
        var pollBackoff: Duration = .seconds(5 * 60)
        /// Checks that find nothing move the last-synced time at most this often, so a
        /// quiet poll doesn't redraw what shows the status.
        var quietCheckRecord: TimeInterval = 5 * 60
        /// Checks failing this many times in a row show as waiting for iCloud.
        var failedChecks = 3
        /// The longest one check may take before it counts as failed.
        var checkTimeout: Duration = .seconds(60)
        /// "Up to date" only within this long of a check that iCloud answered; nil leaves the
        /// status alone (tests of other things, which never check).
        var checkFreshness: TimeInterval? = 3 * 60
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
    /// Asks iCloud for changes while the app is in front; nil without an engine.
    @ObservationIgnored private(set) var poller: SyncPoller?
    /// Fetches the poller is running, which never show as syncing.
    @ObservationIgnored private var quietFetches = 0
    /// Checks keep failing (`Timing.failedChecks`), so sync says it is waiting.
    private var checksFailing = false
    /// iCloud answered a check within `Timing.checkFreshness`.
    private var checkedRecently = false
    @ObservationIgnored private var freshnessTask: Task<Void, Never>?
    /// What sync is doing, for "Sync details" and the sync log.
    @ObservationIgnored let trace = SyncTrace()
    @ObservationIgnored private let role: @MainActor () -> DeviceRole
    /// Whether it follows the app coming to the front and leaving it; tests drive that
    /// themselves (`appActivityChanged`), since the test host is always in front.
    @ObservationIgnored private let followsApplication: Bool
    @ObservationIgnored private var lifecycle: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - hasHousehold: Whether this device already has a household, which decides the
    ///     switch the first time: on for a new install, off on a wall that already has data,
    ///     so its first upload is a deliberate act.
    ///   - removeFiles: Removes the household's files when the owner removes its data.
    ///   - role: How this device is used, read before each check: a shared screen checks
    ///     more often than a phone.
    init(
        _ setup: Setup, preferences: SyncPreferences, hasHousehold: Bool, timing: Timing = Timing(),
        role: @escaping @MainActor () -> DeviceRole = SyncController.storedRole,
        followsApplication: Bool = true,
        removeFiles: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.removeFiles = removeFiles
        self.timing = timing
        self.role = role
        self.followsApplication = followsApplication
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
        trace.role = role()
        #if DEBUG
        if let debugStatus {
            show(debugStatus)
            watchStatus()
            return
        }
        // `-debugSyncPoll`: the checks run on their real schedule against a stand-in for
        // iCloud, so a UI test can watch them tick on an untouched screen.
        if engine == nil, ProcessInfo.processInfo.arguments.contains("-debugSyncPoll") {
            trace.engineRunning = true
            poller = makePoller { .checked }
            followLifecycle()
            return
        }
        #endif
        guard engine != nil else {
            trace.note("sync unavailable: \(unavailable.map { "\($0)" } ?? "unknown")")
            return
        }
        trace.note("launch: role \(role().rawValue), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion), switch \(isEnabled ? "on" : "off")")
        // CloudKit registers for pushes itself once an engine exists; asking again is
        // harmless (UIKit hands back the same token) and makes the app delegate hear whether
        // a token arrived, which is the first thing to know when pushes don't come.
        UIApplication.shared.registerForRemoteNotifications()
        poller = makePoller { [weak self] in try await self?.quietFetch() ?? .skipped }
        listenForChanges()
        watchActivity()
        watchStatus()
        followLifecycle()
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
        let controller = SyncController(
            setup,
            preferences: SyncPreferences(defaults: .standard),
            hasHousehold: hasHousehold,
            removeFiles: AppFiles.removeHouseholdFiles
        )
        current = controller
        return controller
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
        if !isOnline || checksFailing { return .waiting(lastSynced: lastSynced) }
        if timing.checkFreshness != nil, poller != nil, !checkedRecently { return .notChecked(lastSynced: lastSynced) }
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

    /// The controller of this launch, for work done with the app in the background (a
    /// widget's button, Siri), which has no view to find it through.
    static var launched: SyncController?

    /// Sends pending changes now and waits for that, at most `timeout`: a widget or Siri
    /// log may be all a background launch does, and iOS can suspend the app soon after, so
    /// it doesn't wait for the engine's own schedule (docs/design/beyond-the-app.md). When
    /// sync is off, waiting for a decision, signed out or offline, it returns at once or at
    /// the timeout, and the change stays pending for the next time sync runs.
    func sendSoon(timeout: Duration = .seconds(10)) async {
        guard let engine else { return }
        await settle()
        guard engine.isRunning else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await engine.sendChanges() }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

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
        let account = status.map { $0 == .available ? "available" : "not available (\($0.rawValue))" } ?? "couldn't check"
        if trace.account != account {
            trace.account = account
            trace.note("iCloud account \(account)")
        }
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
            trace.engineRunning = true
            trace.note("engine started")
            // Sync was just turned on, or the app launched: look for changes now. The app's
            // state is read directly too, in case the notification that it came to the
            // front went by before anything listened.
            followApplicationState(source: "state after start")
            poller?.checkNow(.turnedOn)
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
        if isOnline != self.isOnline { trace.note(isOnline ? "online" : "offline") }
        self.isOnline = isOnline
        trace.isOnline = isOnline
        poller?.setOnline(isOnline)
    }

    /// Records the end of a round of syncing as the last-synced time, when it ended online.
    func activityChanged(isSynchronizing active: Bool, at date: Date = .now) {
        if isSynchronizing, !active, isOnline {
            lastSynced = date
            preferences.lastSynced = date
            // A round the engine ran by itself talked to iCloud too.
            markChecked()
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

    /// Follows the engine's sending and fetching. The poller's own fetches never count, so
    /// a check every few seconds doesn't flicker "Syncing" or redraw the status.
    private func watchActivity() {
        guard let engine else { return }
        let (sending, fetching) = withObservationTracking {
            (engine.isSendingChanges, engine.isFetchingChanges)
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchActivity() }
        }
        let active = sending || (fetching && quietFetches == 0)
        if active != isSynchronizing { activityChanged(isSynchronizing: active) }
    }

    // MARK: Staying current

    /// How this device is used, as `DeviceSettings` keeps it.
    static func storedRole() -> DeviceRole {
        UserDefaults.standard.string(forKey: DeviceSettings.roleKey).flatMap(DeviceRole.init(rawValue:))
            ?? .standard(for: UIDevice.current.userInterfaceIdiom)
    }

    private func makePoller(fetch: @escaping @MainActor @Sendable () async throws -> SyncPoller.Outcome) -> SyncPoller {
        let timing = timing, role = role
        return SyncPoller(
            policy: .init(
                interval: { role() == .sharedScreen ? timing.sharedScreenPoll : timing.personalPoll },
                maxBackoff: timing.pollBackoff,
                timeout: timing.checkTimeout
            ),
            fetch: fetch,
            onOutcome: { [weak self] outcome, failures, error, trigger in
                self?.checked(outcome, failures: failures, error: error, trigger: trigger)
            },
            onWait: { [weak self] delay in
                self?.trace.nextCheckAt = Date.now.addingTimeInterval(TimeInterval(delay.components.seconds))
            }
        )
    }

    /// Checks while the app is in front, and sends what is pending when it leaves, inside
    /// a background task, so a log made just before locking the phone still goes up.
    private func followLifecycle() {
        guard followsApplication else { return }
        let center = NotificationCenter.default
        lifecycle = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appActivityChanged(isActive: true, source: "became active") }
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appActivityChanged(isActive: false, source: "resigned active") }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sendBeforeSuspending() }
            },
        ]
        // Not only from notifications: the app may already be in front by now.
        followApplicationState(source: "state at launch")
        Task { @MainActor [weak self] in self?.followApplicationState(source: "state after launch") }
    }

    /// Reads whether the app is in front from the app itself.
    private func followApplicationState(source: String) {
        guard poller != nil, followsApplication else { return }
        appActivityChanged(isActive: UIApplication.shared.applicationState == .active, source: source)
    }

    struct Counts: Equatable, Sendable {
        /// Rows iCloud has no record of yet.
        var unconfirmed: Int
        /// Changes the engine queued while it was stopped.
        var queued: Int
    }

    func counts() async -> Counts? {
        guard let writer else { return nil }
        return try? await writer.read { db in
            Counts(
                unconfirmed: try SyncUnsent.count(db),
                queued: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlitedata_icloud_pendingRecordZoneChanges") ?? 0
            )
        }
    }

    /// This launch's controller, for the app delegate's push callbacks.
    static var current: SyncController?

    func pushToken(arrived: Bool, detail: String) {
        trace.pushToken = arrived ? "arrived (\(detail))" : "failed: \(detail)"
        readPushState()
        trace.note("push token \(trace.pushToken)")
    }

    /// A push came: noted, then one check of our own. True when iCloud answered it.
    func pushArrived(_ kind: PushKind) async -> Bool {
        trace.pushes += 1
        trace.lastPush = .now
        trace.note("push arrived: \(kind)")
        guard kind.isCloudKit, poller != nil else { return false }
        await checkNow(.push)
        return trace.lastCheck?.outcome == "answered"
    }

    /// "Check now" in Sync details, and a push: one check at once, also in the background.
    func checkNow(_ trigger: SyncPoller.Trigger) async {
        guard let poller else { return }
        trace.note("check asked for: \(trigger.rawValue)")
        await poller.checkOnce(trigger)
    }

    /// The system's push state, read for "Sync details" and the log.
    func readPushState() {
        let application = UIApplication.shared
        trace.registeredForPushes = application.isRegisteredForRemoteNotifications
        trace.backgroundRefresh = switch application.backgroundRefreshStatus {
        case .available: "on"
        case .denied: "off"
        case .restricted: "restricted"
        @unknown default: "unknown"
        }
        trace.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func appActivityChanged(isActive: Bool, source: String = "test") {
        guard let poller, poller.isActive != isActive else { return }
        trace.isActive = isActive
        trace.activitySource = source
        trace.role = role()
        readPushState()
        trace.note("\(isActive ? "active" : "inactive") (\(source)), role \(role().rawValue), pushes \(trace.registeredForPushes ? "registered" : "not registered"), background refresh \(trace.backgroundRefresh), low power \(trace.lowPowerMode ? "on" : "off")")
        if !isActive { trace.nextCheckAt = nil }
        poller.setActive(isActive)
    }

    /// One check, as the poller's. When asking for everything fails, it asks for the
    /// household's own zone alone: SQLiteData fetches the private and shared databases
    /// together and one failing cancels the other, and an owner's shared database (or a
    /// member's private one) holds nothing of the household, so it must never stand in the
    /// way (docs/design/sync-icloud.md, "Seeing what sync does").
    private func quietFetch() async throws -> SyncPoller.Outcome {
        guard let engine else { return .skipped }
        guard engine.isRunning, isEnabled, decision == nil else {
            let reason = !isEnabled ? "switch off" : decision != nil ? "waiting for a decision" : "engine not running"
            if trace.lastError != "skipped: \(reason)" {
                trace.lastError = "skipped: \(reason)"
                trace.note("check skipped: \(reason)")
            }
            return .skipped
        }
        quietFetches += 1
        defer { quietFetches -= 1 }
        do {
            try await engine.fetchChanges()
            return .checked
        } catch {
            if Task.isCancelled { throw error }
            let everything = error.syncDescription
            guard let zone = await householdZone() else {
                trace.note("check failed: everything \(everything); no household zone known")
                throw error
            }
            do {
                try await engine.fetchChanges(CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([zone])))
                trace.note("check: everything failed (\(everything)), the household's zone answered")
                trace.lastError = "everything: \(everything); household zone fine"
                return .checked
            } catch {
                trace.note("check failed: everything \(everything); household zone \(error.syncDescription)")
                throw error
            }
        }
    }

    /// The zone the household's row lives in, as the engine knows it.
    private func householdZone() async -> CKRecordZone.ID? {
        guard let writer else { return nil }
        let names = try? await writer.read { db -> [String]? in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT zoneName, ownerName FROM sqlitedata_icloud_metadata WHERE recordType = 'household' LIMIT 1
                """), let zone = row["zoneName"] as String?, let owner = row["ownerName"] as String? else { return nil }
            return [zone, owner]
        }
        guard let names = names ?? nil, let zone = names.first, let owner = names.last else { return nil }
        return CKRecordZone.ID(zoneName: zone, ownerName: owner)
    }

    /// After each check: a success is the last-synced time (at most every
    /// `Timing.quietCheckRecord` when nothing else happened) and keeps "Up to date" true,
    /// and checks that keep failing say so.
    func checked(_ outcome: SyncPoller.Outcome, failures: Int, error: (any Error)? = nil, trigger: SyncPoller.Trigger = .timer, at date: Date = .now) {
        trace.checks += 1
        trace.lastTrigger = trigger.rawValue
        trace.failuresInRow = failures
        switch outcome {
        case .checked:
            trace.lastCheck = .init(at: date, outcome: "answered", milliseconds: 0)
            if trace.lastError?.hasPrefix("everything:") != true { trace.lastError = nil }
            if checksFailing { checksFailing = false }
            if lastSynced.map({ date.timeIntervalSince($0) >= timing.quietCheckRecord }) ?? true {
                lastSynced = date
                preferences.lastSynced = date
            }
            markChecked(at: date)
            // Every check, but tersely: the log shows the checks keep coming.
            trace.note("check answered (\(trigger.rawValue), \(trace.checks) so far)")
        case .failed:
            let text = error?.syncDescription ?? "unknown"
            trace.lastCheck = .init(at: date, outcome: "failed", milliseconds: 0)
            trace.lastError = text
            trace.note("check failed (\(trigger.rawValue), \(failures) in a row): \(text)")
            if failures >= timing.failedChecks && !checksFailing { checksFailing = true }
        case .skipped:
            trace.lastCheck = .init(at: date, outcome: "skipped", milliseconds: 0)
        }
    }

    /// iCloud answered: "Up to date" holds for `Timing.checkFreshness`.
    private func markChecked(at date: Date = .now) {
        if !checkedRecently { checkedRecently = true }
        freshnessTask?.cancel()
        guard let freshness = timing.checkFreshness else { return }
        freshnessTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(freshness))
            guard !Task.isCancelled, let self else { return }
            self.checkedRecently = false
            self.trace.note("no check answered for \(Int(freshness))s")
        }
    }

    /// Sends whatever is pending as the app leaves the front, with background time asked
    /// for, so iOS doesn't suspend it mid-send. With nothing pending it returns at once.
    private func sendBeforeSuspending() {
        guard let engine, engine.isRunning else { return }
        trace.note("sending before suspending")
        let application = UIApplication.shared
        let task = BackgroundTaskID()
        task.id = application.beginBackgroundTask(withName: "Porchlight sync") {
            application.endBackgroundTask(task.id)
            task.id = .invalid
        }
        Task {
            try? await engine.sendChanges()
            if task.id != .invalid {
                application.endBackgroundTask(task.id)
                task.id = .invalid
            }
        }
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

/// A background task's id, kept by reference so its expiry and the send can both end it.
@MainActor
private final class BackgroundTaskID {
    var id: UIBackgroundTaskIdentifier = .invalid
}
