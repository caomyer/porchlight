import CloudKit
import Observation
import UIKit

/// Where an invite link that opened the app waits until someone answers it (journey A4).
///
/// The system hands the share to the scene delegate, outside SwiftUI, so this is the one
/// shared place both can reach.
@MainActor
@Observable
final class ShareInbox {
    static let shared = ShareInbox()

    /// The invite on screen, if any. A newer one replaces it.
    var invitation: HouseholdInvitation?

    func receive(_ metadata: CKShare.Metadata) {
        invitation = HouseholdInvitation(metadata: metadata)
    }
}

/// Gives every scene `SceneDelegate`, which is how iOS delivers an accepted share to an app
/// with the SwiftUI life cycle. Nothing else about launching changes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Receives invite links: while the app runs, and when one launches it.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        ShareInbox.shared.receive(metadata)
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareInbox.shared.receive(cloudKitShareMetadata)
    }
}
