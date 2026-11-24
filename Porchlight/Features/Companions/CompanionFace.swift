import SwiftUI

/// How a face looks right now.
enum FaceExpression: Sendable {
    case happy
    case sleepy

    /// Sleepy when the mood has run low.
    init(mood: Double?) {
        self = (mood ?? 0.5) < 0.3 ? .sleepy : .happy
    }
}

/// A companion's look, independent of the database record.
struct CompanionLook: Equatable {
    var species: Species
    var coat: CoatPreset
    var photo: PhotoSource?
    /// Its sticker or drawn character, shown in place of the photo when it has one.
    var character: CharacterLook?

    init(species: Species, coat: CoatPreset, photo: PhotoSource? = nil) {
        self.species = species
        self.coat = coat
        self.photo = photo
    }

    /// A saved companion, with its saved photo.
    init(_ companion: Companion, photo: PhotoSource?) {
        self.init(species: companion.species, coat: companion.coat, photo: photo)
    }

    /// A companion as it is being edited, photo included.
    init(_ draft: CompanionDraft) {
        self.init(species: draft.species, coat: draft.coat, photo: draft.photo.map(PhotoSource.unsaved))
    }

    var tint: Color { coat.tint }
}

/// A companion's face: its sticker or character, a photo, a drawn dog or cat, or an emoji
/// in a circle.
struct CompanionFace: View {
    var look: CompanionLook
    var expression: FaceExpression = .happy
    var size: CGFloat
    /// Gently bob, like the hero face on the companion page.
    var bobs = false
    /// The character's mood (`CharacterMoodRule.mood(for:now:)`); nil reads it from `expression`.
    var mood: CharacterMood?

    private var characterMood: CharacterMood { mood ?? (expression == .sleepy ? .asleep : .fine) }

    var body: some View {
        Group {
            switch look.character?.shown {
            case .character:
                if let character = look.character, let still = character.still(characterMood) {
                    CharacterAnimationView(still: still, frames: character.animation(characterMood), size: size) { photoOrDrawn }
                }
            case .sticker:
                if let sticker = look.character?.sticker {
                    CharacterStill(picture: sticker, size: size) { photoOrDrawn }
                }
            case .drawn:
                drawn
            case .photo, nil:
                photoOrDrawn
            }
        }
        .modifier(Bob(isOn: bobs, size: size))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var photoOrDrawn: some View {
        Group {
            if let photo = look.photo {
                PhotoView(request: PhotoRequest(photo)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.surface, lineWidth: max(1, size * 0.03)))
                } placeholder: { isMissing in
                    if isMissing {
                        drawn
                    } else {
                        // Still loading: the coat's color, so the drawn face never flashes up first.
                        Circle().fill(look.tint.wash(0.32)).frame(width: size, height: size)
                    }
                }
            } else {
                drawn
            }
        }
    }

    @ViewBuilder
    private var drawn: some View {
        if look.species.hasDrawnFace {
            DrawnFace(species: look.species, coat: look.coat, expression: expression)
                .frame(width: size, height: size)
        } else {
            Text(look.species.emoji)
                .font(.system(size: size * 0.52))
                .frame(width: size * 0.86, height: size * 0.86)
                .background(look.tint.wash(0.32), in: Circle())
                .frame(width: size, height: size)
        }
    }
}

/// A face on its tinted disc, as lists, headers and cards show it. A photo or a drawn face sits
/// inside the disc, as it always has; a character or a photo sticker, on clear with its own
/// white edge, stands on the card itself, with no disc behind it, and fills the disc's frame.
/// The one place that decides (docs/design/companion-characters.md, "Where it stands").
struct DiscFace: View {
    var look: CompanionLook
    var expression: FaceExpression = .happy
    var mood: CharacterMood?
    /// The disc's side.
    let side: CGFloat
    /// The face's side inside the disc, for a photo or a drawn face.
    let face: CGFloat
    let disc: Color

    var body: some View {
        if look.standsOnCard {
            CompanionFace(look: look, expression: expression, size: side, mood: mood)
                .frame(width: side, height: side)
        } else {
            CompanionFace(look: look, expression: expression, size: face, mood: mood)
                .frame(width: side, height: side)
                .background(disc, in: Circle())
        }
    }
}

/// A face standing on its card at its full size, as a companion's page shows it, on the wall
/// (its hero) and on the phone (its header): a character or a photo sticker with a soft
/// shadow on the ground under it; a photo or drawn face as `DiscFace` draws it when a disc is
/// given, or bare, as the wall's hero has always shown one.
struct StageFace: View {
    var look: CompanionLook
    var expression: FaceExpression = .happy
    var mood: CharacterMood?
    let size: CGFloat
    /// The disc behind a photo or drawn face; nil for none.
    var disc: Color?
    /// Gently bob, as the wall's hero face does.
    var bobs = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if look.standsOnCard {
                // The ground it stands on: a soft shadow under its feet, never a disc.
                Ellipse()
                    .fill(Color.black.opacity(0.13))
                    .frame(width: size * 0.56, height: size * 0.07)
                    .blur(radius: size * 0.025)
                    .offset(y: size * 0.015)
                    .accessibilityHidden(true)
            }
            if let disc {
                DiscFace(look: look, expression: expression, mood: mood, side: size, face: size * 0.86, disc: disc)
            } else {
                CompanionFace(look: look, expression: expression, size: size, bobs: bobs, mood: mood)
            }
        }
        .frame(width: size, height: size)
    }
}

extension CompanionLook {
    /// Whether this face plays an animation in `mood` (a character with that mood's frames):
    /// a tap on it plays, rather than opening anything.
    func animates(in mood: CharacterMood?) -> Bool {
        guard character?.shown == .character, let character else { return false }
        return character.animation(mood ?? .fine) != nil
    }

    /// A character or a photo sticker shows: it stands on the card, with no disc.
    var standsOnCard: Bool {
        switch character?.shown {
        case .character?, .sticker?: true
        default: false
        }
    }
}

/// The mock's gentle bob: up a few points and a small tilt, 1.6 s each way.
///
/// It bobs twice when the face appears or is tapped, then once a minute. Bobbing forever
/// would redraw the page 120 times a second on the wall's ProMotion screen, all day long.
private struct Bob: ViewModifier {
    var isOn: Bool
    var size: CGFloat
    @State private var bobs = 0

    func body(content: Content) -> some View {
        if isOn {
            content
                .phaseAnimator(Restful.twice, trigger: bobs) { face, up in
                    face
                        .rotationEffect(.degrees(up ? 2 : -2))
                        .offset(y: up ? -size * 0.033 : 0)
                } animation: { _ in .easeInOut(duration: 1.6) }
                .contentShape(Circle())
                .onTapGesture { bobs += 1 }
                .task { await Restful.everyMinute { bobs += 1 } }
        } else {
            content
        }
    }
}

/// Vector dog and cat faces on a 120 x 120 canvas, ported from the design mock.
struct DrawnFace: View {
    var species: Species
    var coat: CoatPreset
    var expression: FaceExpression

    private static let ink = Color(hex: 0x2A1E16)
    private static let muzzle = Color(hex: 0xFFF3E2)
    private static let blush = Color(hex: 0xF49A8A)
    private static let tongue = Color(hex: 0xF07C7C)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 120, y: size.height / 120)
            switch species {
            case .cat: drawCat(&context)
            default: drawDog(&context)
            }
        }
    }

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotation degrees: CGFloat = 0) -> Path {
        let path = Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        guard degrees != 0 else { return path }
        let transform = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -cx, y: -cy)
        return path.applying(transform)
    }

    private func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        ellipse(cx, cy, r, r)
    }

    private func drawEyes(_ context: inout GraphicsContext, left: CGPoint, right: CGPoint, radius: CGFloat, tall: CGFloat = 1) {
        if coat.isDark {
            // A soft rim keeps dark eyes readable on a dark coat.
            for eye in [left, right] {
                context.fill(ellipse(eye.x, eye.y, radius + 2.2, radius * tall + 2.2), with: .color(Self.muzzle.opacity(0.9)))
            }
        }
        switch expression {
        case .happy:
            for eye in [left, right] {
                context.fill(ellipse(eye.x, eye.y, radius, radius * tall), with: .color(Self.ink))
                context.fill(circle(eye.x + radius * 0.35, eye.y - radius * 0.35, radius * 0.33), with: .color(.white))
            }
        case .sleepy:
            for eye in [left, right] {
                var lid = Path()
                lid.move(to: CGPoint(x: eye.x - radius, y: eye.y))
                lid.addQuadCurve(to: CGPoint(x: eye.x + radius, y: eye.y), control: CGPoint(x: eye.x, y: eye.y + radius * 0.9))
                context.stroke(lid, with: .color(Self.ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }
    }

    private func drawDog(_ context: inout GraphicsContext) {
        context.fill(ellipse(25, 58, 15, 27, rotation: 18), with: .color(coat.shade))
        context.fill(ellipse(95, 58, 15, 27, rotation: -18), with: .color(coat.shade))
        context.fill(circle(60, 62, 37), with: .color(coat.main))
        context.fill(circle(49, 27, 9), with: .color(coat.main))
        context.fill(circle(60, 24, 10), with: .color(coat.main))
        context.fill(circle(71, 27, 9), with: .color(coat.main))
        context.fill(ellipse(60, 80, 20, 15), with: .color(Self.muzzle))
        drawEyes(&context, left: CGPoint(x: 45, y: 58), right: CGPoint(x: 75, y: 58), radius: 5.2)
        context.fill(ellipse(37, 70, 5.5, 3.3), with: .color(Self.blush.opacity(0.55)))
        context.fill(ellipse(83, 70, 5.5, 3.3), with: .color(Self.blush.opacity(0.55)))
        context.fill(ellipse(60, 72, 6.5, 4.8), with: .color(Self.ink))
        var mouth = Path()
        switch expression {
        case .happy:
            mouth.move(to: CGPoint(x: 52, y: 80))
            mouth.addQuadCurve(to: CGPoint(x: 60, y: 80), control: CGPoint(x: 56, y: 85))
            mouth.addQuadCurve(to: CGPoint(x: 68, y: 80), control: CGPoint(x: 64, y: 85))
            var tongue = Path()
            tongue.move(to: CGPoint(x: 56, y: 83))
            tongue.addQuadCurve(to: CGPoint(x: 64, y: 83), control: CGPoint(x: 60, y: 95))
            tongue.closeSubpath()
            context.fill(tongue, with: .color(Self.tongue))
        case .sleepy:
            mouth.move(to: CGPoint(x: 55, y: 82))
            mouth.addQuadCurve(to: CGPoint(x: 65, y: 82), control: CGPoint(x: 60, y: 84))
        }
        context.stroke(mouth, with: .color(Self.ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    private func drawCat(_ context: inout GraphicsContext) {
        var leftEar = Path()
        leftEar.move(to: CGPoint(x: 24, y: 52))
        leftEar.addLine(to: CGPoint(x: 30, y: 14))
        leftEar.addLine(to: CGPoint(x: 56, y: 32))
        leftEar.closeSubpath()
        var rightEar = Path()
        rightEar.move(to: CGPoint(x: 96, y: 52))
        rightEar.addLine(to: CGPoint(x: 90, y: 14))
        rightEar.addLine(to: CGPoint(x: 64, y: 32))
        rightEar.closeSubpath()
        let round = StrokeStyle(lineWidth: 6, lineJoin: .round)
        for ear in [leftEar, rightEar] {
            context.fill(ear, with: .color(coat.main))
            context.stroke(ear, with: .color(coat.main), style: round)
        }
        var leftInner = Path()
        leftInner.move(to: CGPoint(x: 31, y: 40))
        leftInner.addLine(to: CGPoint(x: 34, y: 23))
        leftInner.addLine(to: CGPoint(x: 47, y: 33))
        leftInner.closeSubpath()
        var rightInner = Path()
        rightInner.move(to: CGPoint(x: 89, y: 40))
        rightInner.addLine(to: CGPoint(x: 86, y: 23))
        rightInner.addLine(to: CGPoint(x: 73, y: 33))
        rightInner.closeSubpath()
        context.fill(leftInner, with: .color(Self.blush.opacity(0.7)))
        context.fill(rightInner, with: .color(Self.blush.opacity(0.7)))
        context.fill(ellipse(60, 64, 40, 35), with: .color(coat.main))
        // Forehead stripes in the ear shade.
        for (x, top) in [(52.0, 31.0), (60.0, 29.5), (68.0, 31.0)] {
            var stripe = Path()
            stripe.move(to: CGPoint(x: x, y: top))
            stripe.addLine(to: CGPoint(x: x, y: top + 8))
            context.stroke(stripe, with: .color(coat.shade.opacity(0.7)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        context.fill(circle(52.5, 79, 9.5), with: .color(Self.muzzle))
        context.fill(circle(67.5, 79, 9.5), with: .color(Self.muzzle))
        drawEyes(&context, left: CGPoint(x: 44, y: 60), right: CGPoint(x: 76, y: 60), radius: 5, tall: 1.2)
        context.fill(ellipse(35, 72, 5.5, 3.3), with: .color(Self.blush.opacity(0.5)))
        context.fill(ellipse(85, 72, 5.5, 3.3), with: .color(Self.blush.opacity(0.5)))
        var nose = Path()
        nose.move(to: CGPoint(x: 55.5, y: 71))
        nose.addLine(to: CGPoint(x: 64.5, y: 71))
        nose.addLine(to: CGPoint(x: 60, y: 76.5))
        nose.closeSubpath()
        context.fill(nose, with: .color(Color(hex: 0xE07A7A)))
        context.stroke(nose, with: .color(Color(hex: 0xE07A7A)), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 60, y: 77))
        mouth.addQuadCurve(to: CGPoint(x: 52, y: 82), control: CGPoint(x: 57, y: 83))
        mouth.move(to: CGPoint(x: 60, y: 77))
        mouth.addQuadCurve(to: CGPoint(x: 68, y: 82), control: CGPoint(x: 63, y: 83))
        context.stroke(mouth, with: .color(Self.ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        var whiskers = Path()
        for (y1, y2) in [(76.0, 72.0), (81.0, 82.0)] {
            whiskers.move(to: CGPoint(x: 40, y: y1))
            whiskers.addLine(to: CGPoint(x: 16, y: y2))
            whiskers.move(to: CGPoint(x: 80, y: y1))
            whiskers.addLine(to: CGPoint(x: 104, y: y2))
        }
        context.stroke(whiskers, with: .color(Self.ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}
