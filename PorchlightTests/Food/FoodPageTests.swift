import CoreGraphics
import PencilKit
import Testing
@testable import Porchlight

@Suite("Food: page geometry and ink transforms")
struct FoodPageTests {
    @Test("Ruled lines start under the date row and are 22 pt apart")
    func lines() {
        #expect(PageGeometry.lineRect(0) == CGRect(x: 0, y: 28, width: 139, height: 22))
        #expect(PageGeometry.lineRect(1).minY == 50)
        #expect(PageGeometry.lineRect(4).maxY == 138)
        #expect(PageGeometry.lineIndex(forY: 10) == 0)
        #expect(PageGeometry.lineIndex(forY: 49.9) == 0)
        #expect(PageGeometry.lineIndex(forY: 50) == 1)
        #expect(PageGeometry.lineIndex(forY: 500) == 4)
    }

    @Test("The next free line skips lines that have ink")
    func nextFreeLine() {
        #expect(PageGeometry.nextFreeLine(strokeBounds: []) == 0)
        let first = CGRect(x: 9, y: 31, width: 60, height: 14)
        #expect(PageGeometry.nextFreeLine(strokeBounds: [first]) == 1)
        let third = PageGeometry.lineRect(2).insetBy(dx: 10, dy: 4)
        #expect(PageGeometry.nextFreeLine(strokeBounds: [first, third]) == 1)
        let all = (0..<5).map { PageGeometry.lineRect($0).insetBy(dx: 10, dy: 4) }
        #expect(PageGeometry.nextFreeLine(strokeBounds: all) == 4)
        #expect(PageGeometry.nextFreeLine(strokeBounds: [.null]) == 0)
    }

    @Test("A zoomed viewport maps page points to view points and back")
    func zoomRoundTrip() {
        let viewport = PageViewport(scale: 3.6, origin: .zero)
        let point = CGPoint(x: 10, y: 50)
        let view = point.applying(viewport.toView)
        #expect(abs(view.x - 36) < 0.0001)
        #expect(abs(view.y - 180) < 0.0001)
        let back = view.applying(viewport.toPage)
        #expect(abs(back.x - point.x) < 0.0001 && abs(back.y - point.y) < 0.0001)
        #expect(viewport.pageFrame.size.width == 139 * 3.6)
    }

    @Test("A centered viewport puts the page center in the view center")
    func centered() {
        let size = CGSize(width: 560, height: 596)
        let viewport = PageViewport.centered(in: size, scale: 2)
        let center = CGPoint(x: 69.5, y: 68.5).applying(viewport.toView)
        #expect(abs(center.x - 280) < 0.0001)
        #expect(abs(center.y - 298) < 0.0001)
    }

    @Test("Fit scale keeps the whole page inside the view with an inset")
    func fit() {
        let scale = PageViewport.fitScale(in: CGSize(width: 560, height: 540), inset: 22)
        #expect(abs(scale - (540 - 44) / 137) < 0.0001)
        #expect(139 * scale <= 560 - 44)
    }

    @Test("A note strip shows exactly one ruled line, offset to that line")
    func strip() {
        let viewport = PageViewport.strip(line: 1, width: 334)
        #expect(abs(viewport.scale - 334 / 139) < 0.0001)
        #expect(viewport.origin == CGPoint(x: 0, y: 50))
        #expect(abs(viewport.stripHeight - 22 * 334 / 139) < 0.0001)
        // The top-left of line 2 is the strip's top-left corner.
        let corner = CGPoint(x: 0, y: 50).applying(viewport.toView)
        #expect(abs(corner.x) < 0.0001 && abs(corner.y) < 0.0001)
        // The line's rule lands on the strip's bottom edge.
        let rule = CGPoint(x: 139, y: 72).applying(viewport.toView)
        #expect(abs(rule.x - 334) < 0.0001 && abs(rule.y - viewport.stripHeight) < 0.0001)
    }

    @Test("Ink drawn in the strip and in the zoomed editor lands on the same page spot")
    func drawingRoundTrip() {
        let strip = PageViewport.strip(line: 2, width: 334)
        // A stroke across the middle of the strip, in strip view coordinates.
        let stroke = Self.stroke(from: CGPoint(x: 40, y: strip.stripHeight / 2), to: CGPoint(x: 200, y: strip.stripHeight / 2), width: 1.3 * strip.scale)
        let page = PKDrawing(strokes: [stroke]).inPage(from: strip)
        let bounds = page.bounds
        #expect(PageGeometry.lineIndex(forY: bounds.midY) == 2)
        #expect(abs(bounds.midY - PageGeometry.lineRect(2).midY) < 1)

        // The same page in the 4x editor, then back to page space: unchanged.
        let editor = PageViewport(scale: 4, origin: .zero)
        let inEditor = page.inView(editor)
        #expect(abs(inEditor.bounds.midY - bounds.midY * 4) < 0.5)
        let back = inEditor.inPage(from: editor)
        #expect(abs(back.bounds.minX - bounds.minX) < 0.01)
        #expect(abs(back.bounds.width - bounds.width) < 0.01)
        #expect(PageGeometry.nextFreeLine(strokeBounds: back.strokeBounds) == 0)
    }

    @Test("Each person's default pen follows their color")
    func defaultInks() {
        #expect(PageInk.defaultInk(for: .blue) == .midnight)
        #expect(PageInk.defaultInk(for: .coral) == .brick)
        #expect(PageInk.defaultInk(for: .sage) == .forest)
        #expect(PageInk.defaultInk(for: .plum) == .plum)
        #expect(PageInk.defaultInk(for: .ochre) == .ochre)
        #expect(PageInk.defaultInk(for: .teal) == .graphite)
        #expect(PageInk.brick.hex == 0x9C3F2A)
    }

    @Test("Pen widths are in page points, so tools scale with zoom")
    func toolWidths() {
        let at1 = PenTip.felt.tool(ink: .midnight, zoom: 1)
        let at4 = PenTip.felt.tool(ink: .midnight, zoom: 4)
        #expect(abs(at4.width / at1.width - 4) < 0.01 || at1.width == PKInkingTool.InkType.monoline.validWidthRange.lowerBound)
        #expect(PenTip.fine.pageWidth < PenTip.felt.pageWidth)
        #expect(PenTip.felt.pageWidth < PenTip.marker.pageWidth)
    }

    @Test("Blank drawings are recognized")
    func blank() {
        #expect(PageInkData.isBlank(PKDrawing().dataRepresentation()))
        #expect(PageInkData.isBlank(Data([1, 2, 3])))
        let ink = PKDrawing(strokes: [Self.stroke(from: .zero, to: CGPoint(x: 10, y: 10), width: 1)])
        #expect(!PageInkData.isBlank(ink.dataRepresentation()))
    }

    static func stroke(from start: CGPoint, to end: CGPoint, width: CGFloat) -> PKStroke {
        let points = (0...10).map { step -> PKStrokePoint in
            let t = CGFloat(step) / 10
            return PKStrokePoint(
                location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                timeOffset: TimeInterval(step) * 0.01,
                size: CGSize(width: width, height: width),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.monoline, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
    }
}
