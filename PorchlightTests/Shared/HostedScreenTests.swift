#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The hosted screen's own picture (`HostedScreen`): a page far taller than can be drawn at
/// once still comes out as one whole image with its last row in it, and a picture that is
/// blank where the page has words is a failure, not a shot.
///
/// On November 22, 2026 a page of about 5,400 points was saved as an empty image while every
/// check on it passed: `drawHierarchy` gives back a blank picture, and no error, past about
/// 8192 pixels.
@Suite("A hosted screen's picture, however tall the page")
@MainActor
struct HostedScreenTests {
    /// Three hundred rows of 40 points: 12,000 points, five times what is drawn at once.
    private struct TallPage: View {
        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<300, id: \.self) { row in
                        Text("Row \(row)")
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .background(row.isMultiple(of: 2) ? Color.white : Color(white: 0.9))
                    }
                }
            }
            .background(Color.white)
        }
    }

    @Test("A page of 12,000 points is one whole picture, drawn to its last row")
    func aTallPage() async throws {
        let page = try await HostedScreen.host(TallPage(), look: .light)
        try page.saveShot("hosted-tall-page")
        let last = try #require(page.element(beginningWith: "Row 299"))
        #expect(page.elements.count >= 300, "the page was read: \(page.elements.count) elements")
        #expect(last.frame.maxY > 11_000, "its last row is where a page this long ends: \(last.frame)")
        #expect(page.image.size.height >= last.frame.maxY, "the picture reaches it: \(page.image.size)")
        #expect(page.image.size.height > HostedScreen.tallestDrawn * 4, "so it was drawn in pieces")
        // Every row's own stripe is in the picture where the page says the row is: the rows
        // alternate white and grey, so a piece put in the wrong place shows at once.
        for row in [0, 1, 58, 59, 60, 61, 149, 150, 298, 299] {
            let element = try #require(page.element(beginningWith: "Row \(row)"))
            let grey = try #require(Self.grey(of: page.image, at: CGPoint(x: 380, y: element.frame.midY)))
            #expect(row.isMultiple(of: 2) ? grey > 0.97 : (0.85...0.94).contains(grey), "row \(row) at \(element.frame): \(grey)")
        }
    }

    @Test("A picture that is blank where the page has words is a failure")
    func aBlankPicture() throws {
        let words = [HostedScreen.Element(label: "Row 1", frame: CGRect(x: 16, y: 500, width: 200, height: 24))]
        let size = CGSize(width: 393, height: 900)
        let blank = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        #expect(throws: HostedScreen.Failure.self) { try HostedScreen.checkNotBlank(blank, against: words) }
        let drawn = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 16, y: 500, width: 200, height: 24))
        }
        #expect(throws: Never.self) { try HostedScreen.checkNotBlank(drawn, against: words) }
        // A stretch with no words in it may be one flat colour: an empty page is not blank.
        #expect(throws: Never.self) { try HostedScreen.checkNotBlank(blank, against: []) }
    }

    /// How light the picture is at a point, 0 to 1: that one pixel drawn into a bitmap of a
    /// known layout, since the picture's own may be wide colour or ordered another way.
    private static func grey(of image: UIImage, at point: CGPoint) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        let x = Int(point.x * image.scale), y = Int(point.y * image.scale)
        guard x < cgImage.width, y < cgImage.height, let pixel = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(bytes[0]) + Double(bytes[1]) + Double(bytes[2])) / (3 * 255)
    }
}
#endif
