import Foundation
import Observation

// Drawing a companion's character (docs/design/companion-characters.md, "The character
// journey"): the consent that shows what leaves the device, three tries to pick from, then
// the four moods drawn to match. The steps live here, apart from any screen, so each one and
// each failure is tested on the stand-in relay.

/// A drawing in progress, kept on this device only (never synced) so a journey the app
/// closed mid-way can be finished or thrown away, and never shows as a half character.
struct CharacterDraft: Codable, Equatable, Sendable {
    var companionId: Companion.ID
    var species: CharacterSpecies.RawValue
    /// The cut-out the tries were drawn from: every mood is drawn from it too.
    var cutout: Data?
    /// The tries of the last round, and the one picked.
    var tries: [Data] = []
    var picked: Int?
    var roundsLeft: Int?
    /// Each mood's still and, when it came, its animation's strip.
    var stills: [CharacterMood: Data] = [:]
    var strips: [CharacterMood: Data] = [:]
    var frameCounts: [CharacterMood: Int] = [:]
    var startedAt: Date
}

/// Where drafts are kept: one file per companion in Application Support, never in iCloud.
struct CharacterDraftStore: Sendable {
    let folder: URL

    static var standard: CharacterDraftStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return CharacterDraftStore(folder: base.appendingPathComponent("CharacterDrafts", isDirectory: true))
    }

    private func file(_ companionId: Companion.ID) -> URL { folder.appendingPathComponent("\(companionId).plist") }

    func load(_ companionId: Companion.ID) -> CharacterDraft? {
        guard let data = try? Data(contentsOf: file(companionId)) else { return nil }
        return try? PropertyListDecoder().decode(CharacterDraft.self, from: data)
    }

    func save(_ draft: CharacterDraft) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? PropertyListEncoder().encode(draft) {
            try? data.write(to: file(draft.companionId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func discard(_ companionId: Companion.ID) {
        try? FileManager.default.removeItem(at: file(companionId))
    }
}

@MainActor
@Observable
final class CharacterDrawing {
    enum Step: Equatable {
        /// A drawing left mid-way: finish it, or throw it away.
        case resume
        /// No photo yet: pick one first.
        case needsPhoto
        /// Cutting the pet out of its photo, on the device.
        case cutting
        /// The photo and the cut-out side by side, and what will be sent.
        case consent(PhotoSticker.Result)
        /// The cut-out couldn't be made; the photo stays.
        case cutFailed(PhotoSticker.Failure)
        /// "Drawing Yo-Yo": waiting for the tries.
        case drawingTries
        /// Three tries to pick from.
        case picking
        /// "Meet Yo-Yo": the four moods, arriving as they are drawn.
        case meeting
        /// Saved; it shows everywhere now.
        case done
        /// A call failed; `failure` says what and how to go on.
        case failed(Failure)
    }

    /// A failed call, with the step it happened at, so the words can say what happened.
    struct Failure: Equatable {
        enum Stage: Equatable { case tries, mood(CharacterMood), allowance }
        var error: CharacterServiceError
        var stage: Stage
    }

    /// How a mood stands while meeting.
    enum MoodState: Equatable {
        case drawing
        case ready
        case failed(CharacterServiceError)
    }

    private(set) var step: Step
    private(set) var draft: CharacterDraft
    /// The cut-out sent, and the sticker made with it (the free path).
    private(set) var cut: PhotoSticker.Result?
    private(set) var photo: Data?
    private(set) var moodStates: [CharacterMood: MoodState] = [:]
    /// The try picked on screen, before "This one".
    var selection = 0

    @ObservationIgnored let subject: (householdId: Household.ID, companionId: Companion.ID, species: CharacterSpecies)
    @ObservationIgnored private let service: any CharacterService
    @ObservationIgnored private let drafts: CharacterDraftStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cutOut: @Sendable (Data) async throws -> PhotoSticker.Result
    @ObservationIgnored private let strip: @Sendable (CharacterAnimation) -> (strip: Data, frames: Int)?
    @ObservationIgnored private var work: [Task<Void, Never>] = []

    init(
        householdId: Household.ID, companionId: Companion.ID, species: CharacterSpecies, photo: Data?,
        service: any CharacterService, drafts: CharacterDraftStore = .standard, defaults: UserDefaults = .standard,
        cutOut: @escaping @Sendable (Data) async throws -> PhotoSticker.Result = { try await PhotoSticker.make(from: $0) },
        strip: @escaping @Sendable (CharacterAnimation) -> (strip: Data, frames: Int)? = CharacterFrames.strip
    ) {
        subject = (householdId, companionId, species)
        self.photo = photo
        self.service = service
        self.drafts = drafts
        self.defaults = defaults
        self.cutOut = cutOut
        self.strip = strip
        if let saved = drafts.load(companionId), !saved.tries.isEmpty {
            draft = saved
            step = .resume
        } else {
            draft = CharacterDraft(companionId: companionId, species: species.rawValue, startedAt: .now)
            step = .cutting
        }
    }

    /// Whether this companion has a drawing left mid-way on this device.
    static func hasDraft(_ companionId: Companion.ID, in drafts: CharacterDraftStore = .standard) -> Bool {
        drafts.load(companionId).map { !$0.tries.isEmpty } ?? false
    }

    // MARK: Cutting out and consent

    /// Cuts the pet out of its photo, or of `newPhoto` picked just now.
    func cut(newPhoto: Data? = nil) async {
        if let newPhoto { photo = newPhoto }
        guard let photo else {
            step = .needsPhoto
            return
        }
        step = .cutting
        do {
            let result = try await cutOut(photo)
            cut = result
            step = .consent(result)
        } catch let failure as PhotoSticker.Failure {
            step = .cutFailed(failure)
        } catch {
            step = .cutFailed(.unavailable)
        }
    }

    private func subject(_ cutout: Data) -> CharacterSubject {
        CharacterSubject(householdId: subject.householdId, companionId: subject.companionId, species: subject.species, cutout: cutout)
    }

    // MARK: Tries

    /// After consent, or "try again": a round of three tries. Nothing is sent before this.
    func drawTries() async {
        guard let cutout = cut?.cutout else { return }
        step = .drawingTries
        do {
            let tries = try await service.tries(subject(cutout))
            draft.cutout = cutout
            draft.tries = tries.images
            draft.roundsLeft = tries.roundsLeft
            CharacterOffer.remember(roundsLeft: tries.roundsLeft, for: subject.companionId, defaults: defaults)
            draft.picked = nil
            draft.stills = [:]
            draft.strips = [:]
            draft.frameCounts = [:]
            selection = 0
            drafts.save(draft)
            step = .picking
        } catch {
            let error = error as? CharacterServiceError ?? .unavailable
            // A limit with no rounds known to be left is this pet's: none are.
            if error.kind == .limitReached, (draft.roundsLeft ?? 0) == 0 {
                draft.roundsLeft = 0
                CharacterOffer.remember(roundsLeft: 0, for: subject.companionId, defaults: defaults)
            }
            step = .failed(Failure(error: error, stage: .tries))
        }
    }

    /// "This one": the picked try becomes the character's doing-fine still, and the other
    /// moods are drawn to match it, each as it can be, never one blocking another.
    func pick() {
        guard draft.tries.indices.contains(selection) else { return }
        draft.picked = selection
        draft.stills = [.fine: draft.tries[selection]]
        drafts.save(draft)
        step = .meeting
        drawMissing()
    }

    // MARK: Moods

    /// Draws every mood not drawn yet, and every animation not made yet.
    func drawMissing() {
        guard let cutout = draft.cutout, let reference = draft.stills[.fine] else { return }
        for mood in CharacterMood.allCases {
            if draft.stills[mood] == nil {
                moodStates[mood] = .drawing
                work.append(Task { await self.drawMood(mood, cutout: cutout, reference: reference) })
            } else {
                moodStates[mood] = .ready
                if draft.strips[mood] == nil { work.append(Task { await self.animate(mood, cutout: cutout) }) }
            }
        }
    }

    /// Tapping a mood draws it again, to match the picked try.
    func redraw(_ mood: CharacterMood) {
        guard mood != .fine, moodStates[mood] != .drawing, let cutout = draft.cutout, let reference = draft.stills[.fine] else { return }
        moodStates[mood] = .drawing
        work.append(Task { await self.drawMood(mood, cutout: cutout, reference: reference, again: true) })
    }

    private func drawMood(_ mood: CharacterMood, cutout: Data, reference: Data, again: Bool = false) async {
        do {
            let still = try await service.mood(mood, of: subject(cutout), reference: reference)
            draft.stills[mood] = still
            if again { draft.strips[mood] = nil; draft.frameCounts[mood] = nil }
            drafts.save(draft)
            moodStates[mood] = .ready
            await animate(mood, cutout: cutout)
        } catch {
            // A redraw that fails keeps the still it had.
            moodStates[mood] = draft.stills[mood] != nil ? .ready : .failed(error as? CharacterServiceError ?? .unavailable)
        }
    }

    /// A mood's animation: when it fails (it is a preview feature at the model's maker), the
    /// still stands on its own and the animation can be made another time.
    private func animate(_ mood: CharacterMood, cutout: Data) async {
        guard let still = draft.stills[mood],
              let animation = try? await service.animation(mood, of: subject(cutout), reference: still),
              let strip = strip(animation) else { return }
        draft.strips[mood] = strip.strip
        draft.frameCounts[mood] = strip.frames
        drafts.save(draft)
    }

    /// Every mood has its still: "Done" can save.
    var canFinish: Bool { CharacterMood.allCases.allSatisfy { draft.stills[$0] != nil } }

    /// Saves the character, every still and the animations that came, in one transaction,
    /// and shows it; the draft goes. Returns why it couldn't, if it couldn't.
    func finish(save: (_ stills: [CharacterMood: Data], _ strips: [CharacterMood: (Data, Int)]) -> String?) -> String? {
        guard canFinish else { return nil }
        var strips: [CharacterMood: (Data, Int)] = [:]
        for (mood, strip) in draft.strips { strips[mood] = (strip, draft.frameCounts[mood] ?? 1) }
        if let problem = save(draft.stills, strips) { return problem }
        drafts.discard(subject.companionId)
        work.forEach { $0.cancel() }
        step = .done
        return nil
    }

    // MARK: Resuming, discarding, leaving

    /// Picks up a drawing left mid-way: the tries to pick from, or the moods so far.
    func resume() async {
        if draft.picked != nil, draft.stills[.fine] != nil {
            step = .meeting
            drawMissing()
        } else {
            step = .picking
        }
    }

    /// Throws the drawing away: nothing of it was ever shown, and nothing is.
    func discard() {
        work.forEach { $0.cancel() }
        drafts.discard(subject.companionId)
        draft = CharacterDraft(companionId: subject.companionId, species: subject.species.rawValue, startedAt: .now)
        moodStates = [:]
        step = .cutting
    }

    /// The sheet closed: calls in flight stop; the draft stays to be resumed.
    func leave() {
        work.forEach { $0.cancel() }
        work = []
    }

    /// Back to a step's start after a failure: the consent with the same cut-out, or the
    /// moods so far.
    func recover() {
        guard case let .failed(failure) = step else { return }
        switch failure.stage {
        case .tries, .allowance:
            if let cut { step = .consent(cut) } else { step = .cutting }
        case .mood:
            step = .meeting
        }
    }
}
