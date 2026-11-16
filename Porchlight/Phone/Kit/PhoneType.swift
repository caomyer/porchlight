import SwiftUI

// The phone's type: the wall's own faces and sizes (designed at 375 pt wide), grown
// with Dynamic Type. The wall's fonts are fixed because nobody holds a wall closer;
// a phone follows the reader's text size, up to the largest accessibility size.

extension View {
    /// The wall's typeface at `size`, scaled with Dynamic Type like `style`.
    func phoneFont(_ face: Typeface, _ size: CGFloat, weight: CGFloat = 400, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(PhoneFont(face: face, size: size, weight: weight, style: style))
    }
}

private struct PhoneFont: ViewModifier {
    let face: Typeface
    let weight: CGFloat
    @ScaledMetric private var size: CGFloat

    init(face: Typeface, size: CGFloat, weight: CGFloat, style: Font.TextStyle) {
        self.face = face
        self.weight = weight
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.font(.custom(face, size: size, weight: weight))
    }
}

/// A length that grows with Dynamic Type, but only so far: avatars and faces get
/// bigger with the text beside them without crowding it out.
///
///     @PhoneMetric private var face: CGFloat = 46
@propertyWrapper
struct PhoneMetric: DynamicProperty {
    @ScaledMetric private var scaled: CGFloat
    private let base: CGFloat
    private let cap: CGFloat

    init(wrappedValue base: CGFloat, upTo factor: CGFloat = 1.6, relativeTo style: Font.TextStyle = .body) {
        self.base = base
        cap = base * factor
        _scaled = ScaledMetric(wrappedValue: base, relativeTo: style)
    }

    var wrappedValue: CGFloat { min(max(scaled, base), cap) }
}
