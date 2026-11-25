import Foundation
import Testing
@testable import Porchlight

/// The character journey's steps on the stand-in relay (docs/design/companion-characters.md,
/// "The character journey"): nothing is sent before Draw, three tries and their rounds, the
/// moods arriving to match the try picked, animations never blocking, every failure with its
/// words, and a drawing left mid-way resumed or thrown away, never shown half done.
@MainActor
@Suite("Drawing a character")
struct CharacterDrawingTests {
    private let folder = TestFolders.make("drafts-\(UUID().uuidString)")
    private let suite = "drawing-\(UUID().uuidString)"
    private let householdId = Household.ID(UUID())
    private let companionId = Companion.ID(UUID())

    private var drafts: CharacterDraftStore { CharacterDraftStore(folder: folder) }
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    nonisolated private static let cut = PhotoSticker.Result(sticker: Data("sticker".utf8), cutout: Data("cutout".utf8), notes: [])

    private func drawing(_ service: FakeCharacterService, photo: Data? = Data("photo".utf8)) -> CharacterDrawing {
        CharacterDrawing(
            householdId: householdId, companionId: companionId, species: .dog, photo: photo,
            service: service, drafts: drafts, defaults: defaults, cutOut: { _ in Self.cut },
            strip: { animation in (Data("strip".utf8), animation.frames) }
        )
    }

    /// Waits for the moods drawn in the background to settle.
    private func settle(_ drawing: CharacterDrawing) async throws {
        for _ in 0..<200 where drawing.moodStates.values.contains(.drawing) || drawing.draft.strips.count < drawing.draft.stills.count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Cut out on the device, then consent; nothing is sent before Draw")
    func consent() async {
        let fake = FakeCharacterService()
        let drawing = drawing(fake)
        await drawing.cut()
        #expect(drawing.step == .consent(Self.cut))
        #expect(fake.calls.isEmpty, "nothing has left the device")
    }

    @Test("What the consent shows is, byte for byte, what is sent: the tries, every mood and every animation get that cut-out and nothing else")
    func shownIsSent() async throws {
        let fake = FakeCharacterService()
        let drawing = drawing(fake)
        await drawing.cut()
        guard case let .consent(shown) = drawing.step else { Issue.record("Expected the consent"); return }
        await drawing.drawTries()
        drawing.pick()
        try await settle(drawing)
        let sent = fake.calls.filter { $0.step != "allowance" }
        #expect(sent.count == 1 + 3 + 4, "the tries, three moods and four animations")
        #expect(sent.allSatisfy { $0.cutout == shown.cutout }, "each with the cut-out the consent showed")
    }

    @Test("A photo with no subject, or a device that can't cut one out, stops before anything is sent: no crop, no whole photo")
    func noCutoutSendsNothing() async {
        for failure in [PhotoSticker.Failure.noSubject, .unavailable, .unreadable] {
            let fake = FakeCharacterService()
            let drawing = CharacterDrawing(
                householdId: householdId, companionId: companionId, species: .dog, photo: Data("photo".utf8),
                service: fake, drafts: drafts, defaults: defaults, cutOut: { _ in throw failure }
            )
            await drawing.cut()
            #expect(drawing.step == .cutFailed(failure))
            await drawing.drawTries()
            #expect(drawing.step == .cutFailed(failure), "Draw can't be reached without a cut-out")
            #expect(fake.calls.isEmpty, "nothing left the device")
        }
    }

    @Test("No photo asks for one first")
    func needsPhoto() async {
        let drawing = drawing(FakeCharacterService(), photo: nil)
        await drawing.cut()
        #expect(drawing.step == .needsPhoto)
        await drawing.cut(newPhoto: Data("new".utf8))
        #expect(drawing.step == .consent(Self.cut))
        #expect(drawing.photo == Data("new".utf8))
    }

    @Test("Draw: three tries, picked, the moods drawn to match it with their animations, then saved and shown in one go")
    func happyPath() async throws {
        let fake = FakeCharacterService()
        let drawing = drawing(fake)
        await drawing.cut()
        await drawing.drawTries()
        #expect(drawing.step == .picking)
        #expect(drawing.draft.tries.count == 3 && drawing.draft.roundsLeft == 2)
        #expect(CharacterOffer.roundsLeft(companionId, defaults: defaults) == 2, "the offer knows, without asking again")
        drawing.selection = 2
        drawing.pick()
        #expect(drawing.step == .meeting)
        try await settle(drawing)
        #expect(drawing.canFinish)
        let picked = CharacterPlaceholders.variant(of: drawing.draft.tries[2])
        for mood in CharacterMood.allCases {
            #expect(CharacterPlaceholders.variant(of: try #require(drawing.draft.stills[mood])) == picked, "\(mood) matches the try picked")
            #expect(drawing.moodStates[mood] == .ready)
        }
        #expect(drawing.draft.strips.count == 4, "every mood moves")
        #expect(fake.calls.filter { $0.step == "mood" }.map(\.mood) .compactMap { $0 }.sorted { $0.rawValue < $1.rawValue } == [.asleep, .waiting, .zoomies],
                "doing fine is the try itself")

        var saved: ([CharacterMood: Data], [CharacterMood: (Data, Int)])?
        #expect(drawing.finish { stills, strips in saved = (stills, strips); return nil } == nil)
        #expect(saved?.0.count == 4 && saved?.1.count == 4 && saved?.1[.zoomies]?.1 == 9)
        #expect(drawing.step == .done)
        #expect(!CharacterDrawing.hasDraft(companionId, in: drafts), "the draft goes once it's saved")
    }

    @Test("Try again uses a round and says how many are left; after the last, none is offered")
    func rounds() async {
        let fake = FakeCharacterService()
        let drawing = drawing(fake)
        await drawing.cut()
        for left in [2, 1, 0] {
            await drawing.drawTries()
            #expect(drawing.draft.roundsLeft == left)
        }
        #expect(CharacterWords.tryAgain(roundsLeft: 2) == "None of these: try again (2 left)")
        await drawing.drawTries()
        guard case let .failed(failure) = drawing.step else { Issue.record("Expected a failure"); return }
        #expect(failure == CharacterDrawing.Failure(error: .limitReached, stage: .tries))
        #expect(CharacterWords.failure(failure, name: "Yo-Yo", roundsLeft: drawing.draft.roundsLeft) == "Yo-Yo has had all three rounds of tries.")
        #expect(CharacterOffer.roundsLeft(companionId, defaults: defaults) == 0, "and the offer stays away")
    }

    @Test("Without animations the moods still come and can be saved; the animations can come another time")
    func noAnimations() async throws {
        let drawing = drawing(FakeCharacterService(script: .noAnimations))
        await drawing.cut()
        await drawing.drawTries()
        drawing.pick()
        try await settle(drawing)
        #expect(drawing.canFinish)
        #expect(drawing.draft.strips.isEmpty)
        var strips = -1
        _ = drawing.finish { _, saved in strips = saved.count; return nil }
        #expect(strips == 0 && drawing.step == .done)
    }

    @Test("A mood that fails says so and is drawn again on a tap; Done waits for it; a failed redraw keeps the one before")
    func moodFailure() async throws {
        let fake = FakeCharacterService()
        let drawing = drawing(fake)
        await drawing.cut()
        await drawing.drawTries()
        fake.set(.unavailable)
        drawing.pick()
        try await settle(drawing)
        #expect(drawing.moodStates[.waiting] == .failed(.unavailable))
        #expect(drawing.moodStates[.fine] == .ready, "doing fine is the try itself")
        #expect(!drawing.canFinish, "Done waits for every mood's still")
        fake.set(.draws)
        drawing.redraw(.waiting)
        try await settle(drawing)
        #expect(drawing.moodStates[.waiting] == .ready)
        let before = drawing.draft.stills[.waiting]
        fake.set(.limitReached)
        drawing.redraw(.waiting)
        try await settle(drawing)
        #expect(drawing.moodStates[.waiting] == .ready && drawing.draft.stills[.waiting] == before)
    }

    /// Waits until `condition`, up to two seconds.
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("Done waits until every mood is settled, its animation come or failed: a mood whose movement is on its way still says it is drawing, and the character saved has all four")
    func doneWaitsForAnimations() async throws {
        let fake = FakeCharacterService()
        fake.animationDelay = .milliseconds(400)
        let drawing = drawing(fake)
        await drawing.cut()
        await drawing.drawTries()
        drawing.pick()
        try await until { drawing.draft.stills.count == 4 }
        #expect(drawing.draft.stills.count == 4 && drawing.draft.strips.isEmpty, "every still has come, no animation yet")
        #expect(!drawing.canFinish, "Done isn't there yet: three animations the relay is drawing would be lost")
        #expect(CharacterMood.allCases.allSatisfy { drawing.moodStates[$0] == .drawing && !drawing.isSettled($0) }, "each mood says it is still drawing")
        try await until { drawing.canFinish }
        #expect(drawing.canFinish && drawing.draft.strips.count == 4)
        var saved = -1
        #expect(drawing.finish { _, strips in saved = strips.count; return nil } == nil)
        #expect(saved == 4, "the character saved has every mood's movement")
    }

    @Test("A failed animation settles its mood: Done comes, and that mood rests on its still")
    func failedAnimationSettles() async throws {
        let drawing = drawing(FakeCharacterService(script: .noAnimations))
        await drawing.cut()
        await drawing.drawTries()
        drawing.pick()
        try await until { drawing.canFinish }
        #expect(drawing.canFinish && drawing.draft.strips.isEmpty)
        #expect(CharacterMood.allCases.allSatisfy { drawing.moodStates[$0] == .ready })
    }

    @Test("A redraw unsettles only its own mood until its new still and movement come")
    func redrawUnsettlesOneMood() async throws {
        let fake = FakeCharacterService()
        let drawing = drawing(fake)
        await drawing.cut()
        await drawing.drawTries()
        drawing.pick()
        try await until { drawing.canFinish }
        fake.animationDelay = .milliseconds(400)
        drawing.redraw(.zoomies)
        try await until { fake.calls.filter { $0.step == "mood" && $0.mood == .zoomies }.count == 2 && drawing.draft.strips[.zoomies] == nil }
        #expect(!drawing.isSettled(.zoomies) && !drawing.canFinish, "zoomies waits for its new movement")
        #expect([CharacterMood.fine, .waiting, .asleep].allSatisfy(drawing.isSettled), "the others stay settled")
        try await until { drawing.canFinish }
        #expect(drawing.canFinish && drawing.draft.strips[.zoomies] != nil)
    }

    @Test("Closed while movements are on their way, a drawing resumed draws them, and Done waits for them")
    func resumeDrawsMissingAnimations() async throws {
        let fake = FakeCharacterService()
        fake.animationDelay = .seconds(30)
        let first = drawing(fake)
        await first.cut()
        await first.drawTries()
        first.pick()
        try await until { first.draft.stills.count == 4 }
        first.leave()
        #expect(first.draft.strips.isEmpty)

        let quick = FakeCharacterService()
        let again = drawing(quick)
        #expect(again.step == .resume)
        await again.resume()
        #expect(again.step == .meeting && !again.canFinish, "the movements are drawn again, and Done waits")
        try await until { again.canFinish }
        #expect(again.draft.strips.count == 4)
        #expect(quick.calls.filter { $0.step == "animation" }.count == 4 && quick.calls.filter { $0.step == "mood" }.isEmpty, "only what was missing")
    }

    @Test("During beta the relay says one round left for good: no words state one as a count, and only the relay's own 'rounds' answer hides the offer")
    func roundsDuringBeta() async {
        #expect(CharacterWords.tryAgain(roundsLeft: 2) == "None of these: try again (2 left)")
        #expect(CharacterWords.tryAgain(roundsLeft: 1) == "None of these: try again")
        #expect(FaceWords.removeDetail(roundsLeft: 2) == "Its moods are deleted on every device. Drawing another one uses a round of tries again. 2 rounds are left.")
        #expect(FaceWords.removeDetail(roundsLeft: 1) == "Its moods are deleted on every device. Drawing another one uses a round of tries again.")
        for (reason, remembered) in [(CharacterServiceError.Reason.householdDay, nil), (.installationDay, nil), (.rounds, 0)] as [(CharacterServiceError.Reason, Int?)] {
            let suite = UserDefaults(suiteName: "rounds-\(UUID().uuidString)")!
            let drawing = CharacterDrawing(
                householdId: householdId, companionId: companionId, species: .dog, photo: Data("photo".utf8),
                service: TriesLimited(reason), drafts: drafts, defaults: suite, cutOut: { _ in Self.cut }
            )
            await drawing.cut()
            await drawing.drawTries()
            #expect(CharacterOffer.roundsLeft(companionId, defaults: suite) == remembered, "\(reason): \(String(describing: remembered)) remembered")
        }
    }

    @Test("Every failure on the tries has words and a way on; retry goes back to the consent with the same cut-out")
    func failures() async {
        let words: [(FakeCharacterService.Script, String)] = [
            (.offline, "Porchlight can't reach the internet. Yo-Yo keeps the photo; try again once you're online."),
            (.unavailable, "Drawing isn't working right now. Try again in a little while; Yo-Yo keeps the photo meanwhile."),
            (.refused, "OpenAI wouldn't draw this photo. Try another one, where Yo-Yo is clearly the subject."),
        ]
        for (script, sentence) in words {
            let drawing = drawing(FakeCharacterService(script: script))
            await drawing.cut()
            await drawing.drawTries()
            guard case let .failed(failure) = drawing.step else { Issue.record("Expected a failure for \(script)"); continue }
            #expect(CharacterWords.failure(failure, name: "Yo-Yo", roundsLeft: nil) == sentence)
            drawing.recover()
            #expect(drawing.step == .consent(Self.cut), "back to the consent, nothing lost")
        }
        let unauthenticated = CharacterDrawing.Failure(error: .unauthenticated, stage: .tries)
        #expect(CharacterWords.failure(unauthenticated, name: "Yo-Yo", roundsLeft: nil).hasPrefix("Porchlight's drawing service couldn't check this device."))
        let daily = CharacterDrawing.Failure(error: .limitReached, stage: .tries)
        #expect(CharacterWords.failure(daily, name: "Yo-Yo", roundsLeft: 2) == "Your household has drawn a lot today. Try again tomorrow.")
        #expect(CharacterWords.failure(CharacterDrawing.Failure(error: .limitReached, stage: .mood(.waiting)), name: "Yo-Yo", roundsLeft: 2)
                == "That mood has been redrawn as many times as it can be. The one before stays.")
    }

    @Test("Each reason the relay gives has its own words; with none, the step and the rounds left decide")
    func reasons() {
        func words(_ kind: CharacterServiceError.Kind, _ reason: CharacterServiceError.Reason?, stage: CharacterDrawing.Failure.Stage = .tries) -> String {
            CharacterWords.failure(CharacterDrawing.Failure(error: CharacterServiceError(kind, reason: reason), stage: stage), name: "Yo-Yo", roundsLeft: 2)
        }
        #expect(words(.limitReached, .rounds) == "Yo-Yo has had all three rounds of tries.")
        #expect(words(.limitReached, .householdDay) == "Your household has drawn a lot today. Try again tomorrow.")
        #expect(words(.limitReached, .installationDay) == "This device has drawn a lot today. Try again tomorrow, or from another device.")
        #expect(words(.limitReached, .companions).hasPrefix("Your household has characters for as many pets as it can have."))
        #expect(words(.limitReached, .moodRedraws, stage: .mood(.waiting)) == "That mood has been redrawn as many times as it can be. The one before stays.")
        #expect(words(.limitReached, .animationRedraws, stage: .mood(.waiting)).hasPrefix("That mood's movement"))
        #expect(words(.unavailable, .spendCeiling).hasPrefix("Porchlight has drawn all it can for everyone today."))
        #expect(words(.unavailable, .model).hasPrefix("OpenAI isn't drawing right now."))
        #expect(words(.unavailable, .relay).hasPrefix("Drawing isn't working right now."))
        #expect(words(.limitReached, nil) == "Your household has drawn a lot today. Try again tomorrow.", "no reason, rounds left: the day's limit")
        // Every reason has words of its own; the relay's own failure has the plain ones.
        let all = CharacterServiceError.Reason.allCases.map { words($0.kind, $0) }
        #expect(Set(all).count == all.count)
    }

    @Test("Closed mid-way, the drawing is kept on this device and resumed where it stopped, or thrown away; never shown half done")
    func resume() async throws {
        let fake = FakeCharacterService()
        let first = drawing(fake)
        await first.cut()
        await first.drawTries()
        let tries = first.draft.tries
        first.leave()
        #expect(CharacterDrawing.hasDraft(companionId, in: drafts))

        // The app opens again: the same tries to pick from, without drawing again.
        let again = drawing(fake)
        #expect(again.step == .resume)
        await again.resume()
        #expect(again.step == .picking && again.draft.tries == tries)
        #expect(fake.calls.filter { $0.step == "tries" }.count == 1)
        again.pick()
        try await settle(again)
        again.leave()

        // Opened once more after picking: back to the moods, all kept.
        let third = drawing(fake)
        await third.resume()
        #expect(third.step == .meeting && third.canFinish)

        third.discard()
        #expect(!CharacterDrawing.hasDraft(companionId, in: drafts), "thrown away, it's gone")
        #expect(drawing(fake).step == .cutting, "and the next time starts afresh")
    }
}

/// A relay that turns every round of tries down with one limit.
private struct TriesLimited: CharacterService {
    let reason: CharacterServiceError.Reason
    init(_ reason: CharacterServiceError.Reason) { self.reason = reason }
    var isConfigured: Bool { true }
    func allowance(householdId: Household.ID, companionId: Companion.ID) async throws -> Int { 1 }
    func tries(_ subject: CharacterSubject) async throws -> CharacterTries { throw CharacterServiceError(.limitReached, reason: reason) }
    func mood(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> Data { throw CharacterServiceError.unavailable }
    func animation(_ mood: CharacterMood, of subject: CharacterSubject, reference: Data) async throws -> CharacterAnimation {
        throw CharacterServiceError.unavailable
    }
}
