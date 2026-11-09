import CoreGraphics
import PencilKit
import Testing
import UIKit
@testable import Porchlight

@Suite("Food: page geometry and ink transforms")
struct FoodPageTests {
    @Test("Ruled lines start under the date row and are 22 pt apart")
    func lines() {
        #expect(PageGeometry.lineRect(0) == CGRect(x: 0, y: 28, width: 139, height: 22))
        #expect(PageGeometry.lineRect(1).minY == 50)
        #expect(PageGeometry.lineRect(4).maxY == 138)
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

    @Test("Ink drawn at one zoom lands on the same page spot at another")
    func drawingRoundTrip() {
        // A stroke across line 3 of the page in the fitted 3.6x editor, in view coordinates.
        let fitted = PageViewport(scale: 3.6, origin: .zero)
        let y = PageGeometry.lineRect(2).midY * fitted.scale
        let stroke = Self.stroke(from: CGPoint(x: 40, y: y), to: CGPoint(x: 200, y: y), width: 1.3 * fitted.scale)
        let page = PKDrawing(strokes: [stroke]).inPage(from: fitted)
        let bounds = page.bounds
        #expect(abs(bounds.midY - PageGeometry.lineRect(2).midY) < 1)

        // The same page in the 4x editor, then back to page space: unchanged.
        let editor = PageViewport(scale: 4, origin: .zero)
        let inEditor = page.inView(editor)
        #expect(abs(inEditor.bounds.midY - bounds.midY * 4) < 0.5)
        let back = inEditor.inPage(from: editor)
        #expect(abs(back.bounds.minX - bounds.minX) < 0.01)
        #expect(abs(back.bounds.width - bounds.width) < 0.01)
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

#if DEBUG
@Suite("Food: sample handwriting")
struct SampleHandwritingTests {
    @Test("Sample text becomes real strokes on the right ruled lines")
    func strokes() {
        let drawing = SampleHandwriting.page(lines: [("pancakes", .brick), ("pesto pasta!", .midnight)])
        #expect(drawing.strokes.count > 6)
        // Every stroke sits on the first two ruled lines.
        #expect(drawing.strokes.allSatisfy { stroke in
            let midY = stroke.renderBounds.midY
            return midY >= PageGeometry.lineRect(0).minY && midY < PageGeometry.lineRect(1).maxY
        })
        #expect(drawing.bounds.minX >= 5 && drawing.bounds.maxX <= PageGeometry.size.width)

        // The month cell image actually shows the ink.
        let image = drawing.pageImage(scale: 1, displayScale: 2)
        #expect(image.size == PageGeometry.size)
        #expect(Self.inkedPixels(image) > 200)
        // Twice the scale, about four times the ink.
        let big = Self.inkedPixels(drawing.pageImage(scale: 2, displayScale: 2))
        #expect(big > Self.inkedPixels(image) * 3)
    }

    static func inkedPixels(_ image: UIImage) -> Int {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let flattened = UIGraphicsImageRenderer(size: CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: image.size.width * image.scale, height: image.size.height * image.scale))
        }
        guard let cg = flattened.cgImage else { return -1 }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return 0 }
        return stride(from: 3, to: data.count, by: 4).filter { data[$0] > 128 }.count
    }
}
#endif
