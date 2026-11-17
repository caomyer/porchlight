import CloudKit
import Network

/// What sync needs to know about the device: its iCloud account and its network.
///
/// `SyncController` only talks to the device through this, so tests can sign in, sign out,
/// switch accounts and go offline without iCloud.
protocol SyncDevice: Sendable {
    func accountStatus() async throws -> CKAccountStatus
    /// A stable name for the signed-in iCloud account, so a different account is noticed
    /// before anything is uploaded to it.
    func accountName() async throws -> String
    /// Tells when the account may have changed, and when the network comes or goes.
    func changes() -> AsyncStream<SyncDeviceChange>
    /// Asks iCloud, on its own and apart from the sync engine, which zones changed in each
    /// database since the last time it asked; nil where it can't ask.
    func probeChanges() async -> SyncProbe?
}

extension SyncDevice {
    func probeChanges() async -> SyncProbe? { nil }
}

/// What iCloud says changed since the last probe, database by database, so a failure in
/// one never hides the other (docs/design/sync-icloud.md, "When fetching brings nothing").
struct SyncProbe: Equatable, Sendable {
    struct Database: Equatable, Sendable {
        var scope: String
        var changedZones: Int
        var error: String?
        /// The first probe of a launch only sets where the next one starts from; the
        /// engine's own start fetched everything older.
        var isBaseline: Bool
    }

    var databases: [Database]

    var hasChanges: Bool { databases.contains { !$0.isBaseline && $0.changedZones > 0 } }

    var description: String {
        databases.map { database in
            if let error = database.error { return "\(database.scope) \(error)" }
            if database.isBaseline { return "\(database.scope) baseline" }
            return "\(database.scope) \(database.changedZones) zone\(database.changedZones == 1 ? "" : "s") changed"
        }.joined(separator: ", ")
    }
}

enum SyncDeviceChange: Equatable, Sendable {
    case account
    case network(isOnline: Bool)
}

/// The real device, through the household's iCloud container.
struct LiveSyncDevice: SyncDevice {
    let container: CKContainer
    private let probe: ChangeProbe

    init(container: CKContainer) {
        self.container = container
        probe = ChangeProbe(container: container)
    }

    func probeChanges() async -> SyncProbe? {
        await probe.probe()
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    func accountName() async throws -> String {
        try await container.userRecordID().recordName
    }

    func changes() -> AsyncStream<SyncDeviceChange> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(.network(isOnline: path.status == .satisfied))
            }
            monitor.start(queue: DispatchQueue(label: "Porchlight.network"))
            let accounts = Task {
                for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged).map({ _ in () }) {
                    continuation.yield(.account)
                }
            }
            continuation.onTermination = { _ in
                monitor.cancel()
                accounts.cancel()
            }
        }
    }
}

/// Asks each database for its changed zones since the last time, keeping its own change
/// tokens apart from the engine's: one small request per database, and nothing applied.
private actor ChangeProbe {
    let container: CKContainer
    private var tokens: [CKDatabase.Scope: CKServerChangeToken] = [:]

    init(container: CKContainer) {
        self.container = container
    }

    func probe() async -> SyncProbe {
        var databases: [SyncProbe.Database] = []
        for scope in [CKDatabase.Scope.private, .shared] {
            databases.append(await probe(scope))
        }
        return SyncProbe(databases: databases)
    }

    private func probe(_ scope: CKDatabase.Scope) async -> SyncProbe.Database {
        let database = scope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
        let name = scope == .private ? "private" : "shared"
        let isBaseline = tokens[scope] == nil
        var changed = 0
        do {
            var token = tokens[scope]
            for _ in 0..<5 {
                let page = try await database.databaseChanges(since: token, resultsLimit: 200)
                changed += page.modifications.count + page.deletions.count
                token = page.changeToken
                if !page.moreComing { break }
            }
            tokens[scope] = token
            return SyncProbe.Database(scope: name, changedZones: changed, error: nil, isBaseline: isBaseline)
        } catch {
            return SyncProbe.Database(scope: name, changedZones: 0, error: error.syncDescription, isBaseline: isBaseline)
        }
    }
}
