import SwiftUI

// Two seams filled by the relay's half of the work (docs/design/companion-characters.md):
// the mood rule, and the view that plays a mood's frames by the motion rule. Until then,
// trivial stand-ins, so every screen already goes through them.

/// How a companion is doing, as its character shows it: one pure rule for every screen and
/// the widget ("Moods follow the day").
enum CharacterMoodRule {
    /// Stand-in: asleep when the report's face is sleepy, else doing fine. The real rule reads
    /// open and late slots, logs in the last hour, everything owed today, and 9 PM.
    static func mood(for report: CompanionReport, now: Date) -> CharacterMood {
        report.expression == .sleepy ? .asleep : .fine
    }
}

/// A character in a mood: its still, and its animation played by the motion rule (once when
/// it appears, then about once a minute, never in a loop, not at all under Reduce Motion).
///
/// Stand-in: the still only. `frames` is a strip of `frameCount` square frames side by side
/// (`CharacterImage`, kind `frames`); the real view reads it through `PhotoImages` as a
/// `.character` picture and steps through it with a `TimelineView`.
struct CharacterAnimationView<Fallback: View>: View {
    let still: CharacterLook.Picture
    let frames: CharacterLook.Picture?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        CharacterStill(picture: still, isPixelArt: true, size: size, fallback: fallback)
    }
}

/// The relay's GIF as the strip `CharacterImage` keeps (`frames`: `frameCount` square frames
/// side by side, each `CharacterImage.frameSide` pixels, scaled without smoothing).
enum CharacterFrames {
    /// Stand-in: no codec yet, so no animation is kept; the still stands on its own.
    static func strip(_ animation: CharacterAnimation) -> (strip: Data, frames: Int)? { nil }
}
