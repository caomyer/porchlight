import CoreGraphics
import SwiftUI
import UIKit

/// The one handwritten page every day has, shared by everyone in the household. Ink is
/// stored in these canonical page coordinates (points at 1x), so the month cell, the
/// zoomed day editor and the previews are all the same page at different scales:
/// nothing ever reflows.
enum PageGeometry {
    static let size = CGSize(width: 139, height: 137)
    static var bounds: CGRect { CGRect(origin: .zero, size: size) }
    /// The date row sits above the first ruled line.
    static let firstLineTop: CGFloat = 28
    static let lineHeight: CGFloat = 22
    /// Left inset of the day number.
    static let margin: CGFloat = 9

    /// The band of writing line `index` (0-based): its rule is at the bottom edge.
    static func lineRect(_ index: Int) -> CGRect {
        CGRect(x: 0, y: firstLineTop + CGFloat(index) * lineHeight, width: size.width, height: lineHeight)
    }

}

/// How a piece of the page is shown on screen: page point `origin` lands at the
/// view's top-left corner, and one page point is `scale` view points.
struct PageViewport: Equatable, Sendable {
    var scale: CGFloat
    var origin: CGPoint

    /// Page coordinates to view coordinates.
    var toView: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: -origin.x * scale, ty: -origin.y * scale)
    }

    /// View coordinates to page coordinates.
    var toPage: CGAffineTransform { toView.inverted() }

    /// Where the whole page sits in view coordinates.
    var pageFrame: CGRect { PageGeometry.bounds.applying(toView) }

    /// The page drawn at `scale`, centered in a view of `viewSize`.
    static func centered(in viewSize: CGSize, scale: CGFloat) -> PageViewport {
        let page = PageGeometry.size
        return PageViewport(
            scale: scale,
            origin: CGPoint(x: page.width / 2 - viewSize.width / (2 * scale), y: page.height / 2 - viewSize.height / (2 * scale))
        )
    }

    /// The largest scale at which the page fits `viewSize` with `inset` points around it.
    static func fitScale(in viewSize: CGSize, inset: CGFloat) -> CGFloat {
        let page = PageGeometry.size
        let scale = min((viewSize.width - 2 * inset) / page.width, (viewSize.height - 2 * inset) / page.height)
        return max(scale, 0.1)
    }

}

// MARK: - Pens

/// The six inks, tuned to read well on the paper color.
enum PageInk: String, CaseIterable, Identifiable, Sendable {
    case midnight, brick, forest, plum, ochre, graphite

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var hex: UInt32 {
        switch self {
        case .midnight: 0x2F4F86
        case .brick: 0x9C3F2A
        case .forest: 0x3E6B4A
        case .plum: 0x6E4A7E
        case .ochre: 0x8A6418
        case .graphite: 0x3A3530
        }
    }

    var color: Color { Color(hex: hex) }

    var uiColor: UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Each person starts with the pen that matches their color.
    static func defaultInk(for color: PersonColor) -> PageInk {
        switch color {
        case .blue: .midnight
        case .coral: .brick
        case .sage: .forest
        case .plum: .plum
        case .ochre: .ochre
        case .teal: .graphite
        }
    }
}

/// Pen tips. Widths are in page points, so a tip looks the same at every zoom.
enum PenTip: String, CaseIterable, Identifiable, Sendable {
    case fine, felt, marker

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fine: "Fine"
        case .felt: "Felt tip"
        case .marker: "Marker"
        }
    }

    var pageWidth: CGFloat {
        switch self {
        case .fine: 0.9
        case .felt: 1.35
        case .marker: 2.2
        }
    }
}

// MARK: - Paper

enum Paper {
    static let color = Color(hex: 0xFFFDF6)
    static let uiColor = UIColor(red: 1, green: 0xFD / 255, blue: 0xF6 / 255, alpha: 1)
    /// Ruled lines: rgba(140,110,80,.15) over the paper.
    static let rule = Color(hex: 0x8C6E50).opacity(0.15)
    static let cellBorder = Color(hex: 0xEFE5D6)
    static let headerRule = Color(hex: 0xE2D3BE)
    static let desk = Color(hex: 0xECE2D0)
}
