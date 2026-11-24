import FirebaseAppCheck
import FirebaseCore
import FirebaseFunctions
import Foundation

/// The relay over Firebase: the only file that knows Firebase is there
/// (docs/design/companion-characters.md, "The relay's client").
///
/// Nothing here runs until the first call to the relay. Making one of these configures
/// Firebase for this process, once, with the project's ids from the build and with App Check:
/// App Attest in every build people run, so the relay knows a call comes from a genuine copy
/// of Porchlight on a real device. A debug build may use App Check's debug provider, and only
/// when it is handed a debug token (`AppCheckDebug`); no token is ever in the repository.
///
/// The app uses no other part of Firebase: no Analytics, no Auth, no Firestore, no messaging.
final class FirebaseRelayBackend: CharacterRelayBackend, @unchecked Sendable {
    /// Firebase's own name for the one app this process configures.
    private static let configured = Configured()
    private let functions: Functions

    init(config: CharacterRelayConfig) {
        Self.configured.once(config)
        functions = Functions.functions(region: CharacterRelayConfig.region)
    }

    func call(_ function: String, _ payload: [String: String], limitedUse: Bool, timeout: TimeInterval) async throws -> [String: RelayValue] {
        let callable = functions.httpsCallable(function, options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: limitedUse))
        callable.timeoutInterval = timeout
        do {
            let result = try await callable.call(payload)
            guard let answer = result.data as? [String: Any] else { throw RelayFailure() }
            return answer.mapValues(RelayValue.init)
        } catch let failure as RelayFailure {
            throw failure
        } catch {
            throw Self.failure(for: error as NSError)
        }
    }

    /// Whether this process has configured Firebase yet: false until the first call to the
    /// relay, which the tests hold the app to.
    static var isFirebaseConfigured: Bool { FirebaseApp.app() != nil }

    /// A callable's error as a `RelayFailure`: the relay's own code out of `details`, the
    /// caller not being checked, or the network not being there.
    static func failure(for error: NSError) -> RelayFailure {
        var failure = RelayFailure()
        failure.isOffline = RelayNetworkErrors.isOffline(error)
        guard error.domain == FunctionsErrorDomain else { return failure }
        if let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any] {
            failure.code = details["code"] as? String
            failure.reason = details["reason"] as? String
        }
        failure.isUnauthenticated = error.code == FunctionsErrorCode.unauthenticated.rawValue
        return failure
    }

    /// Configures Firebase once per process, whichever thread asks first.
    private final class Configured: @unchecked Sendable {
        private let lock = NSLock()
        private var isDone = false

        func once(_ config: CharacterRelayConfig) {
            lock.withLock {
                guard !isDone else { return }
                isDone = true
                // Before the app exists: App Check asks this factory for its provider then.
                AppCheck.setAppCheckProviderFactory(PorchlightAppCheckFactory())
                let options = FirebaseOptions(googleAppID: config.appID, gcmSenderID: config.senderID)
                options.apiKey = config.apiKey
                options.projectID = config.projectID
                FirebaseApp.configure(options: options)
            }
        }
    }
}

/// App Attest, or in a debug build that was handed a debug token, App Check's debug provider.
private final class PorchlightAppCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        #if DEBUG
        if AppCheckDebug.adoptToken() { return AppCheckDebugProvider(app: app) }
        #endif
        return AppAttestProvider(app: app)
    }
}

#if DEBUG
/// A debug App Check token, for a debug build on a simulator or a developer's device to reach
/// the relay. The token is registered in the Firebase console by the project's owner and
/// handed to one run, as the environment variable `FIRAAppCheckDebugToken` (which App
/// Check's debug provider reads) or the launch argument `-debugAppCheckToken <token>`.
/// Without one a debug build uses App Attest like any other, and on a simulator, where there
/// is no App Attest, the relay refuses it.
enum AppCheckDebug {
    static let environmentKey = "FIRAAppCheckDebugToken"

    /// The token handed to this run, if any.
    static func token(environment: [String: String] = ProcessInfo.processInfo.environment, defaults: UserDefaults = .standard) -> String? {
        for candidate in [environment[environmentKey], defaults.string(forKey: "debugAppCheckToken")] {
            if let token = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty { return token }
        }
        return nil
    }

    /// Puts a launch-argument token where the debug provider looks. True when there is one.
    static func adoptToken() -> Bool {
        guard let token = token() else { return false }
        setenv(environmentKey, token, 1)
        return true
    }
}
#endif
