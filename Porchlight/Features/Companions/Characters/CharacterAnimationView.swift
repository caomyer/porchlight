import SwiftUI

/// When a character's animation plays (docs/design/companion-characters.md, "A mood's
/// animation"): twice back to back as it appears, then twice about every ten seconds while it
/// is on screen, and twice whenever its face is tapped. A play begins only once the strip is
/// ready to show, so none passes on the still. Between plays no timeline runs; under Reduce
/// Motion, with the app not in front, or on a face under 40 points it never moves.
enum CharacterPlayback {
    /// The rest between two turns.
    static let rest: TimeInterval = 10
    /// Plays in a turn, back to back: one alone, about a second, is easy to miss.
    static let playsPerTurn = 2
    /// Faces smaller than this stay still: nine frames in a 28 point dot are only a flicker.
    static let smallestAnimated: CGFloat = 40

    /// How long one play lasts.
    static func duration(frameCount: Int) -> TimeInterval {
        Double(max(frameCount, 0)) * CharacterAnimationCodec.frameDuration
    }

    /// How long a turn lasts: its plays back to back.
    static func turn(frameCount: Int) -> TimeInterval {
        duration(frameCount: frameCount) * Double(playsPerTurn)
    }

    /// The frame showing `elapsed` seconds into a turn, or nil once the turn is over (or
    /// hasn't begun): then the still shows.
    static func frame(at elapsed: TimeInterval, frameCount: Int) -> Int? {
        guard frameCount >= 2, elapsed >= 0 else { return nil }
        let index = Int(elapsed / CharacterAnimationCodec.frameDuration)
        return index < frameCount * playsPerTurn ? index % frameCount : nil
    }

    /// Whether a face plays at all: it has frames, it is large enough, the scene is in front,
    /// and the person hasn't asked for less motion.
    static func plays(frameCount: Int?, size: CGFloat, reduceMotion: Bool, isActive: Bool) -> Bool {
        guard let frameCount, frameCount >= 2 else { return false }
        return !reduceMotion && isActive && size >= smallestAnimated
    }
}

/// A character in a mood: its still, and its animation played by `CharacterPlayback`.
///
/// At rest this is one picture and no timer: a page of pets costs what their stills cost. A
/// turn runs a timeline for about two seconds, sliding the stored strip one frame at a time
/// (nothing is decoded per frame), then the timeline is gone again. Turns stop when the face
/// leaves the screen or the app leaves the front, because their task does.
///
/// James saw no movement on his phone (build 20261124.085813): each play began as the face
/// appeared, before the strip's bytes were read, so it passed on the still, and the next was a
/// minute away. Now the strip is read first, and turns come twice as long and every ten seconds.
struct CharacterAnimationView<Fallback: View>: View {
    let still: CharacterLook.Picture
    let frames: CharacterLook.Picture?
    let size: CGFloat
    /// How a tap plays it: never by default (`CharacterTap`).
    var tap: CharacterTap = .none
    @ViewBuilder let fallback: () -> Fallback

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PhotoImages.self) private var images
    /// When the turn now running began; nil at rest.
    @State private var startedAt: Date?
    /// The strip is decoded and ready to show: turns may begin.
    @State private var ready = false

    private var plays: Bool {
        CharacterPlayback.plays(frameCount: frames?.frameCount, size: size, reduceMotion: reduceMotion, isActive: scenePhase == .active)
    }

    private var stillView: some View {
        CharacterStill(picture: still, isPixelArt: true, size: size, fallback: fallback)
    }

    /// The picture at rest: the animation's own first frame wherever the mood has one, so a
    /// play starts and ends on the very same pixels and the pet is one picture everywhere,
    /// at every size, moving or not. The mood's still (a separate drawing, with its own
    /// outline and pose) shows only when there is no strip, or its bytes are gone or can't be
    /// read; while they are being read nothing shows, since showing the still first would
    /// swap it for the frame a moment later, the jump this rule is here to end. It is drawn by
    /// the very view that draws a play's frames, at frame 0, so the two are one picture by
    /// construction, not two drawings that happen to agree.
    @ViewBuilder
    private var restView: some View {
        if let frames, frames.frameCount >= 1 {
            CharacterFrame(strip: frames, index: 0, size: size) { stillView }
        } else {
            stillView
        }
    }

    var body: some View {
        Group {
            if plays, ready, let frames, let startedAt {
                TimelineView(.periodic(from: startedAt, by: CharacterAnimationCodec.frameDuration)) { context in
                    if let index = CharacterPlayback.frame(at: context.date.timeIntervalSince(startedAt), frameCount: frames.frameCount) {
                        // A frame stands in for the still, never over it: where a frame is
                        // clear, the still must not show through.
                        CharacterFrame(strip: frames, index: index, size: size) { stillView }
                    } else {
                        restView
                    }
                }
            } else {
                restView
            }
        }
        .frame(width: size, height: size)
        .modifier(PlaysOnTap(isOn: tap == .own) { playOnce() })
        .onChange(of: tap) { old, new in
            if case let .counted(count) = new, case let .counted(before) = old, count != before { playOnce() }
        }
        // One task per face and mood: a new mood plays its own animation at once.
        .task(id: PlayKey(frames: frames, plays: plays)) {
            startedAt = nil
            ready = false
            guard plays, let frames else { return }
            // The strip first: a turn that began before it could show would pass on the still.
            // Bytes not there yet (still on their way by sync) are asked for again, every ten
            // seconds while the face is on screen, so it plays once they come.
            while await images.image(PhotoRequest(.character(frames.id, byteCount: frames.byteCount))) == nil {
                try? await Task.sleep(for: .seconds(CharacterPlayback.rest))
                if Task.isCancelled { return }
            }
            ready = true
            while !Task.isCancelled {
                await turn()
                try? await Task.sleep(for: .seconds(CharacterPlayback.rest))
            }
        }
    }

    /// A turn now, on a tap, once the strip is ready.
    private func playOnce() {
        if plays && ready { Task { await turn() } }
    }

    /// One turn: its plays back to back, then the still again. A tap during a turn starts
    /// another from the first frame; the earlier turn's end leaves the newer one alone.
    @MainActor
    private func turn() async {
        guard let frames else { return }
        let mine = Date.now
        startedAt = mine
        try? await Task.sleep(for: .seconds(CharacterPlayback.turn(frameCount: frames.frameCount)))
        if startedAt == mine { startedAt = nil }
    }

    private struct PlayKey: Equatable {
        var frames: CharacterLook.Picture?
        var plays: Bool
    }
}

/// How a tap reaches a character's animation (docs/design/companion-characters.md, "A mood's
/// animation"). A tap gesture on a face inside someone else's Button takes the touch from it,
/// so the Button never fires: in James's test the wall's rail entry and the phone's grid card
/// went dead (build 20261124.220829). So a face listens for taps only where it is itself
/// what is tapped.
enum CharacterTap: Equatable {
    /// No tap: the face is a picture inside a row, a card or a rail entry that does its own thing.
    case none
    /// The face is the tap target and plays on a tap: the phone page's center stage, the
    /// wall's hero.
    case own
    /// A Button around the face plays it by counting its taps: each new count plays a turn
    /// (the phone's Today card, whose face is its own Button).
    case counted(Int)
}

/// A tap that plays, only where the face is the tap target.
private struct PlaysOnTap: ViewModifier {
    var isOn: Bool
    var play: () -> Void

    func body(content: Content) -> some View {
        if isOn {
            // Simultaneous, so it never stands in the way of the wall hero's other gestures.
            content.simultaneousGesture(TapGesture().onEnded { play() })
        } else {
            content
        }
    }
}

/// How a character's pixels are scaled to the screen, at rest and in play alike: without smoothing when the picture is
/// enlarged, which keeps pixel art crisp (a strip of 256 pixel frames, from before frames were
/// kept at 512, shown at 168 points is 504 pixels: about two screen pixels to each of its
/// own); smoothed when it is reduced, so no row or column of it is dropped.
enum CharacterPixels {
    static func interpolation(framePixels: Int, points: CGFloat, displayScale: CGFloat) -> Image.Interpolation {
        CGFloat(framePixels) <= points * displayScale ? .none : .high
    }

    /// A frame's side in pixels: the strip's height. 256 for a strip from before frames were
    /// kept at 512.
    static func framePixels(_ image: UIImage?) -> Int {
        image?.cgImage?.height ?? CharacterImage.frameSide
    }
}

/// One frame of a stored strip: the strip slid so that frame fills the square, with the
/// rest clipped away. The face at rest is frame 0 of it. Nothing shows while the strip's
/// bytes are read; if they are gone or can't be read, `missing` (the still).
struct CharacterFrame<Missing: View>: View {
    let strip: CharacterLook.Picture
    let index: Int
    let size: CGFloat
    @ViewBuilder let missing: () -> Missing

    @Environment(\.displayScale) private var displayScale
    @Environment(PhotoImages.self) private var images

    var body: some View {
        let count = max(strip.frameCount, 1)
        let request = PhotoRequest(.character(strip.id, byteCount: strip.byteCount))
        PhotoView(request: request) { image in
            Color.clear
                .frame(width: size, height: size)
                .overlay(alignment: .leading) {
                    image
                        .resizable()
                        // As the first frame at rest is scaled (`CharacterPixels`), so the two match.
                        .interpolation(CharacterPixels.interpolation(
                            framePixels: CharacterPixels.framePixels(images.cached(request)), points: size, displayScale: displayScale
                        ))
                        .frame(width: size * CGFloat(count), height: size)
                        .offset(x: -size * CGFloat(min(max(index, 0), count - 1)))
                }
                .clipped()
        } placeholder: { isMissing in
            if isMissing { missing() } else { Color.clear.frame(width: size, height: size) }
        }
    }
}
