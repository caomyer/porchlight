import PhotosUI
import SwiftUI

// Making a companion's photo sticker: cut out on this device from its photo (or another
// one picked here), shown beside the photo it came from, and used in place of the photo
// wherever the companion shows (docs/design/companion-characters.md, "The photo sticker").

/// The steps of making a sticker, apart from any screen, so each can be tested.
@MainActor
@Observable
final class StickerMaking {
    enum Step: Equatable {
        /// The companion has no photo yet: pick one.
        case needsPhoto
        case cutting
        case ready(PhotoSticker.Result)
        case failed(PhotoSticker.Failure)
        /// Saved; the sheet closes.
        case done
    }

    private(set) var step: Step
    /// The photo the sticker is cut from, and whether it was picked here rather than saved.
    private(set) var photo: Data?
    private(set) var isNewPhoto = false
    /// Why saving didn't work, if it didn't.
    private(set) var saveError: String?

    @ObservationIgnored private let cut: @Sendable (Data) async throws -> PhotoSticker.Result
    /// Each cut gets a number, so a slow one that finishes after another photo was picked is dropped.
    @ObservationIgnored private var attempt = 0

    init(photo: Data?, cut: @escaping @Sendable (Data) async throws -> PhotoSticker.Result = { try await PhotoSticker.make(from: $0) }) {
        self.photo = photo
        self.cut = cut
        step = photo == nil ? .needsPhoto : .cutting
    }

    /// Cuts the subject out of the companion's own photo, or one just picked.
    func start(with newPhoto: Data? = nil) async {
        if let newPhoto {
            photo = newPhoto
            isNewPhoto = true
        }
        guard let photo else {
            step = .needsPhoto
            return
        }
        attempt += 1
        let mine = attempt
        step = .cutting
        let outcome: Step
        do {
            outcome = .ready(try await cut(photo))
        } catch let failure as PhotoSticker.Failure {
            outcome = .failed(failure)
        } catch {
            outcome = .failed(.unavailable)
        }
        guard mine == attempt else { return }
        step = outcome
    }

    /// Saves the sticker, and the photo it came from when it was picked here.
    func use(save: (_ sticker: Data, _ photo: Data?) -> String?) {
        guard case let .ready(result) = step else { return }
        if let problem = save(result.sticker, isNewPhoto ? photo : nil) {
            saveError = problem
        } else {
            saveError = nil
            step = .done
        }
    }
}

/// What the sticker sheet says, in one place for the screen and its tests.
enum StickerWords {
    static func title(_ name: String) -> String { "A sticker of \(name)" }

    static func made(_ name: String, device: String) -> String {
        "Porchlight cut \(name) out of the photo on this \(device). Nothing is sent anywhere."
    }

    static func cutting(_ name: String) -> String { "Cutting \(name) out of the photo..." }

    static func note(_ note: PhotoSticker.Note, name: String) -> String {
        switch note {
        case .severalSubjects: "There's more than one subject in this photo, so Porchlight used the biggest."
        case .cutByEdge: "Part of \(name) is outside the photo, so the sticker is cut off there too."
        }
    }

    static func failure(_ failure: PhotoSticker.Failure, name: String, device: String) -> String {
        switch failure {
        case .noSubject: "Porchlight couldn't find \(name) in this photo. Try one where \(name) stands out from the background."
        case .unavailable: "This \(device) can't cut a photo out, so \(name) keeps the photo. A phone can make the sticker, and it shows here too."
        case .unreadable: "That photo couldn't be read. Try another one."
        }
    }

    static func needsPhoto(_ name: String) -> String { "Pick a photo of \(name), and Porchlight cuts \(name) out of it on this device." }

    static let use = "Use the photo sticker"
    static let another = "Choose another photo"
    static let pick = "Choose a photo"
    static let notNow = "Not now"
}

/// The sticker sheet's content, the same on the phone and the wall.
struct StickerSheetContent: View {
    let companionId: Companion.ID
    let name: String
    /// Who is making it, on a personal device.
    let personId: Person.ID?
    /// How the subject is cut out: on the device, or a stand-in in previews and tests.
    var cut: @Sendable (Data) async throws -> PhotoSticker.Result = { try await PhotoSticker.make(from: $0) }
    let close: () -> Void

    @Environment(CompanionStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var making: StickerMaking?
    @State private var picked: PhotosPickerItem?

    private var device: String { sizeClass == .compact ? "phone" : "iPad" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let making {
                content(making)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .task {
            guard making == nil else { return }
            let model = StickerMaking(photo: store.photo(of: companionId), cut: cut)
            making = model
            await model.start()
        }
        .onChange(of: picked) { _, item in
            guard let item, let making else { return }
            picked = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let photo = try? await Task.detached(priority: .userInitiated, operation: { try CompanionPhotos.prepared(data) }).value
                else {
                    await making.start(with: Data())
                    return
                }
                await making.start(with: photo)
            }
        }
        .onChange(of: making?.step) { _, step in
            if step == .done { close() }
        }
    }

    @ViewBuilder
    private func content(_ making: StickerMaking) -> some View {
        switch making.step {
        case .needsPhoto:
            Text(StickerWords.needsPhoto(name)).modifier(SheetText())
            picker(StickerWords.pick, primary: true)
            notNow
        case .cutting:
            pair(making, sticker: nil)
            Text(StickerWords.cutting(name)).modifier(SheetText())
                .accessibilityIdentifier("sticker-cutting")
            notNow
        case let .ready(result):
            pair(making, sticker: result.sticker)
            Text(StickerWords.made(name, device: device)).modifier(SheetText())
            ForEach(result.notes.sorted { "\($0)" < "\($1)" }, id: \.self) { note in
                Text(StickerWords.note(note, name: name)).modifier(SheetText(muted: false))
            }
            if let problem = making.saveError {
                Text(problem).modifier(SheetText(muted: false)).foregroundStyle(Theme.accent)
            }
            Button(StickerWords.use) {
                making.use { sticker, photo in store.useSticker(sticker, photo: photo, for: companionId, by: personId) }
            }
            .buttonStyle(PhoneButtonStyle())
            .accessibilityIdentifier("use-sticker")
            picker(StickerWords.another, primary: false)
        case let .failed(failure):
            pair(making, sticker: nil)
            Text(StickerWords.failure(failure, name: name, device: device)).modifier(SheetText(muted: false))
                .accessibilityIdentifier("sticker-failed")
            picker(StickerWords.another, primary: true)
            notNow
        case .done:
            EmptyView()
        }
    }

    /// The photo, an arrow, and the sticker cut from it (or the space it will fill).
    private func pair(_ making: StickerMaking, sticker: Data?) -> some View {
        HStack(spacing: 12) {
            if let photo = making.photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("The photo of \(name)")
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface2)
                if let sticker, let image = UIImage(data: sticker) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .accessibilityLabel("The sticker of \(name)")
                        .accessibilityIdentifier("sticker-preview")
                } else if making.step == .cutting {
                    ProgressView()
                }
            }
            .frame(width: 128, height: 128)
        }
        .frame(maxWidth: .infinity)
    }

    private func picker(_ title: String, primary: Bool) -> some View {
        PhotosPicker(selection: $picked, matching: .images) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(PhoneButtonStyle(kind: primary ? .primary : .ghost))
        .accessibilityIdentifier("sticker-photo")
    }

    private var notNow: some View {
        Button(StickerWords.notNow, action: close)
            .buttonStyle(PhoneButtonStyle(kind: .ghost))
    }
}

private struct SheetText: ViewModifier {
    var muted = true

    func body(content: Content) -> some View {
        content
            .phoneFont(.body, 14, weight: 600, relativeTo: .subheadline)
            .foregroundStyle(muted ? Theme.muted : Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The face sheet for a companion: what it shows, and making its photo sticker.
struct FaceRequest: Identifiable {
    enum Start { case choose, sticker, draw }
    let companionId: Companion.ID
    var start: Start = .choose
    /// A photo to draw from instead of the saved one: one just picked in the editor.
    var photo: Data?
    var id: Companion.ID { companionId }
}

/// What the face sheet says.
enum FaceWords {
    static func title(_ name: String) -> String { "\(name.possessive) face" }
    static func everywhere(_ name: String) -> String { "It shows everywhere \(name) does, for the whole household." }
    static let makeSticker = "Make a photo sticker"
    static let newCharacter = "Draw a new character"
    static func photoChanged(_ name: String) -> String {
        "\(name.possessive) character was drawn from the old photo, and stays until you draw a new one."
    }
    static let drawFromPhoto = "Draw a new character from this photo"
    static func finishDrawing(_ name: String) -> String { "Finish drawing \(name)" }
    static let newSticker = "Make a new photo sticker"
    static let removeCharacter = "Remove character"
    static func removeQuestion(_ name: String) -> String { "Remove \(name.possessive) character for everyone?" }
    static func removeDetail(roundsLeft: Int?) -> String {
        // The count only above one, as on "try again".
        let rounds = roundsLeft.flatMap { $0 > 1 ? " \($0) rounds are left." : nil } ?? ""
        return "Its moods are deleted on every device. Drawing another one uses a round of tries again." + rounds
    }
    static let done = "Done"
}

/// The face sheet's content, the same on the phone and the wall: the faces there are for the
/// companion, each shown as it would be, the one showing ticked; making a photo sticker; and
/// removing the character, confirmed. Choosing a face redraws and deletes nothing.
struct FaceSheetContent: View {
    let companionId: Companion.ID
    let name: String
    let personId: Person.ID?
    var start: FaceRequest.Start = .choose
    /// Rounds of tries left for drawing, when the relay said.
    var roundsLeft: Int?
    /// A photo to draw from instead of the saved one.
    var photo: Data?
    var cut: @Sendable (Data) async throws -> PhotoSticker.Result = { try await PhotoSticker.make(from: $0) }
    var service: any CharacterService = CharacterServices.current
    var drafts: CharacterDraftStore = .standard
    let close: () -> Void

    @Environment(CompanionStore.self) private var store
    @State private var makingSticker = false
    @State private var drawingCharacter = false
    @State private var confirmingRemove = false

    private var companion: Companion? { store.snapshot.companions.first { $0.id == companionId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if makingSticker {
                StickerSheetContent(companionId: companionId, name: name, personId: personId, cut: cut) {
                    if start == .sticker { close() } else { makingSticker = false }
                }
            } else if drawingCharacter {
                CharacterJourneyContent(
                    companionId: companionId, name: name, personId: personId, photo: photo, service: service, drafts: drafts, cutOut: cut
                ) {
                    drawingCharacter = false
                    makingSticker = true
                } close: {
                    if start == .draw { close() } else { drawingCharacter = false }
                }
            } else if let companion {
                choices(companion)
            }
        }
        // Opened to make a sticker, the sheet closes once it is used; opened on the faces, it
        // comes back to them with the sticker ticked.
        .onAppear {
            makingSticker = start == .sticker
            drawingCharacter = start == .draw
        }
    }

    @ViewBuilder
    private func choices(_ companion: Companion) -> some View {
        let look = store.snapshot.look(of: companion)
        let shown = Self.shown(look)
        Text(FaceWords.everywhere(name))
            .phoneFont(.body, 14, weight: 600, relativeTo: .subheadline)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        VStack(spacing: 0) {
            ForEach(Self.offered(look), id: \.self) { face in
                Button {
                    if let problem = store.chooseFace(face, for: companionId, by: personId) {
                        store.lastError = problem
                    }
                } label: {
                    HStack(spacing: 12) {
                        CompanionFace(look: Self.look(look, showing: face), size: 44)
                        Text(face.label(species: companion.species))
                            .phoneFont(.body, 15, weight: 700, relativeTo: .body)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        if face == shown {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(face.label(species: companion.species))
                .accessibilityAddTraits(face == shown ? .isSelected : [])
                .accessibilityIdentifier("face-\(face.rawValue)")
            }
        }
        if service.isConfigured, companion.species.isDrawnAsCharacter {
            let title = CharacterDrawing.hasDraft(companionId, in: drafts) ? FaceWords.finishDrawing(name)
                : look.character?.hasCharacter == true ? FaceWords.newCharacter : CharacterWords.draw(name)
            Button(title) { drawingCharacter = true }
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
                .accessibilityIdentifier("draw-character")
        }
        Button(look.character?.hasSticker == true ? FaceWords.newSticker : FaceWords.makeSticker) { makingSticker = true }
            .buttonStyle(PhoneButtonStyle(kind: .ghost))
            .accessibilityIdentifier("make-sticker")
        if look.character?.hasCharacter == true {
            // Quiet: removing is rare, and asks first.
            Button(FaceWords.removeCharacter, role: .destructive) { confirmingRemove = true }
                .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                .foregroundStyle(Color(hex: 0xB4532A))
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("remove-character")
                .confirmationDialog(FaceWords.removeQuestion(name), isPresented: $confirmingRemove, titleVisibility: .visible) {
                    Button(FaceWords.removeCharacter, role: .destructive) { store.removeCharacter(of: companionId, by: personId) }
                } message: {
                    Text(FaceWords.removeDetail(roundsLeft: roundsLeft))
                }
        }
        Button(FaceWords.done, action: close)
            .buttonStyle(PhoneButtonStyle())
            .accessibilityIdentifier("face-done")
    }

    /// The face a companion shows now.
    static func shown(_ look: CompanionLook) -> CompanionFaceChoice {
        look.character?.shown ?? (look.photo != nil ? .photo : .drawn)
    }

    /// The faces there are to choose, in a fixed order.
    static func offered(_ look: CompanionLook) -> [CompanionFaceChoice] {
        var faces: [CompanionFaceChoice] = []
        if look.character?.hasCharacter == true { faces.append(.character) }
        if look.character?.hasSticker == true { faces.append(.sticker) }
        if look.photo != nil { faces.append(.photo) }
        faces.append(.drawn)
        return faces
    }

    /// The companion's look as it would be with `face` chosen.
    static func look(_ look: CompanionLook, showing face: CompanionFaceChoice) -> CompanionLook {
        var look = look
        var character = look.character ?? CharacterLook()
        character.face = face
        look.character = character
        return look
    }
}

extension View {
    /// Presents the face sheet while `request` is set: a system sheet on a phone, a wall sheet
    /// on the wall.
    func faceSheet(_ request: Binding<FaceRequest?>, personId: Person.ID?) -> some View {
        modifier(FaceSheetHost(request: request, personId: personId))
    }
}

private struct FaceSheetHost: ViewModifier {
    @Binding var request: FaceRequest?
    let personId: Person.ID?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(CompanionStore.self) private var store

    private func name(_ id: Companion.ID) -> String {
        store.snapshot.companions.first { $0.id == id }?.name ?? "your companion"
    }

    private func title(_ request: FaceRequest) -> String {
        request.start == .sticker ? StickerWords.title(name(request.companionId)) : FaceWords.title(name(request.companionId))
    }

    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content.sheet(item: $request) { request in
                PhoneSheet(
                    title: title(request),
                    content: {
                        FaceSheetContent(companionId: request.companionId, name: name(request.companionId), personId: personId, start: request.start,
                                         roundsLeft: CharacterOffer.roundsLeft(request.companionId), photo: request.photo) {
                            self.request = nil
                        }
                    },
                    footer: { EmptyView() },
                    fullHeight: true
                )
                .presentationBackground(Theme.surface)
            }
        } else {
            content.wallSheet(item: $request, width: 520) { request in
                WallFaceSheet(request: request, title: title(request), name: name(request.companionId), personId: personId)
            }
        }
    }
}

private struct WallFaceSheet: View {
    let request: FaceRequest
    let title: String
    let name: String
    let personId: Person.ID?
    @Environment(\.closeWallSheet) private var closeSheet

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.display(26))
                .accessibilityAddTraits(.isHeader)
            FaceSheetContent(companionId: request.companionId, name: name, personId: personId, start: request.start,
                                     roundsLeft: CharacterOffer.roundsLeft(request.companionId), photo: request.photo) { closeSheet() }
        }
        .foregroundStyle(Theme.ink)
    }
}
