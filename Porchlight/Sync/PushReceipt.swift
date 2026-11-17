import CloudKit
import UIKit

// Pushes, made visible (docs/design/sync-icloud.md, "Seeing what sync does").
//
// CloudKit registers for remote notifications by itself once a sync engine exists, and the
// engine takes its pushes without the app's help: SQLiteData implements none of these
// methods and has no way to be handed a notification. So these only watch, and log what
// they see (a token's length, never the token), and a push also starts one check of our
// own, so a push the engine somehow didn't act on still brings the change in.
extension AppDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SyncController.current?.pushToken(arrived: true, detail: "length \(deviceToken.count)")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        SyncController.current?.pushToken(arrived: false, detail: error.syncDescription)
    }

    func application(
        _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let kind = PushKind(userInfo)
        let done = UncheckedFetchCompletion(run: completionHandler)
        guard let sync = SyncController.current else {
            done.run(.noData)
            return
        }
        Task { @MainActor in
            let answered = await sync.pushArrived(kind)
            done.run(answered ? .newData : .noData)
        }
    }
}

/// What a push says about itself, without anything it carries.
struct PushKind: Sendable, CustomStringConvertible {
    var isCloudKit: Bool
    var type: String
    var scope: String
    var subscription: String?

    init(_ userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            isCloudKit = false
            type = "not CloudKit"
            scope = "-"
            return
        }
        isCloudKit = true
        subscription = notification.subscriptionID
        switch notification {
        case let database as CKDatabaseNotification:
            type = "database"
            scope = database.databaseScope.name
        case let zone as CKRecordZoneNotification:
            type = "zone"
            scope = zone.databaseScope.name
        case is CKQueryNotification:
            type = "query"
            scope = "-"
        default:
            type = "other"
            scope = "-"
        }
    }

    var description: String {
        "\(type), \(scope) database\(subscription.map { ", subscription \($0)" } ?? "")"
    }
}

private extension CKDatabase.Scope {
    var name: String {
        switch self {
        case .private: "private"
        case .shared: "shared"
        case .public: "public"
        @unknown default: "unknown"
        }
    }
}

/// UIKit's completion handler, carried to the main actor where it is called.
private struct UncheckedFetchCompletion: @unchecked Sendable {
    let run: (UIBackgroundFetchResult) -> Void
}
