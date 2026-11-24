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

    var body: some View {
        Group {
            if plays, ready, let frames, let startedAt {
                TimelineView(.periodic(from: startedAt, by: CharacterAnimationCodec.frameDuration)) { context in
                    if let index = CharacterPlayback.frame(at: context.date.timeIntervalSince(startedAt), frameCount: frames.frameCount) {
                        // A frame stands in for the still, never over it: where a frame is
                        // clear, the still must not show through.
                        CharacterFrame(strip: frames, index: index, size: size) { stillView }
                    } else {
                        stillView
                    }
                }
            } else {
                stillView
            }
        }
        .frame(width: size, height: size)
        // A tap plays a turn. Simultaneous, so a face that bobs on a tap (the wall's hero)
        // bobs and plays on the same tap.
        .simultaneousGesture(TapGesture().onEnded { if plays && ready { Task { await turn() } } })
        // One task per face and mood: a new mood plays its own animation at once.
        .task(id: PlayKey(frames: frames, plays: plays)) {
            startedAt = nil
            ready = false
            guard plays, let frames else { return }
            // The strip first: a turn that began before it could show would pass on the still.
            guard await images.image(PhotoRequest(.character(frames.id, byteCount: frames.byteCount))) != nil else { return }
            ready = true
            while !Task.isCancelled {
                await turn()
                try? await Task.sleep(for: .seconds(CharacterPlayback.rest))
            }
        }
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

/// One frame of a stored strip: the strip slid so that frame fills the square, with the
/// rest clipped away. Until the strip's bytes are read, or if they are gone, `waiting` shows
/// (the still).
struct CharacterFrame<Waiting: View>: View {
    let strip: CharacterLook.Picture
    let index: Int
    let size: CGFloat
    @ViewBuilder let waiting: () -> Waiting

    var body: some View {
        let count = max(strip.frameCount, 1)
        PhotoView(request: PhotoRequest(.character(strip.id, byteCount: strip.byteCount))) { image in
            Color.clear
                .frame(width: size, height: size)
                .overlay(alignment: .leading) {
                    image
                        .resizable()
                        // Pixel art: scaled without smoothing, as its still is.
                        .interpolation(.none)
                        .frame(width: size * CGFloat(count), height: size)
                        .offset(x: -size * CGFloat(min(max(index, 0), count - 1)))
                }
                .clipped()
        } placeholder: { _ in
            waiting()
        }
    }
}
