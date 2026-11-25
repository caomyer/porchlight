import PhotosUI
import SwiftUI

/// What the character journey says (docs/design/companion-characters.md, "The character
/// journey"), in one place for the screens and their tests.
enum CharacterWords {
    static let consentTitle = "This is what we'll send"

    static func consent(_ name: String, device: String) -> String {
        "Only the cut-out of \(name) goes to OpenAI to be drawn. The rest of the photo stays on this \(device). OpenAI doesn't train on it and deletes it within 30 days."
    }

    static func draw(_ name: String) -> String { "Draw \(name)" }
    static func keepSticker(device: String) -> String { "Keep it on this \(device): use the photo sticker" }
    static let another = "Choose another photo"

    static func drawing(_ name: String) -> String { "Drawing \(name)" }
    static let drawingNote = "It takes about half a minute, sometimes more. Keep this open while it draws."

    static func pickTitle(_ name: String) -> String { "Which one is most \(name)?" }
    static let pickNote = "Three tries from the same photo. Pick one, and the moods are drawn to match it."
    static let thisOne = "This one"

    /// The count only above one: during beta testing the relay counts rounds without
    /// enforcing them and says 1 from then on, so "1 left" would be untrue for good.
    static func tryAgain(roundsLeft: Int) -> String { roundsLeft > 1 ? "None of these: try again (\(roundsLeft) left)" : "None of these: try again" }
    static func noTriesLeft(_ name: String) -> String { "No more tries for \(name). Pick the closest; any mood can be redrawn on its own." }

    static func meetTitle(_ name: String) -> String { "Meet \(name)" }
    static let meetNote = "Tap a mood to redraw just that one."
    static let done = "Done"

    static func moodNote(_ mood: CharacterMood) -> String {
        switch mood {
        case .fine: "blinks, wags now and then"
        case .waiting: "a walk or meal is due"
        case .zoomies: "just back from a walk"
        case .asleep: "all done, or night"
        }
    }

    static let moodDrawing = "Drawing..."
    static let moodFailed = "Couldn't draw this one. Tap to try again."

    static func resumeTitle(_ name: String) -> String { "Finish drawing \(name)?" }

    static func resume(_ name: String) -> String {
        "A drawing of \(name) was left part way. Pick up where it stopped, or throw it away; nothing of it shows until it's done."
    }

    static let finish = "Finish drawing"
    static let throwAway = "Throw it away"
    static let retry = "Try again"
    static let close = "Close"

    /// What went wrong, in words a person can act on. The relay doesn't say which limit was
    /// reached, so the step and the rounds left from its last answer tell them apart.
    static func failure(_ failure: CharacterDrawing.Failure, name: String, roundsLeft: Int?) -> String {
        switch failure.error.kind {
        case .offline:
            "Porchlight can't reach the internet. \(name) keeps the photo; try again once you're online."
        case .unavailable:
            switch failure.error.reason {
            case .spendCeiling?:
                "Porchlight has drawn all it can for everyone today. Try again tomorrow; \(name) keeps the photo meanwhile."
            case .model?:
                "OpenAI isn't drawing right now. Try again in a little while; \(name) keeps the photo meanwhile."
            default:
                "Drawing isn't working right now. Try again in a little while; \(name) keeps the photo meanwhile."
            }
        case .refused:
            "OpenAI wouldn't draw this photo. Try another one, where \(name) is clearly the subject."
        case .unauthenticated:
            "Porchlight's drawing service couldn't check this device. Try again later, or draw \(name) from another device."
        case .invalid:
            "Something went wrong in Porchlight, not on your side. Try again; if it keeps happening, tell us."
        case .limitReached:
            switch failure.error.reason {
            case .rounds?: "\(name) has had all three rounds of tries."
            case .moodRedraws?: "That mood has been redrawn as many times as it can be. The one before stays."
            case .animationRedraws?: "That mood's movement has been redrawn as many times as it can be. It stays as it is."
            case .companions?: "Your household has characters for as many pets as it can have. A photo sticker is always free."
            case .householdDay?: "Your household has drawn a lot today. Try again tomorrow."
            case .installationDay?: "This device has drawn a lot today. Try again tomorrow, or from another device."
            default:
                // No reason given: the step and the rounds last reported tell the limits apart.
                switch failure.stage {
                case .mood: "That mood has been redrawn as many times as it can be. The one before stays."
                case .tries, .allowance:
                    roundsLeft.map { $0 > 0 } == true
                        ? "Your household has drawn a lot today. Try again tomorrow."
                        : "\(name) has had all three rounds of tries."
                }
            }
        }
    }
}

/// The character journey, inside the face sheet: consent, drawing, picking from three, and
/// meeting the four moods; a drawing left mid-way is resumed or thrown away.
struct CharacterJourneyContent: View {
    let companionId: Companion.ID
    let name: String
    let personId: Person.ID?
    /// A photo to draw from instead of the saved one.
    var photo: Data?
    var service: any CharacterService = CharacterServices.current
    var drafts: CharacterDraftStore = .standard
    var cutOut: @Sendable (Data) async throws -> PhotoSticker.Result = { try await PhotoSticker.make(from: $0) }
    /// A journey already under way, for previews and review shots of each step.
    var prepared: CharacterDrawing?
    /// The free path: the sticker sheet with this cut-out.
    let useSticker: () -> Void
    let close: () -> Void

    @Environment(CompanionStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var drawing: CharacterDrawing?
    @State private var picked: PhotosPickerItem?
    @State private var saveError: String?

    private var device: String { sizeClass == .compact ? "phone" : "iPad" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let drawing {
                content(drawing)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .task {
            if drawing == nil, let prepared {
                drawing = prepared
                return
            }
            guard drawing == nil, let companion = store.snapshot.companions.first(where: { $0.id == companionId }),
                  let householdId = store.snapshot.household?.id, let species = CharacterSpecies(companion.species) else { return }
            let model = CharacterDrawing(
                householdId: householdId, companionId: companionId, species: species, photo: photo ?? store.photo(of: companionId),
                service: service, drafts: drafts, cutOut: cutOut
            )
            drawing = model
            if model.step == .cutting { await model.cut() }
        }
        .onDisappear { drawing?.leave() }
        .onChange(of: picked) { _, item in
            guard let item, let drawing else { return }
            picked = nil
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let photo = try? await Task.detached { try data.map(CompanionPhotos.prepared) }.value
                await drawing.cut(newPhoto: photo ?? Data())
            }
        }
        .onChange(of: drawing?.step) { _, step in
            if step == .done { close() }
        }
    }

    @ViewBuilder
    private func content(_ drawing: CharacterDrawing) -> some View {
        switch drawing.step {
        case .resume:
            heading(CharacterWords.resumeTitle(name))
            note(CharacterWords.resume(name))
            Button(CharacterWords.finish) { Task { await drawing.resume() } }
                .buttonStyle(PhoneButtonStyle())
                .accessibilityIdentifier("character-finish")
            Button(CharacterWords.throwAway) { drawing.discard(); Task { await drawing.cut() } }
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
                .accessibilityIdentifier("character-discard")
        case .needsPhoto:
            note(CharacterOffer.needsPhoto(name))
            picker(primary: true)
            Button(CharacterWords.close, action: close).buttonStyle(PhoneButtonStyle(kind: .ghost))
        case .cutting:
            pair(drawing, cutout: nil)
            note(StickerWords.cutting(name))
        case let .consent(result):
            heading(CharacterWords.consentTitle)
            pair(drawing, cutout: result.cutout)
            note(CharacterWords.consent(name, device: device))
            Button(CharacterWords.draw(name)) { Task { await drawing.drawTries() } }
                .buttonStyle(PhoneButtonStyle())
                .accessibilityIdentifier("character-draw")
            Button(CharacterWords.keepSticker(device: device), action: useSticker)
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
                .accessibilityIdentifier("character-use-sticker")
            picker(primary: false)
        case let .cutFailed(failure):
            pair(drawing, cutout: nil)
            note(StickerWords.failure(failure, name: name, device: device), muted: false)
            picker(primary: true)
            Button(CharacterWords.close, action: close).buttonStyle(PhoneButtonStyle(kind: .ghost))
        case .drawingTries:
            heading(CharacterWords.drawing(name))
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.surface2)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { ProgressView() }
                }
            }
            note(CharacterWords.drawingNote)
                .accessibilityIdentifier("character-drawing")
        case .picking:
            picking(drawing)
        case .meeting:
            meeting(drawing)
        case let .failed(failure):
            heading(CharacterWords.drawing(name))
            note(CharacterWords.failure(failure, name: name, roundsLeft: drawing.draft.roundsLeft), muted: false)
                .accessibilityIdentifier("character-failed")
            failureWays(drawing, failure)
        case .done:
            EmptyView()
        }
    }

    private func picking(_ drawing: CharacterDrawing) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(CharacterWords.pickTitle(name))
            HStack(spacing: 10) {
                ForEach(Array(drawing.draft.tries.enumerated()), id: \.offset) { index, image in
                    let isOn = drawing.selection == index
                    Button { drawing.selection = index } label: {
                        picture(image)
                            .padding(6)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isOn ? Theme.accent : .clear, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Try \(index + 1)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("character-try-\(index)")
                }
            }
            note(CharacterWords.pickNote)
            Button(CharacterWords.thisOne) { drawing.pick() }
                .buttonStyle(PhoneButtonStyle())
                .accessibilityIdentifier("character-pick")
            if let left = drawing.draft.roundsLeft, left > 0 {
                Button(CharacterWords.tryAgain(roundsLeft: left)) { Task { await drawing.drawTries() } }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
                    .accessibilityIdentifier("character-try-again")
            } else {
                note(CharacterWords.noTriesLeft(name))
            }
        }
    }

    private func meeting(_ drawing: CharacterDrawing) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(CharacterWords.meetTitle(name))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(CharacterMood.allCases, id: \.self) { mood in
                    moodTile(drawing, mood)
                }
            }
            note(CharacterWords.meetNote)
            if let saveError { note(saveError, muted: false) }
            Button(CharacterWords.done) {
                saveError = drawing.finish { stills, strips in
                    store.useCharacter(stills: stills, strips: strips, for: companionId, by: personId)
                }
            }
            .buttonStyle(PhoneButtonStyle())
            .disabled(!drawing.canFinish)
            .accessibilityIdentifier("character-done")
        }
    }

    private func moodTile(_ drawing: CharacterDrawing, _ mood: CharacterMood) -> some View {
        let state = drawing.moodStates[mood]
        return Button { drawing.redraw(mood) } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let still = drawing.draft.stills[mood] {
                        picture(still).opacity(state == .drawing ? 0.35 : 1)
                    }
                    if state == .drawing { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                Text(mood.label)
                    .phoneFont(.body, 14, weight: 800, relativeTo: .subheadline)
                    .foregroundStyle(Theme.ink)
                Text(stateNote(state, mood))
                    .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        // Doing fine is the try itself and isn't redrawn, but it looks like the others.
        .allowsHitTesting(mood != .fine && state != .drawing)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("character-mood-\(mood.rawValue)")
    }

    private func stateNote(_ state: CharacterDrawing.MoodState?, _ mood: CharacterMood) -> String {
        switch state {
        case .drawing?: CharacterWords.moodDrawing
        case .failed?: CharacterWords.moodFailed
        default: CharacterWords.moodNote(mood)
        }
    }

    @ViewBuilder
    private func failureWays(_ drawing: CharacterDrawing, _ failure: CharacterDrawing.Failure) -> some View {
        switch failure.error.kind {
        case .refused:
            picker(primary: true)
            Button(CharacterWords.keepSticker(device: device), action: useSticker).buttonStyle(PhoneButtonStyle(kind: .ghost))
        case .limitReached where failure.stage != .tries || (drawing.draft.roundsLeft ?? 0) == 0:
            Button(CharacterWords.keepSticker(device: device), action: useSticker).buttonStyle(PhoneButtonStyle())
            Button(CharacterWords.close, action: close).buttonStyle(PhoneButtonStyle(kind: .ghost))
        default:
            Button(CharacterWords.retry) { drawing.recover() }
                .buttonStyle(PhoneButtonStyle())
                .accessibilityIdentifier("character-retry")
            Button(CharacterWords.keepSticker(device: device), action: useSticker).buttonStyle(PhoneButtonStyle(kind: .ghost))
        }
    }

    // MARK: Pieces

    /// A step's heading, under the sheet's own title.
    private func heading(_ text: String) -> some View {
        Text(text)
            .phoneFont(.body, 17, weight: 800, relativeTo: .headline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: String, muted: Bool = true) -> some View {
        Text(text)
            .phoneFont(.body, 14, weight: 600, relativeTo: .subheadline)
            .foregroundStyle(muted ? Theme.muted : Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func picture(_ data: Data) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Color.clear
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The photo and its cut-out, side by side: what stays, and what is sent.
    private func pair(_ drawing: CharacterDrawing, cutout: Data?) -> some View {
        HStack(spacing: 12) {
            if let photo = drawing.photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("The photo of \(name), which stays here")
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface2)
                if let cutout, let image = UIImage(data: cutout) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .accessibilityLabel("The cut-out of \(name), which is sent")
                        .accessibilityIdentifier("character-cutout")
                } else if drawing.step == .cutting {
                    ProgressView()
                }
            }
            .frame(width: 128, height: 128)
        }
        .frame(maxWidth: .infinity)
    }

    private func picker(primary: Bool) -> some View {
        PhotosPicker(selection: $picked, matching: .images) {
            Text(CharacterWords.another).frame(maxWidth: .infinity)
        }
        .buttonStyle(PhoneButtonStyle(kind: primary ? .primary : .ghost))
        .accessibilityIdentifier("character-photo")
    }
}
