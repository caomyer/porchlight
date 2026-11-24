import Foundation
import Network

// The real `CharacterService`: Porchlight's relay, two Firebase callables
// (docs/design/companion-characters.md, "The relay's client"; firebase/README.md).
//
// This file knows the contract and nothing of Firebase: what is sent, what comes back, which
// error is which. The transport behind it is `CharacterRelayBackend`; the real one is
// `FirebaseRelayBackend`, and tests use one that records its calls.

/// The Firebase project the relay lives in, as this build carries it: four ids from
/// `Config/Firebase.xcconfig` by way of the Info.plist. A build without them has no relay.
struct CharacterRelayConfig: Equatable, Sendable {
    var appID: String
    var apiKey: String
    var projectID: String
    var senderID: String

    /// The relay's region (firebase/functions/src/config.ts).
    static let region = "us-central1"

    /// The config in a bundle's Info.plist; nil unless all four ids are there.
    init?(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let text = (info[key] as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
                  // A build setting that was never set leaves its own name behind.
                  !text.contains("$(") else { return nil }
            return text
        }
        guard let appID = value("PorchlightFirebaseAppID"), let apiKey = value("PorchlightFirebaseAPIKey"),
              let projectID = value("PorchlightFirebaseProjectID"), let senderID = value("PorchlightFirebaseSenderID") else { return nil }
        self.appID = appID
        self.apiKey = apiKey
        self.projectID = projectID
        self.senderID = senderID
    }

    static var inThisBuild: CharacterRelayConfig? {
        CharacterRelayConfig(info: Bundle.main.infoDictionary ?? [:])
    }
}

/// What a callable answers with, as far as the contract goes.
enum RelayValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case texts([String])
    case other

    init(_ any: Any) {
        switch any {
        case let text as String: self = .text(text)
        // A Bool bridges to NSNumber too; the contract has none, so a number is a number.
        case let number as NSNumber: self = .number(number.doubleValue)
        case let list as [String]: self = .texts(list)
        default: self = .other
        }
    }
}

/// Why a call to the relay failed, before it is read as a `CharacterServiceError`.
struct RelayFailure: Error, Equatable, Sendable {
    /// The relay's own word for it (`details.code`), when it sent one.
    var code: String?
    /// Which limit, or why it is unavailable (`details.reason`), when it said.
    var reason: String?
    /// The callable's status said the caller could not be checked (App Check).
    var isUnauthenticated = false
    /// The call never reached the relay: no network.
    var isOffline = false
}

/// The transport: one call to one callable. Making one must touch nothing (no network, no
/// Firebase); the first `call` may.
protocol CharacterRelayBackend: Sendable {
    /// `limitedUse` asks for an App Check token good for this call only, which
    /// `drawCharacter` spends. Throws `RelayFailure`.
    func call(_ function: String, _ payload: [String: String], limitedUse: Bool, timeout: TimeInterval) async throws -> [String: RelayValue]
}

/// The relay as a `CharacterService`.
final class RelayCharacterService: CharacterService, @unchecked Sendable {
    /// How long a call may take. A drawing is one model attempt of up to 75 seconds and one
    /// retry, inside a function that gives up at 180; asking what is left is quick.
    static let drawTimeout: TimeInterval = 180
    static let allowanceTimeout: TimeInterval = 30

    private let config: CharacterRelayConfig?
    private let makeBackend: @Sendable (CharacterRelayConfig) -> any CharacterRelayBackend
    private let isOnline: @Sendable () -> Bool
    private let lock = NSLock()
    private var backend: (any CharacterRelayBackend)?

    init(
        config: CharacterRelayConfig?,
        isOnline: @escaping @Sendable () -> Bool = { CharacterRelayReachability.shared.isOnline },
        makeBackend: @escaping @Sendable (CharacterRelayConfig) -> any CharacterRelayBackend
    ) {
        self.config = config
        self.isOnline = isOnline
        self.makeBackend = makeBackend
    }

    /// Whether this build has a relay. Reads the config only: no backend is made, nothing is called.
    var isConfigured: Bool { config != nil }

    func allowance(householdId: Household.ID, companionId: Companion.ID) async throws -> Int {
        let answer = try await call(
            "characterAllowance", ["householdId": householdId.description, "companionId": companionId.description],
            limitedUse: false, timeout: Self.allowanceTimeout
        )
        guard case let .number(left)? = answer["roundsLeft"] else { throw CharacterServiceError.unavailable }
        return max(0, Int(left))
    }

    func tries(_ subject: CharacterSubject) async throws -> CharacterTries {
        let answer = try await draw(subject, step: "tries", mood: nil, reference: nil)
        guard case let .texts(encoded)? = answer["images"], case let .number(left)? = answer["roundsLeft"] else {
            throw CharacterServiceError.unavailable
        }
        let images = encoded.compactMap { Self.picture($0, isPNG: true) }
        // Every try must be a whole picture: a round with a broken one in it is no answer.
        guard !images.isEmpty, images.count == encoded.count else { throw CharacterServiceError.unavailable }
        return CharacterTries(images: images, roundsLeft: max(0, Int(left)))
    }

    func mood(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> Data {
        let answer = try await draw(subject, step: "mood", mood: mood, reference: reference)
        guard case let .text(encoded)? = answer["image"], let image = Self.picture(encoded, isPNG: true) else {
            throw CharacterServiceError.unavailable
        }
        return image
    }

    func animation(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> CharacterAnimation {
        let answer = try await draw(subject, step: "animation", mood: mood, reference: reference)
        guard case let .text(encoded)? = answer["gif"], let gif = Self.picture(encoded, isPNG: false) else {
            throw CharacterServiceError.unavailable
        }
        let frames: Int = if case let .number(count)? = answer["frames"] { Int(count) } else { 0 }
        return CharacterAnimation(gif: gif, frames: frames)
    }

    // MARK: Pieces

    private func draw(_ subject: CharacterSubject, step: String, mood: CharacterMood?, reference: Data?) async throws -> [String: RelayValue] {
        var payload = [
            "householdId": subject.householdId.description,
            "companionId": subject.companionId.description,
            "species": subject.species.rawValue,
            "step": step,
            "cutout": subject.cutout.base64EncodedString(),
        ]
        if let mood { payload["mood"] = mood.rawValue }
        if let reference { payload["reference"] = reference.base64EncodedString() }
        return try await call("drawCharacter", payload, limitedUse: true, timeout: Self.drawTimeout)
    }

    /// One call, with every failure read as the contract's error. Cancelling the task ends
    /// the wait at once; the relay may still finish the drawing (and count it), since a
    /// request already sent cannot be taken back.
    private func call(_ function: String, _ payload: [String: String], limitedUse: Bool, timeout: TimeInterval) async throws -> [String: RelayValue] {
        guard let config else { throw CharacterServiceError.unavailable }
        try Task.checkCancellation()
        // Said before anything is sent: with no network there is nothing to wait three minutes for.
        guard isOnline() else { throw CharacterServiceError.offline }
        let backend = theBackend(config)
        do {
            return try await Self.cancellable { try await backend.call(function, payload, limitedUse: limitedUse, timeout: timeout) }
        } catch let failure as RelayFailure {
            throw Self.error(for: failure)
        } catch let error as CharacterServiceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CharacterServiceError.unavailable
        }
    }

    /// The contract's error for a failure: no network first, then the relay's own code, then
    /// a caller that could not be checked; anything else is the relay being unavailable.
    static func error(for failure: RelayFailure) -> CharacterServiceError {
        if failure.isOffline { return .offline }
        if let code = failure.code { return CharacterServiceError(code: code, reason: failure.reason) }
        if failure.isUnauthenticated { return .unauthenticated }
        return .unavailable
    }

    /// Made on the first call, once: until someone asks for a drawing or for what is left,
    /// this build has made no backend, configured nothing and sent nothing.
    private func theBackend(_ config: CharacterRelayConfig) -> any CharacterRelayBackend {
        lock.withLock {
            if let backend { return backend }
            let made = makeBackend(config)
            backend = made
            return made
        }
    }

    /// Whether a backend has been made yet, for the test that nothing is touched before a call.
    var hasBackend: Bool { lock.withLock { backend != nil } }

    /// A picture out of the answer: base64, and really the kind of file it should be.
    static func picture(_ encoded: String, isPNG: Bool) -> Data? {
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else { return nil }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        return (isPNG ? data.prefix(8) == png : CharacterAnimationCodec.isGIF(data)) ? data : nil
    }

    /// Runs `work`, but stops waiting the moment the task is cancelled: the callable itself
    /// cannot be cancelled, so it is left to finish unheard.
    static func cancellable<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let gate = OnceGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.wait(continuation)
                Task.detached {
                    do { gate.finish(.success(try await work())) } catch { gate.finish(.failure(error)) }
                }
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

/// Resumes a continuation once, with whichever comes first: the answer, or the cancellation.
private final class OnceGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var early: Result<T, any Error>?
    private var isDone = false

    func wait(_ continuation: CheckedContinuation<T, any Error>) {
        let result = lock.withLock { () -> Result<T, any Error>? in
            if let early { isDone = true; return early }
            self.continuation = continuation
            return nil
        }
        if let result { continuation.resume(with: result) }
    }

    func finish(_ result: Result<T, any Error>) {
        let waiting = lock.withLock { () -> CheckedContinuation<T, any Error>? in
            guard !isDone else { return nil }
            guard let continuation else {
                // Cancelled before the wait began: kept for `wait`.
                if early == nil { early = result }
                return nil
            }
            isDone = true
            self.continuation = nil
            return continuation
        }
        waiting?.resume(with: result)
    }
}

/// Whether there is any network at all, kept by the system's path monitor. It starts on first
/// use (the first call to the relay), never at launch, and it sends nothing.
final class CharacterRelayReachability: @unchecked Sendable {
    static let shared = CharacterRelayReachability()

    private let lock = NSLock()
    private var monitor: NWPathMonitor?
    private var satisfied = true

    /// True until the monitor has said otherwise: a call is only ever refused as offline on
    /// the monitor's word, never on a guess.
    var isOnline: Bool {
        lock.withLock {
            if monitor == nil {
                let monitor = NWPathMonitor()
                monitor.pathUpdateHandler = { [weak self] path in
                    guard let self else { return }
                    self.lock.withLock { self.satisfied = path.status != .unsatisfied }
                }
                monitor.start(queue: DispatchQueue(label: "porchlight.character-relay.reachability"))
                self.monitor = monitor
            }
            return satisfied
        }
    }
}

/// Which errors mean the network is not there.
enum RelayNetworkErrors {
    static let offlineCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
        NSURLErrorInternationalRoamingOff, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
    ]

    /// Whether `error`, or an error under it, is the URL system saying there is no network.
    static func isOffline(_ error: NSError, depth: Int = 0) -> Bool {
        if error.domain == NSURLErrorDomain && offlineCodes.contains(error.code) { return true }
        guard depth < 4, let under = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return isOffline(under, depth: depth + 1)
    }
}

enum CharacterRelay {
    /// Puts the relay in `CharacterServices.live` at launch when this build carries a Firebase
    /// project. It only reads the Info.plist: Firebase is configured, and anything sent, by
    /// the first drawing or allowance call (`FirebaseRelayBackend`), never before.
    static func install(info: [String: Any] = Bundle.main.infoDictionary ?? [:], into set: (any CharacterService) -> Void = { CharacterServices.live = $0 }) {
        guard let config = CharacterRelayConfig(info: info) else { return }
        set(RelayCharacterService(config: config) { FirebaseRelayBackend(config: $0) })
    }
}
