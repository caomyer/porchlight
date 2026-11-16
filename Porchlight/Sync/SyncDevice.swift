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
}

enum SyncDeviceChange: Equatable, Sendable {
    case account
    case network(isOnline: Bool)
}

/// The real device, through the household's iCloud container.
struct LiveSyncDevice: SyncDevice {
    let container: CKContainer

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
