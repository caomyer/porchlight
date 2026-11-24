import Foundation
import Testing
@testable import Porchlight

/// The relay's client below Firebase (docs/design/companion-characters.md, "The relay's
/// client"): what it sends, how it reads an answer and a failure, and that nothing of the
/// relay or of Firebase is touched until a character is asked for.
@Suite("The character relay's client")
struct CharacterRelayClientTests {
    /// A transport that records what it is asked and answers as scripted.
    private final class Backend: CharacterRelayBackend, @unchecked Sendable {
        struct Call: Equatable {
            var function: String
            var payload: [String: String]
            var limitedUse: Bool
            var timeout: TimeInterval
        }

        private let lock = NSLock()
        private var recorded: [Call] = []
        var answer: @Sendable (String) throws -> [String: RelayValue]
        var delay: Duration = .zero

        init(_ answer: @escaping @Sendable (String) throws -> [String: RelayValue] = { _ in [:] }) {
            self.answer = answer
        }

        var calls: [Call] { lock.withLock { recorded } }

        func call(_ function: String, _ payload: [String: String], limitedUse: Bool, timeout: TimeInterval) async throws -> [String: RelayValue] {
            lock.withLock { recorded.append(Call(function: function, payload: payload, limitedUse: limitedUse, timeout: timeout)) }
            if delay > .zero { try? await Task.sleep(for: delay) }
            return try answer(function)
        }
    }

    /// Counts the backends made, so a test can say none was.
    private final class Factory: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        let backend: Backend

        init(_ backend: Backend) { self.backend = backend }

        var made: Int { lock.withLock { count } }

        func make(_ config: CharacterRelayConfig) -> any CharacterRelayBackend {
            lock.withLock { count += 1 }
            return backend
        }
    }

    private static let info: [String: String] = [
        "PorchlightFirebaseAppID": "1:1234567890:ios:0123456789abcdef", "PorchlightFirebaseAPIKey": "test-api-key",
        "PorchlightFirebaseProjectID": "demo-porchlight", "PorchlightFirebaseSenderID": "1234567890",
    ]
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    private static let gif = Data("GIF89a-and-frames".utf8)
    private static let subject = CharacterSubject(
        householdId: Household.ID(UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!),
        companionId: Companion.ID(UUID(uuidString: "11111111-2222-4333-8444-555555555555")!),
        species: .cat, cutout: Data([0x89, 0x50, 0x4E, 0x47, 9, 9])
    )

    private func service(_ backend: Backend, online: Bool = true) -> (RelayCharacterService, Factory) {
        let factory = Factory(backend)
        let config = CharacterRelayConfig(info: Self.info)
        return (RelayCharacterService(config: config, isOnline: { online }, makeBackend: factory.make), factory)
    }

    // MARK: The build's config

    @Test("A build has a relay only with all four of the project's ids")
    func config() throws {
        let config = try #require(CharacterRelayConfig(info: Self.info))
        #expect(config.appID == "1:1234567890:ios:0123456789abcdef" && config.projectID == "demo-porchlight")
        #expect(config.apiKey == "test-api-key" && config.senderID == "1234567890")
        for key in Self.info.keys {
            var missing: [String: Any] = Self.info
            missing[key] = nil
            #expect(CharacterRelayConfig(info: missing) == nil, "without \(key)")
            missing[key] = ""
            #expect(CharacterRelayConfig(info: missing) == nil, "with \(key) empty, as a build setting never set leaves it")
            missing[key] = "$(PORCHLIGHT_FIREBASE_APP_ID)"
            #expect(CharacterRelayConfig(info: missing) == nil, "with \(key) left unexpanded")
        }
        #expect(CharacterRelayConfig(info: [:]) == nil)
        #expect(CharacterRelayConfig.region == "us-central1")
    }

    @Test("A build without the project's ids has no relay: not configured, and every call unavailable without a backend")
    func noConfig() async {
        let factory = Factory(Backend())
        let service = RelayCharacterService(config: nil, isOnline: { true }, makeBackend: factory.make)
        #expect(!service.isConfigured)
        await #expect(throws: CharacterServiceError.unavailable) { try await service.tries(Self.subject) }
        await #expect(throws: CharacterServiceError.unavailable) {
            _ = try await service.allowance(householdId: Self.subject.householdId, companionId: Self.subject.companionId)
        }
        #expect(factory.made == 0)
        var live: (any CharacterService)?
        CharacterRelay.install(info: [:]) { live = $0 }
        #expect(live == nil, "nothing is installed at launch")
        CharacterRelay.install(info: Self.info) { live = $0 }
        #expect(live?.isConfigured == true)
    }

    // MARK: Nothing until asked

    @Test("Until a character is asked for, no backend is made: nothing configured, nothing sent")
    func nothingUntilAsked() async throws {
        let backend = Backend { _ in ["roundsLeft": .number(3)] }
        let (service, factory) = service(backend)
        #expect(service.isConfigured, "reading whether it can draw")
        #expect(service.isConfigured && !service.hasBackend && factory.made == 0 && backend.calls.isEmpty, "makes and sends nothing")
        #expect(try await service.allowance(householdId: Self.subject.householdId, companionId: Self.subject.companionId) == 3)
        #expect(factory.made == 1 && service.hasBackend)
        _ = try await service.allowance(householdId: Self.subject.householdId, companionId: Self.subject.companionId)
        #expect(factory.made == 1, "one backend for the life of the service")
    }

    @Test("This process has not configured Firebase: the unit tests' own app launched, browsed and drew nothing")
    @MainActor
    func firebaseNotConfiguredAtLaunch() {
        // The test bundle runs inside the app, which has launched: `CharacterRelay.install`
        // ran in `Launch.start`. No test in the bundle calls the real backend.
        #expect(!FirebaseRelayBackend.isFirebaseConfigured)
    }

    // MARK: What is sent

    @Test("Asking what is left sends the two ids, lower case, with an ordinary token")
    func allowance() async throws {
        let backend = Backend { _ in ["roundsLeft": .number(2)] }
        let (service, _) = service(backend)
        #expect(try await service.allowance(householdId: Self.subject.householdId, companionId: Self.subject.companionId) == 2)
        #expect(backend.calls == [.init(
            function: "characterAllowance",
            payload: ["householdId": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "companionId": "11111111-2222-4333-8444-555555555555"],
            limitedUse: false, timeout: RelayCharacterService.allowanceTimeout
        )])
    }

    @Test("Three tries send the cut-out and nothing of a mood, with a token good for one call")
    func tries() async throws {
        let backend = Backend { _ in ["images": .texts(Array(repeating: Self.png.base64EncodedString(), count: 3)), "roundsLeft": .number(2)] }
        let (service, _) = service(backend)
        let tries = try await service.tries(Self.subject)
        #expect(tries == CharacterTries(images: [Self.png, Self.png, Self.png], roundsLeft: 2))
        let call = try #require(backend.calls.first)
        #expect(call.function == "drawCharacter" && call.limitedUse && call.timeout == RelayCharacterService.drawTimeout)
        #expect(call.payload == [
            "householdId": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "companionId": "11111111-2222-4333-8444-555555555555",
            "species": "cat", "step": "tries", "cutout": Self.subject.cutout.base64EncodedString(),
        ], "no mood, no reference: the relay refuses either with tries")
        #expect(RelayCharacterService.drawTimeout >= 150, "a drawing is up to 75 seconds, twice")
    }

    @Test("A mood and its animation send the mood and the picture to match")
    func moodAndAnimation() async throws {
        let backend = Backend { _ in ["image": .text(Self.png.base64EncodedString()), "gif": .text(Self.gif.base64EncodedString()), "frames": .number(9)] }
        let (service, _) = service(backend)
        let reference = Data([0x89, 0x50, 0x4E, 0x47, 7])
        #expect(try await service.mood(.waiting, of: Self.subject, reference: reference) == Self.png)
        #expect(try await service.animation(.zoomies, of: Self.subject, reference: reference) == CharacterAnimation(gif: Self.gif, frames: 9))
        #expect(backend.calls.map(\.payload["step"]) == ["mood", "animation"])
        #expect(backend.calls.map(\.payload["mood"]) == ["waiting", "zoomies"])
        #expect(backend.calls.allSatisfy { $0.payload["reference"] == reference.base64EncodedString() && $0.limitedUse && $0.function == "drawCharacter" })
        #expect(backend.calls.allSatisfy { Set($0.payload.keys) == ["householdId", "companionId", "species", "step", "mood", "cutout", "reference"] })
    }

    // MARK: Answers that are not answers

    @Test("An answer outside the contract is the relay being unavailable, never a broken picture")
    func badAnswers() async {
        let notBase64: [String: RelayValue] = ["images": .texts(["not base64!!"]), "roundsLeft": .number(1)]
        let notPNG: [String: RelayValue] = ["images": .texts([Self.gif.base64EncodedString()]), "roundsLeft": .number(1)]
        let oneBroken: [String: RelayValue] = ["images": .texts([Self.png.base64EncodedString(), ""]), "roundsLeft": .number(1)]
        for answer in [[:], notBase64, notPNG, oneBroken, ["images": .texts([]), "roundsLeft": .number(1)], ["images": .other, "roundsLeft": .number(1)]] {
            let (service, _) = service(Backend { _ in answer })
            await #expect(throws: CharacterServiceError.unavailable) { try await service.tries(Self.subject) }
        }
        let (stills, _) = service(Backend { _ in ["image": .text(Self.gif.base64EncodedString()), "gif": .text(Self.png.base64EncodedString())] })
        await #expect(throws: CharacterServiceError.unavailable) { try await stills.mood(.fine, of: Self.subject, reference: Self.png) }
        await #expect(throws: CharacterServiceError.unavailable) { try await stills.animation(.fine, of: Self.subject, reference: Self.png) }
        let (count, _) = service(Backend { _ in ["roundsLeft": .text("3")] })
        await #expect(throws: CharacterServiceError.unavailable) {
            _ = try await count.allowance(householdId: Self.subject.householdId, companionId: Self.subject.companionId)
        }
        #expect(RelayValue(3) == .number(3) && RelayValue("x") == .text("x") && RelayValue(["a"]) == .texts(["a"]) && RelayValue(["a": 1]) == .other)
    }

    // MARK: Failures

    @Test("Each failure is the contract's error, with the relay's reason when it gave one")
    func failures() async {
        let cases: [(RelayFailure, CharacterServiceError)] = [
            (RelayFailure(code: "limit-reached", reason: "rounds"), CharacterServiceError(.limitReached, reason: .rounds)),
            (RelayFailure(code: "limit-reached", reason: "household-day"), CharacterServiceError(.limitReached, reason: .householdDay)),
            (RelayFailure(code: "limit-reached"), .limitReached),
            (RelayFailure(code: "limit-reached", reason: "a-new-limit"), .limitReached),
            (RelayFailure(code: "unavailable", reason: "spend-ceiling"), CharacterServiceError(.unavailable, reason: .spendCeiling)),
            (RelayFailure(code: "unavailable", reason: "rounds"), .unavailable),
            (RelayFailure(code: "refused"), .refused),
            (RelayFailure(code: "invalid"), .invalid),
            (RelayFailure(code: "teapot"), .unavailable),
            (RelayFailure(isUnauthenticated: true), .unauthenticated),
            (RelayFailure(), .unavailable),
            (RelayFailure(code: "unavailable", isOffline: true), .offline),
        ]
        for (failure, expected) in cases {
            #expect(RelayCharacterService.error(for: failure) == expected)
            let (service, _) = service(Backend { _ in throw failure })
            await #expect(throws: expected) { try await service.tries(Self.subject) }
        }
        struct Odd: Error {}
        let (odd, _) = service(Backend { _ in throw Odd() })
        await #expect(throws: CharacterServiceError.unavailable) { try await odd.tries(Self.subject) }
    }

    @Test("A reason belongs to its kind; any other, unknown or missing is no reason")
    func reasons() {
        for reason in CharacterServiceError.Reason.allCases {
            let code = reason.kind == .limitReached ? "limit-reached" : "unavailable"
            let error = CharacterServiceError(code: code, reason: reason.rawValue)
            #expect(error.kind == reason.kind && error.reason == reason)
            #expect(CharacterServiceError(code: "refused", reason: reason.rawValue) == .refused, "refused carries none")
        }
        #expect(CharacterServiceError.Reason.allCases.map(\.rawValue).sorted() == [
            "animation-redraws", "companions", "household-day", "installation-day", "model", "mood-redraws", "relay", "rounds", "spend-ceiling",
        ], "the relay's words, each of them")
        #expect(CharacterServiceError(code: "limit-reached", reason: "model") == .limitReached)
        #expect(CharacterServiceError(code: "limit-reached", reason: nil).reason == nil)
        #expect(CharacterServiceError(.limitReached, reason: .rounds) != .limitReached, "decide by kind, word by reason")
        #expect(CharacterServiceError(.limitReached, reason: .rounds).kind == CharacterServiceError.limitReached.kind)
    }

    @Test("With no network nothing is sent, and the wait is not three minutes long")
    func offline() async {
        let backend = Backend()
        let (service, factory) = service(backend, online: false)
        await #expect(throws: CharacterServiceError.offline) { try await service.tries(Self.subject) }
        #expect(backend.calls.isEmpty && factory.made == 0)
    }

    @Test("The URL system's own words for no network are read through whatever wraps them")
    func networkErrors() {
        let none = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(RelayNetworkErrors.isOffline(none))
        #expect(RelayNetworkErrors.isOffline(NSError(domain: "com.firebase.functions", code: 14, userInfo: [NSUnderlyingErrorKey: none])))
        #expect(!RelayNetworkErrors.isOffline(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)), "slow is not offline")
        #expect(!RelayNetworkErrors.isOffline(NSError(domain: "com.firebase.functions", code: 16)))
        #expect(FirebaseRelayBackend.failure(for: none) == RelayFailure(isOffline: true))
    }

    @Test("A callable's error is read by its details: the relay's code and reason, or the caller not being checked")
    func callableErrors() {
        let domain = "com.firebase.functions"
        let limit = NSError(domain: domain, code: 8, userInfo: ["details": ["code": "limit-reached", "reason": "rounds"]])
        #expect(FirebaseRelayBackend.failure(for: limit) == RelayFailure(code: "limit-reached", reason: "rounds"))
        let refused = NSError(domain: domain, code: 9, userInfo: ["details": ["code": "refused"]])
        #expect(FirebaseRelayBackend.failure(for: refused) == RelayFailure(code: "refused"))
        #expect(FirebaseRelayBackend.failure(for: NSError(domain: domain, code: 16)) == RelayFailure(isUnauthenticated: true), "App Check said no")
        #expect(FirebaseRelayBackend.failure(for: NSError(domain: domain, code: 13)) == RelayFailure(), "an internal error says nothing more")
        #expect(FirebaseRelayBackend.failure(for: NSError(domain: domain, code: 3, userInfo: ["details": "not a dictionary"])) == RelayFailure())
        #expect(FirebaseRelayBackend.failure(for: NSError(domain: "elsewhere", code: 16)) == RelayFailure(), "only a callable's own errors are read")
    }

    // MARK: Cancelling

    @Test("Cancelling ends the wait at once, whatever the relay is still doing")
    func cancelling() async throws {
        let backend = Backend { _ in ["roundsLeft": .number(3)] }
        backend.delay = .seconds(30)
        let (service, _) = service(backend)
        let started = ContinuousClock.now
        let task = Task { try await service.allowance(householdId: Self.subject.householdId, companionId: Self.subject.companionId) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(backend.calls.count == 1, "the request had gone; it is not taken back")
    }

    @Test("A task already cancelled sends nothing")
    func cancelledBefore() async {
        let backend = Backend()
        let (service, _) = service(backend)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.tries(Self.subject)
        }
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(backend.calls.isEmpty)
    }

    #if DEBUG
    @Test("A debug App Check token is only ever one handed to this run")
    func debugToken() throws {
        let defaults = try #require(UserDefaults(suiteName: "relay-client-tests-\(UUID().uuidString)"))
        #expect(AppCheckDebug.token(environment: [:], defaults: defaults) == nil, "none in the build, none in the repository")
        #expect(AppCheckDebug.token(environment: ["FIRAAppCheckDebugToken": " abc "], defaults: defaults) == "abc")
        #expect(AppCheckDebug.token(environment: ["FIRAAppCheckDebugToken": ""], defaults: defaults) == nil)
        defaults.set("from-a-launch-argument", forKey: "debugAppCheckToken")
        #expect(AppCheckDebug.token(environment: [:], defaults: defaults) == "from-a-launch-argument")
    }
    #endif
}
