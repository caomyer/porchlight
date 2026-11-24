import SwiftUI

/// When a character's animation plays (docs/design/companion-characters.md, "A mood's
/// animation"): once as it appears, then it rests on its still, then once more about every
/// minute while it is on screen. It never loops, and under Reduce Motion it never moves.
enum CharacterPlayback {
    /// The rest between two plays.
    static let rest: TimeInterval = 60
    /// Faces smaller than this stay still: nine frames in a 28 point dot are only a flicker.
    static let smallestAnimated: CGFloat = 40

    /// How long one play lasts.
    static func duration(frameCount: Int) -> TimeInterval {
        Double(max(frameCount, 0)) * CharacterAnimationCodec.frameDuration
    }

    /// The frame showing `elapsed` seconds into a play, or nil once the play is over (or
    /// hasn't begun): then the still shows.
    static func frame(at elapsed: TimeInterval, frameCount: Int) -> Int? {
        guard frameCount >= 2, elapsed >= 0 else { return nil }
        let index = Int(elapsed / CharacterAnimationCodec.frameDuration)
        return index < frameCount ? index : nil
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
/// play runs a timeline for about a second, sliding the stored strip one frame at a time
/// (nothing is decoded per frame), then the timeline is gone again. The play stops when the
/// face leaves the screen or the app leaves the front, because its task does.
struct CharacterAnimationView<Fallback: View>: View {
    let still: CharacterLook.Picture
    let frames: CharacterLook.Picture?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// When the play now running began; nil at rest.
    @State private var startedAt: Date?

    private var plays: Bool {
        CharacterPlayback.plays(frameCount: frames?.frameCount, size: size, reduceMotion: reduceMotion, isActive: scenePhase == .active)
    }

    private var stillView: some View {
        CharacterStill(picture: still, isPixelArt: true, size: size, fallback: fallback)
    }

    var body: some View {
        Group {
            if plays, let frames, let startedAt {
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
        // One task per face and mood: a new mood plays its own animation at once.
        .task(id: PlayKey(frames: frames, plays: plays)) {
            startedAt = nil
            guard plays, let frames else { return }
            let length = CharacterPlayback.duration(frameCount: frames.frameCount)
            while !Task.isCancelled {
                startedAt = .now
                try? await Task.sleep(for: .seconds(length))
                startedAt = nil
                try? await Task.sleep(for: .seconds(CharacterPlayback.rest))
            }
        }
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
