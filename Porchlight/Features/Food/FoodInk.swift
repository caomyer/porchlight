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

    /// The page rendered at `scale` view points per page point, for the month and minis.
    ///
    /// Strokes are drawn with Core Graphics from their sampled points instead of
    /// `PKDrawing.image(from:scale:)`, which can come back blank (for example in the
    /// simulator or before PencilKit has warmed up). Widths, opacity and transforms are kept.
    func pageImage(scale: CGFloat, displayScale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        let size = CGSize(width: PageGeometry.size.width * scale, height: PageGeometry.size.height * scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                cg.saveGState()
                cg.concatenate(stroke.transform)
                let color = stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                let points = Array(stroke.path.interpolatedPoints(by: .distance(0.4)))
                if points.count == 1, let point = points.first {
                    color.withAlphaComponent(point.opacity).setFill()
                    let r = point.size.width / 2
                    cg.fillEllipse(in: CGRect(x: point.location.x - r, y: point.location.y - r, width: 2 * r, height: 2 * r))
                }
                for (a, b) in zip(points, points.dropFirst()) {
                    cg.setStrokeColor(color.withAlphaComponent(b.opacity).cgColor)
                    cg.setLineWidth((a.size.width + b.size.width) / 2)
                    cg.move(to: a.location)
                    cg.addLine(to: b.location)
                    cg.strokePath()
                }
                cg.restoreGState()
            }
        }
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
