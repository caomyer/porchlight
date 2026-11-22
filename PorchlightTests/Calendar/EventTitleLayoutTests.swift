import CoreText
import Foundation
import Testing
import UIKit
@testable import Porchlight

/// Titles in the wall week's narrow columns never split a word (`EventTitleLayout`): laid
/// out with Core Text in the grid's own face, at every column width from very narrow to
/// wide, a title the rule lets wrap breaks only between words, and one it keeps to a line
/// has a word that couldn't fit.
@Suite("Event titles in narrow columns wrap at words, never inside one")
struct EventTitleLayoutTests {
    static let titles = [
        "🏺 Pottery class", "Aunt Rosa over for lunch", "Launch review", "🧗 Climbing gym", "Grandma's 80th",
        "Quarterly planning", "Dentist", "Extraordinarily long word", "Busy",
    ]

    /// Where Core Text breaks `text` into lines `width` wide.
    static func lineStarts(_ text: String, font: UIFont, width: CGFloat) -> [Int] {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        return lines.map { CTLineGetStringRange($0).location }
    }

    @Test("Wrapped, every line starts at the start of a word; kept to one line, some word was wider than the column", arguments: [12.5, 16] as [CGFloat])
    func neverSplits(size: CGFloat) {
        let font = UIFont.variable(.body, size: size, weight: 700)
        for title in Self.titles {
            let utf16 = Array(title.utf16)
            for width in stride(from: CGFloat(30), through: 220, by: 2) {
                switch EventTitleLayout.mode(title, font: font, width: width) {
                case .wrap:
                    for start in Self.lineStarts(title, font: font, width: width) where start > 0 {
                        let before = Character(UnicodeScalar(utf16[start - 1]) ?? " ")
                        #expect(before.isWhitespace, "\"\(title)\" at \(width) pt breaks inside a word, at \(start)")
                    }
                case .oneLine:
                    #expect(!EventTitleLayout.fits(EventTitleLayout.longestWordWidth(title, font: font), in: width), "\"\(title)\" at \(width) pt is kept to one line though every word fits")
                }
            }
        }
    }

    @Test("The case on the wall: \"Pottery\" in a column too narrow for it stays on one line")
    func pottery() {
        let font = UIFont.variable(.body, size: 12.5, weight: 700)
        let pottery = EventTitleLayout.longestWordWidth("🏺 Pottery class", font: font)
        #expect(EventTitleLayout.mode("🏺 Pottery class", font: font, width: pottery) == .oneLine)
        #expect(EventTitleLayout.mode("🏺 Pottery class", font: font, width: pottery.rounded(.up) + 1) == .wrap)
    }
}
