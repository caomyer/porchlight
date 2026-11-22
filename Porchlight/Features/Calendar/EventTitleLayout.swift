import UIKit

/// How an event's title sits in a narrow column of the wall's week: wrapped at word
/// boundaries when every word fits the column, else on one line, shrunk a little and then
/// cut with an ellipsis. Never a word split across two lines ("Potte / ry class"), which is
/// what a `Text` does with a word wider than its frame. Measured with the face the grid
/// draws in; `EventTitleLayoutTests` lays titles out with Core Text to hold it.
enum EventTitleLayout {
    enum Mode: Equatable {
        /// Wrap over as many lines as there is room for; every word fits on a line.
        case wrap
        /// One line, which may shrink to `minimumScale` and then ends in an ellipsis.
        case oneLine
    }

    /// The smallest a title shrinks to before it is cut: the app's own floor for text in
    /// tight places.
    static let minimumScale: CGFloat = 0.85

    static func mode(_ title: String, font: UIFont, width: CGFloat) -> Mode {
        fits(longestWordWidth(title, font: font), in: width) ? .wrap : .oneLine
    }

    /// Whether a word this wide fits the column, with a point to spare for rounding.
    static func fits(_ wordWidth: CGFloat, in width: CGFloat) -> Bool {
        wordWidth.rounded(.up) + 1 <= width
    }

    static func longestWordWidth(_ title: String, font: UIFont) -> CGFloat {
        title.split(whereSeparator: \.isWhitespace)
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
    }
}
