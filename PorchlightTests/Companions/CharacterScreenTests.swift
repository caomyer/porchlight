#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// Where the photo sticker shows on a phone, the offer, the face sheet and the sticker sheet, hosted in the unit
/// bundle (`HostedScreen`) with the sample household and pictures drawn in code
/// (`CharacterPlaceholders`): the companion page with the photo and with the sticker, the
/// offer card, the face sheet and the sticker's steps, in light, dark and at the largest text. The wall's shots
/// are `StickerTests`'.
///
/// With `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder>` each is written there as a PNG.
@Suite("The photo sticker, on the screens")
@MainActor
struct CharacterScreenTests {
    private struct Household {
        let db: AppDatabase
        let store: CompanionStore
        let me: Person
        let companionId: Companion.ID
    }

    /// The sample household, Yo-Yo with a photo, and with its sticker when `sticker`, and a
    /// character drawn in code when `character`.
    private func household(sticker: Bool, character: Bool = false) throws -> Household {
        let db = try AppDatabase.inMemory(installId: "characters")
        let made = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: made.id)
        let snapshot = try db.snapshot()
        try CompanionSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        let store = CompanionStore(database: db)
        let companionId = try #require(store.companions.first).id
        try db.writer.write { db in try CompanionPhoto(companionId: companionId, image: CharacterPlaceholders.photo()).upsert(db) }
        if sticker {
            try db.saveSticker(try #require(CharacterPlaceholders.sticker()), companionId: companionId, by: nil)
        }
        if character {
            // A stand-in drawn in code: the sticker itself, in every mood.
            let still = try #require(CharacterPlaceholders.sticker())
            try db.writer.write { db in
                try AppDatabase.replace(.character, of: companionId, with: CharacterMood.allCases.map {
                    CharacterImage(companionId: companionId, source: .character, mood: $0, image: still)
                }, db: db)
            }
            try db.chooseFace(.character, companionId: companionId, by: nil)
        }
        return Household(db: db, store: CompanionStore(database: db), me: snapshot.people[0], companionId: companionId)
    }

    private func whole(_ screen: HostedScreen, _ name: String, size: CGSize = HostedScreen.size, least: Int = 4) {
        #expect(screen.elements.count >= least, "\(name) was read:\n\(screen.listing)")
        for element in screen.elements {
            #expect(element.frame.minX >= 0 && element.frame.maxX <= size.width, "\(element.label.prefix(40)) is whole across \(name): \(element.frame)")
        }
    }

    @Test("The companion page shows the sticker once made, and always has its quiet link to the face", arguments: ["light", "dark", "largest"])
    func page(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        for sticker in [false, true] {
            let home = try household(sticker: sticker)
            let toasts = ToastCenter()
            let screen = PocketCompanionWeek(
                companionId: home.companionId,
                logging: PocketLogging(companions: home.store, home: HomeStore(database: home.db), toasts: toasts, me: home.me.id)
            )
            .environment(home.store).environment(toasts).environment(PhotoImages(database: home.db)).environment(\.me, home.me)
            let hosted = try await HostedScreen.host(screen, look: look)
            let name = "face-page-\(sticker ? "sticker" : "photo")-\(look.name)"
            try hosted.saveShot(name)
            whole(hosted, name)
            #expect(hosted.elements.contains { $0.isButton && $0.label == CharacterOffer.change("Yo-Yo") }, "\(hosted.listing)")
            #expect(hosted.element(beginningWith: CharacterOffer.title("Yo-Yo")) == nil, "no offer while this build can't draw")
        }
    }

    @Test("The offer card asks for a photo first, then offers to draw, with its close control", arguments: ["light", "dark", "largest"])
    func offerCard(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        for card in [CharacterOffer.Card.needsPhoto, .draw] {
            let screen = ScrollView {
                CharacterOfferCard(name: "Yo-Yo", card: card) {} dismiss: {}
                    .padding(16)
            }
            .background(Theme.background)
            let hosted = try await HostedScreen.host(screen, look: look)
            let name = "character-offer-\(card == .draw ? "draw" : "photo-first")-\(look.name)"
            try hosted.saveShot(name)
            whole(hosted, name, least: 3)
            #expect(hosted.elements.contains { $0.isButton && $0.label == "Close" }, "\(hosted.listing)")
            #expect(hosted.elements.contains { $0.isButton && $0.label == (card == .draw ? CharacterOffer.draw("Yo-Yo") : CharacterOffer.addPhoto) })
        }
    }

    @Test("The face sheet lists the faces there are, the one showing ticked, and removing a character is there only once one is", arguments: ["light", "dark", "largest"])
    func faceSheet(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        for (state, sticker, character) in [("photo", false, false), ("sticker", true, false), ("character", true, true)] {
            let home = try household(sticker: sticker, character: character)
            let screen = PhoneSheet(title: FaceWords.title("Yo-Yo")) {
                FaceSheetContent(companionId: home.companionId, name: "Yo-Yo", personId: home.me.id) {}
            } footer: {
                EmptyView()
            }
            .background(Theme.surface)
            .environment(home.store).environment(PhotoImages(database: home.db))
            let hosted = try await HostedScreen.host(screen, look: look)
            let name = "face-sheet-\(state)-\(look.name)"
            try hosted.saveShot(name)
            whole(hosted, name)
            let labels = hosted.elements.filter(\.isButton).map(\.label)
            #expect(labels.contains("Photo") && labels.contains("Drawn face"), "\(hosted.listing)")
            #expect(labels.contains("Photo sticker") == sticker)
            #expect(labels.contains("Character") == character)
            #expect(labels.contains(FaceWords.removeCharacter) == character)
            #expect(labels.contains(sticker ? FaceWords.newSticker : FaceWords.makeSticker))
        }
    }

    @Test(
        "The character journey, each step: consent, drawing, picking, meeting the moods, a failure, and a drawing left mid-way",
        arguments: ["light", "dark", "largest"]
    )
    func journey(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let folder = TestFolders.make("journey-\(UUID().uuidString)")
        let drafts = CharacterDraftStore(folder: folder)
        let cutout = try #require(CharacterPlaceholders.sticker())
        let cut = PhotoSticker.Result(sticker: cutout, cutout: cutout, notes: [])
        for step in ["consent", "drawing", "picking", "meeting", "failed", "resume"] {
            let home = try household(sticker: false)
            let householdId = try #require(home.store.snapshot.household?.id)
            let fake = FakeCharacterService(script: step == "failed" ? .refused : .draws, delay: step == "drawing" ? .seconds(60) : .zero)
            func model() -> CharacterDrawing {
                CharacterDrawing(
                    householdId: householdId, companionId: home.companionId, species: .dog, photo: CharacterPlaceholders.photo(),
                    service: fake, drafts: drafts, cutOut: { _ in cut }, strip: { _ in nil }
                )
            }
            var drawing = model()
            await drawing.cut()
            switch step {
            case "drawing": Task { await drawing.drawTries() }; try await Task.sleep(for: .milliseconds(50))
            case "picking": await drawing.drawTries(); drawing.selection = 1
            case "meeting":
                await drawing.drawTries()
                drawing.pick()
                for _ in 0..<100 where !drawing.canFinish { try await Task.sleep(for: .milliseconds(10)) }
            case "failed": await drawing.drawTries()
            case "resume":
                await drawing.drawTries()
                drawing.leave()
                drawing = model()
            default: break
            }
            let screen = PhoneSheet(title: FaceWords.title("Yo-Yo")) {
                CharacterJourneyContent(
                    companionId: home.companionId, name: "Yo-Yo", personId: home.me.id, service: fake, drafts: drafts, prepared: drawing
                ) {} close: {}
            } footer: {
                EmptyView()
            }
            .background(Theme.surface)
            .environment(home.store).environment(PhotoImages(database: home.db))
            let hosted = try await HostedScreen.host(screen, look: look)
            let name = "character-\(step)-\(look.name)"
            try hosted.saveShot(name)
            whole(hosted, name, least: 3)
            let texts = hosted.elements.map(\.label)
            switch step {
            case "consent":
                #expect(texts.contains(CharacterWords.consent("Yo-Yo", device: "phone")), "\(hosted.listing)")
                #expect(texts.contains(CharacterWords.draw("Yo-Yo")) && texts.contains(CharacterWords.keepSticker(device: "phone")))
            case "drawing": #expect(texts.contains(CharacterWords.drawing("Yo-Yo")), "\(hosted.listing)")
            case "picking": #expect(texts.contains(CharacterWords.thisOne) && texts.contains(CharacterWords.tryAgain(roundsLeft: 2)), "\(hosted.listing)")
            case "meeting":
                #expect(texts.contains(CharacterWords.meetTitle("Yo-Yo")), "\(hosted.listing)")
                #expect(CharacterMood.allCases.allSatisfy { mood in texts.contains { $0.hasPrefix(mood.label) } })
            case "failed": #expect(texts.contains { $0.hasPrefix("OpenAI wouldn't draw this photo.") }, "\(hosted.listing)")
            default: #expect(texts.contains(CharacterWords.finish) && texts.contains(CharacterWords.throwAway), "\(hosted.listing)")
            }
            drawing.leave()
        }
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("The sheet: cutting, the sticker beside its photo with its notes, and a photo with no subject", arguments: ["light", "dark", "largest"])
    func sheet(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let sticker = try #require(CharacterPlaceholders.sticker())
        let steps: [(String, @Sendable (Data) async throws -> PhotoSticker.Result)] = [
            ("cutting", { _ in try await Task.sleep(for: .seconds(60)); throw PhotoSticker.Failure.unavailable }),
            ("ready", { _ in PhotoSticker.Result(sticker: sticker, cutout: Data(), notes: [.cutByEdge]) }),
            ("no-subject", { _ in throw PhotoSticker.Failure.noSubject }),
        ]
        for (step, cut) in steps {
            let home = try household(sticker: false)
            let screen = PhoneSheet(title: StickerWords.title("Yo-Yo")) {
                StickerSheetContent(companionId: home.companionId, name: "Yo-Yo", personId: home.me.id, cut: cut) {}
            } footer: {
                EmptyView()
            }
            .background(Theme.surface)
            .environment(home.store).environment(PhotoImages(database: home.db))
            let hosted = try await HostedScreen.host(screen, look: look)
            let name = "sticker-sheet-\(step)-\(look.name)"
            try hosted.saveShot(name)
            whole(hosted, name)
            switch step {
            case "ready":
                #expect(hosted.elements.contains { $0.label == StickerWords.use }, "\(hosted.listing)")
                #expect(hosted.element(beginningWith: "Part of Yo-Yo is outside the photo") != nil)
                #expect(hosted.element(beginningWith: StickerWords.made("Yo-Yo", device: "phone")) != nil)
            case "no-subject":
                #expect(hosted.element(beginningWith: "Porchlight couldn't find Yo-Yo") != nil, "\(hosted.listing)")
                #expect(!hosted.elements.contains { $0.label == StickerWords.use })
            default:
                #expect(hosted.element(beginningWith: StickerWords.cutting("Yo-Yo")) != nil, "\(hosted.listing)")
            }
        }
    }
}
#endif
