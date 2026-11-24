import SwiftUI

/// Whether drawing a character can be offered here at all.
enum CharacterAvailability: Equatable, Sendable {
    /// No relay to draw with: no Firebase configuration in this build.
    case unavailable
    /// The relay is there; rounds left for this companion, nil until the allowance answers.
    case available(roundsLeft: Int?)
}

/// The offer card on a companion's page, "Give Yo-Yo a character"
/// (docs/design/companion-characters.md, "The offer").
enum CharacterOffer {
    enum Card: Equatable {
        case hidden
        /// No photo yet: the card asks for one first.
        case needsPhoto
        case draw
    }

    /// One rule for every screen. Shown only for species drawn so far, while the feature can
    /// draw, and until this device dismissed it for this companion; it goes by itself once the
    /// companion has a character or a photo sticker, or while one is being drawn.
    static func card(
        species: Species, look: CharacterLook?, hasPhoto: Bool, isDrawing: Bool, dismissed: Bool,
        availability: CharacterAvailability
    ) -> Card {
        guard species.isDrawnAsCharacter, !dismissed, !isDrawing else { return .hidden }
        guard look?.hasCharacter != true, look?.hasSticker != true else { return .hidden }
        guard case let .available(roundsLeft) = availability, roundsLeft != 0 else { return .hidden }
        return hasPhoto ? .draw : .needsPhoto
    }

    private static func key(_ companionId: Companion.ID) -> String { "characterOffer.dismissed.\(companionId)" }

    /// Per device and per companion, never synced, like the catch-up banner's.
    static func isDismissed(_ companionId: Companion.ID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(companionId))
    }

    static func dismiss(_ companionId: Companion.ID, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(companionId))
    }

    /// The rounds of tries the relay last said were left for a companion, on this device: the
    /// offer reads it instead of asking the relay, which is never called before Draw.
    static func roundsLeft(_ companionId: Companion.ID, defaults: UserDefaults = .standard) -> Int? {
        defaults.object(forKey: "characterRounds.\(companionId)") as? Int
    }

    static func remember(roundsLeft: Int, for companionId: Companion.ID, defaults: UserDefaults = .standard) {
        defaults.set(roundsLeft, forKey: "characterRounds.\(companionId)")
    }

    static func title(_ name: String) -> String { "Give \(name) a character" }

    static func pitch(_ name: String) -> String {
        "Turn a photo into a little drawing of \(name) that naps, waits by the door and gets the zoomies with the day."
    }

    static func needsPhoto(_ name: String) -> String { "Add a photo of \(name) first, and Porchlight draws \(name) from it." }

    static func draw(_ name: String) -> String { "Draw \(name)" }
    static let addPhoto = "Add a photo"

    /// The page's quiet link to the face choice.
    static func change(_ name: String) -> String { "Change \(name.possessive) character or photo" }
}

extension Species {
    /// Dogs and cats first; other species keep today's faces until they are tested.
    var isDrawnAsCharacter: Bool { self == .dog || self == .cat }
}

/// The offer on the phone's companion page, under the hero, with a close control.
struct CharacterOfferCard: View {
    let name: String
    let card: CharacterOffer.Card
    let act: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CharacterOffer.title(name))
                    .phoneFont(.body, 16, weight: 800, relativeTo: .headline)
                    .accessibilityAddTraits(.isHeader)
                Text("new")
                    .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("dismiss-character-offer")
            }
            Text(card == .needsPhoto ? CharacterOffer.needsPhoto(name) : CharacterOffer.pitch(name))
                .phoneFont(.body, 13.5, weight: 600, relativeTo: .subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(card == .needsPhoto ? CharacterOffer.addPhoto : CharacterOffer.draw(name), action: act)
                .buttonStyle(PhoneButtonStyle())
                .accessibilityIdentifier("character-offer")
        }
        .phoneCard()
    }
}

/// The wall's quiet link to the face choice, under the companion's name in its hero.
struct FaceLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body(13, weight: 700))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("change-face")
    }
}
