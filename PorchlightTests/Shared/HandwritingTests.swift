import CoreText
import Testing
import UIKit
@testable import Porchlight

/// A handwritten title's letters all draw inside its Text (`Handwriting`). A Text is as wide
/// as its letters' advances and as tall as the font's line, and draws nothing beyond, so any
/// ink outside that box is cut: "Oatmeal" lost the top of its "l". Here each title is laid
/// out as the Text lays it out (the handwriting's font, the drawn string) at every size the
/// phone's diary row takes, from the smallest Dynamic Type size to the largest, and at the
/// wall's fixed caption sizes, with and without a companion for its Chinese, and the ink of
/// the whole line has to sit inside the line's own box.
@Suite("Handwritten titles draw inside their box")
struct HandwritingTests {
    private static let titles = [
        "Oatmeal", "Banh mi", "Stuffed", "Pancakes", "Eggs & toast", "Grilled cod", "Chicken curry",
        "Soup of the day", "Fish taco night!", "jam on toast", "Juice", "Steak 牛排", "大盘鸡", "Pizza 披萨", "親子丼とお味噌汁", "Wild",
    ]

    /// The diary row's 23 pt, grown like `.title3` from the smallest size to the largest, and
    /// the wall's caption sizes.
    private static let sizes: [CGFloat] = {
        let categories: [UIContentSizeCategory] = [
            .extraSmall, .large, .extraExtraExtraLarge, .accessibilityMedium, .accessibilityExtraExtraExtraLarge,
        ]
        let phone = categories.map { UIFontMetrics(forTextStyle: .title3).scaledValue(for: 23, compatibleWith: UITraitCollection(preferredContentSizeCategory: $0)) }
        return phone + [15, 18, 20, 22]
    }()

    /// Where the ink of `string` falls against the box a Text gives it, in points.
    private func overflow(_ string: String, size: CGFloat, weight: CGFloat, companion: UIFontDescriptor?) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        var font = UIFont.variable(.hand, size: size, weight: weight)
        if let companion {
            font = UIFont(descriptor: font.fontDescriptor.addingAttributes([.cascadeList: [companion]]), size: size)
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        let ink = CTLineGetImageBounds(line, context)
        // The descender is negative: ink lower than it is below the line.
        return (-ink.minX, ink.maxX - width, ink.maxY - font.ascender, font.descender - ink.minY)
    }

    /// A companion for the Chinese and Japanese: Hannotate where this machine has it, else
    /// the system's own face (what draws until Hannotate arrives).
    private static let companions: [UIFontDescriptor?] = {
        let hannotate = HandCompanion.faces(languages: ["zh-Hans"], weight: 700)[0]
        let name = HandCompanionFonts.installed(hannotate.postScriptName) ? hannotate.postScriptName : "PingFangSC-Semibold"
        return [nil, UIFontDescriptor(fontAttributes: [.name: name]).withMatrix(CGAffineTransform(scaleX: hannotate.scale, y: hannotate.scale))]
    }()

    @Test("Every letter of a title, first and last, draws inside its box at every size", arguments: [false, true])
    func inside(centered: Bool) {
        for title in Self.titles {
            for size in Self.sizes {
                for weight in [600.0, 700.0] {
                    for companion in Self.companions {
                        let drawn = Handwriting.drawn(title, centered: centered)
                        let out = overflow(drawn, size: size, weight: weight, companion: companion)
                        let place = "\"\(title)\" at \(Int(size)) pt, weight \(Int(weight))\(companion == nil ? "" : " with a companion")\(centered ? ", centered" : "")"
                        #expect(out.left <= 0.25, "ink before the box by \(out.left) pt: \(place)")
                        #expect(out.right <= 0.25, "ink past the box by \(out.right) pt: \(place)")
                        #expect(out.top <= 0.25, "ink above the line by \(out.top) pt: \(place)")
                        #expect(out.bottom <= 0.25, "ink below the line by \(out.bottom) pt: \(place)")
                    }
                }
            }
        }
    }

    @Test("Without the room, a title ending in a leaning letter reaches past its box")
    func withoutRoomItIsCut() {
        // What the room is for: the bare title's "l" reaches about a fifth of an em past it.
        let out = overflow("Oatmeal", size: 23, weight: 700, companion: nil)
        #expect(out.right > 2, "Caveat's last \"l\" leans past its width: \(out.right) pt")
    }

    @Test("Room goes after every title, and before it only when centered or its first letter leans back")
    func room() {
        #expect(Handwriting.drawn("Oatmeal", centered: false) == "Oatmeal\u{2005}")
        #expect(Handwriting.drawn("Oatmeal", centered: true) == "\u{2005}Oatmeal\u{2005}")
        #expect(Handwriting.drawn("jam", centered: false).hasPrefix("\u{2006}"), "a \"j\" reaches back before its start")
        #expect(Handwriting.drawn("", centered: true) == "")
        #expect(!Handwriting.leansBack.contains("O"))
    }
}
