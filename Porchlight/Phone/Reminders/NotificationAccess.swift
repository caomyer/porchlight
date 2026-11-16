import Foundation
import UserNotifications

/// Whether this phone may show Porchlight's reminders.
enum NotificationAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed

    /// What iOS says now. DEBUG builds can pretend with `-notificationAccess
    /// notDetermined|denied|allowed`, so UI tests and screenshots show each state without
    /// the system prompt; asking then allows, like tapping Allow.
    @MainActor
    static func current() async -> NotificationAccess {
        #if DEBUG
        if let pretend = Pretend.access { return pretend }
        #endif
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    /// Shows the system prompt, once; afterwards iOS answers without asking.
    @MainActor
    static func request() async -> NotificationAccess {
        #if DEBUG
        if let pretend = Pretend.access {
            if pretend == .notDetermined { Pretend.access = .allowed }
            return Pretend.access ?? .allowed
        }
        #endif
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await current()
    }

    #if DEBUG
    @MainActor
    private enum Pretend {
        static var access: NotificationAccess? = switch UserDefaults.standard.string(forKey: "notificationAccess") {
        case "notDetermined": .notDetermined
        case "denied": .denied
        case "allowed": .allowed
        default: nil
        }
    }
    #endif
}
