import SwiftUI

/// A handwritten title, the one way the app writes one (a diary row, a polaroid's caption on
/// the phone and the wall): Caveat with its companion for Chinese and Japanese (`Font.hand`,
/// `HandCompanion`), with room for the letters' tails.
///
/// Caveat's letters lean, and some reach past their own width: an "l", "f" or "I" by up to
/// 0.21 em to the right. A Text is as wide as its letters' advances and draws nothing beyond
/// that, so a title ending in one lost the top of its last letter ("Oatmeal" drew as
/// "Oatmea" and a stroke). A quarter-em space after the title gives the tail room inside
/// the Text, at every size, since it is measured in the title's own font; a centered caption
/// gets the same before it, so it stays centered. VoiceOver and the UI tests read the title
/// itself.
enum Handwriting {
    /// U+2005, a four-per-em space: wider than any tail Caveat draws past its last letter.
    static let tailRoom = "\u{2005}"
    /// U+2006, a six-per-em space: wider than any tail Caveat draws before its first letter
    /// (a "j" by 0.09 em), for a title that starts with one.
    static let leadRoom = "\u{2006}"

    /// The title as drawn: with room after it, and before it when it is centered or its
    /// first letter reaches back past its start.
    static func drawn(_ title: String, centered: Bool) -> String {
        guard let first = title.first else { return title }
        let before = centered ? tailRoom : leansBack.contains(first) ? leadRoom : ""
        return before + title + tailRoom
    }

    /// The letters Caveat draws partly before their own start, measured from the font.
    static let leansBack: Set<Character> = {
        let font = UIFont.variable(.hand, size: 100, weight: 700) as CTFont
        return Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".filter { character in
            var unit = character.utf16.first!
            var glyph = CGGlyph(0)
            guard CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1) else { return false }
            var rect = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &rect, 1)
            return rect.minX < -0.5
        })
    }()
}

extension Text {
    /// A handwritten title with room for its last letter's tail (`Handwriting`). Give it the
    /// handwriting's font as usual: `.font(.hand(…))` or `.phoneFont(.hand, …)`.
    init(handwritten title: String, centered: Bool = false) {
        self = Text(verbatim: Handwriting.drawn(title, centered: centered))
            .accessibilityLabel(Text(verbatim: title))
    }
}
