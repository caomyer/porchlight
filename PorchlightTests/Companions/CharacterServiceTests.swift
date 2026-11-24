import Foundation
import ImageIO
import Testing
import UIKit
@testable import Porchlight

/// The relay's contract as the app reads it (docs/design/companion-characters.md, "The
/// relay"): its error codes, and the stand-in every test and preview draws with.
@Suite("The character service")
struct CharacterServiceTests {
    private static let subject = CharacterSubject(
        householdId: Household.ID(UUID()), companionId: Companion.ID(UUID()), species: .dog, cutout: Data("cutout".utf8)
    )

    @Test("Each code in the relay's details is its error; an unknown or missing one is unavailable")
    func codes() {
        #expect(CharacterServiceError(code: "limit-reached") == .limitReached)
        #expect(CharacterServiceError(code: "refused") == .refused)
        #expect(CharacterServiceError(code: "unavailable") == .unavailable)
        #expect(CharacterServiceError(code: "unauthenticated") == .unauthenticated)
        #expect(CharacterServiceError(code: "invalid") == .invalid)
        #expect(CharacterServiceError(code: "teapot") == .unavailable)
        #expect(CharacterServiceError(code: nil) == .unavailable)
    }

    @Test("Only dogs and cats are drawn")
    func species() {
        #expect(CharacterSpecies(.dog) == .dog && CharacterSpecies(.cat) == .cat)
        for other in [Species.bird, .rabbit, .fish, .plant, .other] { #expect(CharacterSpecies(other) == nil) }
    }

    @Test("A build with no relay says so and draws nothing")
    func unconfigured() async {
        let service = UnconfiguredCharacterService()
        #expect(!service.isConfigured)
        await #expect(throws: CharacterServiceError.unavailable) { try await service.tries(Self.subject) }
    }

    @Test("The stand-in draws three different tries a round, three rounds a companion, then no more")
    func tries() async throws {
        let fake = FakeCharacterService()
        #expect(try await fake.allowance(householdId: Self.subject.householdId, companionId: Self.subject.companionId) == 3)
        var seen: Set<Int> = []
        for left in [2, 1, 0] {
            let tries = try await fake.tries(Self.subject)
            #expect(tries.images.count == 3 && tries.roundsLeft == left)
            for image in tries.images {
                let png = try #require(UIImage(data: image)?.cgImage)
                #expect(png.width == CharacterImage.stillSide && png.height == CharacterImage.stillSide)
                seen.insert(try #require(CharacterPlaceholders.variant(of: image)))
            }
        }
        #expect(seen.count == 9, "every try looks different")
        await #expect(throws: CharacterServiceError.limitReached) { try await fake.tries(Self.subject) }
        #expect(try await fake.allowance(householdId: Self.subject.householdId, companionId: Self.subject.companionId) == 0)
        #expect(fake.calls.filter { $0.step == "tries" }.count == 4)
    }

    @Test("Moods match the try they were drawn from; an animation is nine frames; without animations the stills still come")
    func moods() async throws {
        let fake = FakeCharacterService()
        let chosen = try #require(try await fake.tries(Self.subject).images.last)
        let variant = CharacterPlaceholders.variant(of: chosen)
        for mood in CharacterMood.allCases {
            let still = try await fake.mood(mood, of: Self.subject, reference: chosen)
            #expect(CharacterPlaceholders.variant(of: still) == variant, "\(mood) matches the try")
        }
        let animation = try await fake.animation(.zoomies, of: Self.subject, reference: chosen)
        let source = try #require(CGImageSourceCreateWithData(animation.gif as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 9 && animation.frames == 9)

        fake.set(.noAnimations)
        #expect(try await !fake.mood(.asleep, of: Self.subject, reference: chosen).isEmpty)
        await #expect(throws: CharacterServiceError.unavailable) { try await fake.animation(.asleep, of: Self.subject, reference: chosen) }
        for (script, error) in [(FakeCharacterService.Script.refused, CharacterServiceError.refused), (.offline, .offline), (.unavailable, .unavailable)] {
            fake.set(script)
            await #expect(throws: error) { try await fake.tries(Self.subject) }
        }
    }
}
