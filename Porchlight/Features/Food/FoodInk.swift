import PencilKit
import UIKit

/// PencilKit helpers for day pages. Drawings are stored in page coordinates
/// (see `PageGeometry`) and moved into view coordinates only while on screen.
enum PageInkData {
    /// True when the data has no strokes (or cannot be read).
    static func isBlank(_ data: Data) -> Bool {
        (try? PKDrawing(data: data))?.strokes.isEmpty ?? true
    }

    static func drawing(from data: Data?) -> PKDrawing {
        data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
    }
}

extension PKDrawing {
    /// This page-space drawing as it appears in `viewport`.
    func inView(_ viewport: PageViewport) -> PKDrawing {
        transformed(using: viewport.toView)
    }

    /// A drawing made in `viewport`'s view coordinates, back in page space.
    func inPage(from viewport: PageViewport) -> PKDrawing {
        transformed(using: viewport.toPage)
    }

    /// The page-space bounds of each stroke.
    var strokeBounds: [CGRect] {
        strokes.map(\.renderBounds)
    }

    /// The page rendered at `scale` view points per page point, for the month and minis.
    /// Rendered in light mode so inks keep their paper-tuned colors.
    func pageImage(scale: CGFloat, displayScale: CGFloat) -> UIImage {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = self.image(from: PageGeometry.bounds, scale: scale * displayScale)
        }
        return image
    }
}

extension PenTip {
    /// The PencilKit tool for this tip at a given zoom (tool widths are in view points).
    func tool(ink: PageInk, zoom: CGFloat) -> PKInkingTool {
        switch self {
        case .fine: PKInkingTool(.pen, color: ink.uiColor, width: pageWidth * zoom)
        case .felt: PKInkingTool(.monoline, color: ink.uiColor, width: pageWidth * zoom)
        case .marker: PKInkingTool(.monoline, color: ink.uiColor, width: pageWidth * zoom)
        }
    }
}

/// Rendered day pages for the month view, keyed by day, change time and scale.
@MainActor
final class PageImageCache {
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 160
    }

    func image(day: DayKey, updatedAt: Date, scale: CGFloat, displayScale: CGFloat, load: () -> Data?) -> UIImage? {
        let key = "\(day.rawValue)|\(updatedAt.timeIntervalSinceReferenceDate)|\(scale)|\(displayScale)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = load(), let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let image = drawing.pageImage(scale: scale, displayScale: displayScale)
        cache.setObject(image, forKey: key)
        return image
    }
}
