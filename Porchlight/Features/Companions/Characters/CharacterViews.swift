import SwiftUI

/// A character's still, as large as the face it stands in for: a sticker or a drawing on
/// a clear background, never clipped to a circle. Until its bytes are read it holds the
/// space; if they are gone, `fallback` (the photo or drawn face) shows instead.
struct CharacterStill<Fallback: View>: View {
    let picture: CharacterLook.Picture
    /// A character drawn in the house style, pixel art: scaled without smoothing.
    var isPixelArt = false
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        PhotoView(request: PhotoRequest(.character(picture.id, byteCount: picture.byteCount))) { image in
            image
                .resizable()
                // Pixel drawings stay crisp; a photo sticker is smoothed as any photo is.
                .interpolation(isPixelArt ? .none : .high)
                .scaledToFit()
                .frame(width: size, height: size)
        } placeholder: { isMissing in
            if isMissing {
                fallback()
            } else {
                Color.clear.frame(width: size, height: size)
            }
        }
    }
}

/// The companion editor's one "Face" choice: the faces there are for a saved companion, the
/// one showing selected, and the face sheet for making a sticker or removing a character.
/// A choice shows at once, everywhere, for the whole household; it deletes nothing.
struct FaceChoiceRow: View {
    let companionId: Companion.ID
    /// Who is choosing, on a personal device.
    var personId: Person.ID?
    /// The photo in the editor, which may have just been picked.
    var draftPhoto: Data?

    @Environment(CompanionStore.self) private var store
    @State private var sheet: FaceRequest?
    /// A photo picked here that isn't the one the character was drawn from.
    @State private var photoChanged = false

    var body: some View {
        if let companion = store.snapshot.companions.first(where: { $0.id == companionId }) {
            let look = store.snapshot.look(of: companion)
            let shown = FaceSheetContent.shown(look)
            FlowLayout(spacing: 8) {
                ForEach(FaceSheetContent.offered(look), id: \.self) { face in
                    let isOn = face == shown
                    Button {
                        _ = store.chooseFace(face, for: companionId, by: personId)
                    } label: {
                        Text(face.label(species: companion.species))
                            .font(.body(12.5, weight: 700))
                            .foregroundStyle(isOn ? Theme.surface : Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isOn ? Theme.ink : Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(isOn ? .clear : Theme.line))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("editor-face-\(face.rawValue)")
                }
                Button {
                    sheet = FaceRequest(companionId: companionId)
                } label: {
                    Label("More", systemImage: "sparkles")
                        .font(.body(12.5, weight: 700))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More face choices")
                .accessibilityIdentifier("editor-face-more")
            }
            .faceSheet($sheet, personId: personId)
            .task(id: draftPhoto?.count) {
                photoChanged = draftPhoto != nil && draftPhoto != store.photo(of: companionId)
            }
            // A new photo never changes or deletes the character; it offers to draw a new one.
            if photoChanged, look.character?.hasCharacter == true, CharacterServices.current.isConfigured,
               CharacterOffer.roundsLeft(companionId) != 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(FaceWords.photoChanged(companion.name))
                        .font(.body(12.5, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(FaceWords.drawFromPhoto) { sheet = FaceRequest(companionId: companionId, start: .draw, photo: draftPhoto) }
                        .font(.body(12.5, weight: 800))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("draw-from-new-photo")
                }
                .padding(.top, 4)
            }
        }
    }
}
