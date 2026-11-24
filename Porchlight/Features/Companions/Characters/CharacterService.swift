import Foundation

// Drawing a character goes through Porchlight's relay, never straight to the model
// (docs/design/companion-characters.md, "The relay"). The app talks to it through this
// protocol: the real one calls the Firebase callables `drawCharacter` and
// `characterAllowance`; every test and preview uses `FakeCharacterService`.

/// The species the relay draws.
enum CharacterSpecies: String, Sendable, Equatable {
    case dog
    case cat

    init?(_ species: Species) {
        switch species {
        case .dog: self = .dog
        case .cat: self = .cat
        default: return nil
        }
    }
}

/// What the app sends with every call, and the companion it is for.
struct CharacterSubject: Sendable, Equatable {
    var householdId: Household.ID
    var companionId: Companion.ID
    var species: CharacterSpecies
    /// The pet cut out of its photo, a PNG no longer than 1024 on a side
    /// (`PhotoSticker.Result.cutout`): the only picture that leaves the device.
    var cutout: Data
}

/// Three tries at the character, and the rounds of tries left for this companion after them.
struct CharacterTries: Sendable, Equatable {
    /// PNG stills, 512 pixels square, clear background.
    var images: [Data]
    var roundsLeft: Int
}

/// A mood's animation as the relay sends it: a GIF and its frame count.
struct CharacterAnimation: Sendable, Equatable {
    var gif: Data
    var frames: Int
}

/// What can go wrong, in the relay's words: its `details.code` as `kind`, and beside it the
/// `details.reason` the relay gives for a limit or for being unavailable. Plus no network at all.
///
/// The plain errors (`.limitReached`, `.unavailable`, ...) carry no reason, and are what a
/// call throws when the relay gave none. Screens decide by `kind` and word by `reason`:
/// two errors of one kind with different reasons are not equal.
struct CharacterServiceError: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// `limit-reached`: see `Reason` for which limit.
        case limitReached
        /// `refused`: the model would not draw this picture.
        case refused
        /// `unavailable`: the relay or the model is down, or the project's spending ceiling is
        /// reached. Also any code the app doesn't know.
        case unavailable
        /// `unauthenticated`: App Check said no; this device or build can't be checked.
        case unauthenticated
        /// `invalid`: a request outside the contract, which is a bug in the app.
        case invalid
        /// No network: the call never reached the relay.
        case offline
    }

    /// Which limit was reached, or why the relay is unavailable, in the relay's words.
    enum Reason: String, Equatable, Sendable, CaseIterable {
        /// No rounds of tries left for this companion, for life.
        case rounds
        /// This mood's still has been redrawn as often as it can be.
        case moodRedraws = "mood-redraws"
        /// This mood's animation has been redrawn as often as it can be.
        case animationRedraws = "animation-redraws"
        /// The household has characters for as many companions as it can.
        case companions
        /// The household's calls for today are used up; tomorrow there are more.
        case householdDay = "household-day"
        /// This copy of the app's calls for today are used up.
        case installationDay = "installation-day"
        /// The whole project has spent what it may today; tomorrow it draws again.
        case spendCeiling = "spend-ceiling"
        /// The model that draws is down, slow or out of reach.
        case model
        /// The relay itself failed.
        case relay

        /// The kind of error a reason belongs to; given with another kind it is dropped.
        var kind: Kind {
            switch self {
            case .rounds, .moodRedraws, .animationRedraws, .companions, .householdDay, .installationDay: .limitReached
            case .spendCeiling, .model, .relay: .unavailable
            }
        }
    }

    var kind: Kind
    /// Nil when the relay gave none, or one this build doesn't know: then `kind` alone speaks.
    var reason: Reason?

    init(_ kind: Kind, reason: Reason? = nil) {
        self.kind = kind
        self.reason = reason?.kind == kind ? reason : nil
    }

    static let limitReached = CharacterServiceError(.limitReached)
    static let refused = CharacterServiceError(.refused)
    static let unavailable = CharacterServiceError(.unavailable)
    static let unauthenticated = CharacterServiceError(.unauthenticated)
    static let invalid = CharacterServiceError(.invalid)
    static let offline = CharacterServiceError(.offline)

    /// The relay's `details.code` and `details.reason`, read as an error. An unknown or
    /// missing code is `unavailable`; an unknown or missing reason, or one that belongs to
    /// another code, is no reason.
    init(code: String?, reason: String? = nil) {
        let kind: Kind = switch code {
        case "limit-reached": .limitReached
        case "refused": .refused
        case "unauthenticated": .unauthenticated
        case "invalid": .invalid
        default: .unavailable
        }
        self.init(kind, reason: reason.flatMap(Reason.init(rawValue:)))
    }
}

/// The relay that draws characters.
protocol CharacterService: Sendable {
    /// False when this build can't draw at all (no Firebase configuration): the offer never
    /// shows and nothing is called. Reading it makes no call.
    var isConfigured: Bool { get }

    /// The rounds of tries left for a companion (`characterAllowance`).
    func allowance(householdId: Household.ID, companionId: Companion.ID) async throws -> Int

    /// Three tries from the cut-out (`drawCharacter`, step `tries`); uses a round.
    func tries(_ subject: CharacterSubject) async throws -> CharacterTries

    /// One mood's still, drawn to match `reference`, the chosen try (step `mood`): a PNG.
    func mood(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> Data

    /// One mood's animation, drawn from that mood's still (step `animation`).
    func animation(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> CharacterAnimation
}

/// The service a build has: the relay once its client exists and the configuration is in
/// the build; until then, and in every build without it, none.
enum CharacterServices {
    /// Set at launch by the relay's client when this build has a Firebase configuration.
    nonisolated(unsafe) static var live: (any CharacterService)?

    static var current: any CharacterService {
        #if DEBUG
        if let script = UserDefaults.standard.string(forKey: "debugCharacterService") {
            return FakeCharacterService(script: FakeCharacterService.Script(rawValue: script) ?? .draws)
        }
        #endif
        return live ?? UnconfiguredCharacterService()
    }
}

/// A build with no relay: nothing to call, and the offer never shows.
struct UnconfiguredCharacterService: CharacterService {
    var isConfigured: Bool { false }
    func allowance(householdId: Household.ID, companionId: Companion.ID) async throws -> Int { throw CharacterServiceError.unavailable }
    func tries(_ subject: CharacterSubject) async throws -> CharacterTries { throw CharacterServiceError.unavailable }
    func mood(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> Data { throw CharacterServiceError.unavailable }
    func animation(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> CharacterAnimation {
        throw CharacterServiceError.unavailable
    }
}

/// The relay's stand-in for tests, previews and UI tests: draws placeholder sprites in code
/// (`CharacterPlaceholders`), counts its calls, and fails as scripted.
final class FakeCharacterService: CharacterService, @unchecked Sendable {
    /// How it behaves, also as a launch argument (`-debugCharacterService <rawValue>`).
    enum Script: String, Sendable {
        /// Draws everything, with three rounds of tries per companion.
        case draws
        /// Draws stills, but every animation is unavailable (the model's preview feature down).
        case noAnimations
        /// No rounds left.
        case limitReached = "limit"
        case refused
        case unavailable
        case offline
        /// Every call waits this long before answering (seconds), for the waiting screens.
        case slow
    }

    struct Call: Equatable, Sendable {
        var step: String
        var mood: CharacterMood?
    }

    private let lock = NSLock()
    private var script: Script
    private var rounds: [Companion.ID: Int] = [:]
    private var recorded: [Call] = []
    var delay: Duration

    init(script: Script = .draws, delay: Duration = .zero) {
        self.script = script
        self.delay = script == .slow ? .seconds(4) : delay
    }

    var isConfigured: Bool { true }

    /// Every call made, in order.
    var calls: [Call] { lock.withLock { recorded } }

    func set(_ script: Script) { lock.withLock { self.script = script } }

    private func begin(_ step: String, mood: CharacterMood? = nil) async throws {
        let script = lock.withLock { () -> Script in
            recorded.append(Call(step: step, mood: mood))
            return self.script
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        switch script {
        case .limitReached: throw CharacterServiceError.limitReached
        case .refused: throw CharacterServiceError.refused
        case .unavailable: throw CharacterServiceError.unavailable
        case .offline: throw CharacterServiceError.offline
        case .noAnimations where step == "animation": throw CharacterServiceError.unavailable
        default: break
        }
    }

    func allowance(householdId: Household.ID, companionId: Companion.ID) async throws -> Int {
        try await begin("allowance")
        if lock.withLock({ script }) == .limitReached { return 0 }
        return lock.withLock { 3 - (rounds[companionId] ?? 0) }
    }

    func tries(_ subject: CharacterSubject) async throws -> CharacterTries {
        try await begin("tries")
        let round = lock.withLock { () -> Int? in
            let used = rounds[subject.companionId] ?? 0
            guard used < 3 else { return nil }
            rounds[subject.companionId] = used + 1
            return used
        }
        guard let round else { throw CharacterServiceError.limitReached }
        let images = (0..<3).compactMap { CharacterPlaceholders.sprite(species: subject.species, variant: round * 3 + $0, mood: .fine) }
        return CharacterTries(images: images, roundsLeft: 2 - round)
    }

    func mood(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> Data {
        try await begin("mood", mood: mood)
        guard let image = CharacterPlaceholders.sprite(species: subject.species, variant: Self.variant(of: reference), mood: mood) else {
            throw CharacterServiceError.unavailable
        }
        return image
    }

    func animation(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> CharacterAnimation {
        try await begin("animation", mood: mood)
        guard let gif = CharacterPlaceholders.animation(species: subject.species, variant: Self.variant(of: reference), mood: mood) else {
            throw CharacterServiceError.unavailable
        }
        return CharacterAnimation(gif: gif, frames: CharacterPlaceholders.frameCount)
    }

    /// Which try a reference was, so moods match it: read back from the sprite's own colour.
    private static func variant(of reference: Data) -> Int {
        CharacterPlaceholders.variant(of: reference) ?? 0
    }
}
