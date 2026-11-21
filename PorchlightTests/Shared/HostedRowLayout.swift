import UIKit

/// Where a list row puts its words against its picture, read from the hosted page's image.
///
/// A list keeps one row layout at a given text size: the words beside the picture at the
/// standard sizes (a long name or line wraps), below it at the accessibility sizes, for every
/// row at once. A row reads to VoiceOver as one element, so the picture and the name have no
/// frames of their own; the image says which layout a row took instead. Beside the picture's
/// top, a strip a few letters wide holds the name's first letters when the words are beside
/// it, and only the card when they went below.
@MainActor
enum HostedRowLayout {
    enum Layout: Equatable { case beside, below }

    /// The layout `row` took, its picture `picture` points wide at its leading edge.
    static func layout(of row: CGRect, picture: CGFloat, in page: HostedScreen) -> Layout? {
        guard let pixels = Pixels(page.image) else { return nil }
        // The card, where the row's top padding leaves it bare.
        let card = pixels.color(at: CGPoint(x: row.minX + picture + 30, y: row.minY + 2))
        let strip = CGRect(x: row.minX + picture + 6, y: row.minY + 8, width: 56, height: picture)
        var inked = 0, all = 0
        var y = strip.minY
        while y < strip.maxY {
            var x = strip.minX
            while x < strip.maxX {
                all += 1
                if pixels.color(at: CGPoint(x: x, y: y)).differs(from: card) { inked += 1 }
                x += 1
            }
            y += 1
        }
        guard all > 0 else { return nil }
        return Double(inked) / Double(all) > 0.02 ? .beside : .below
    }

    private struct RGB {
        var r: Int, g: Int, b: Int
        func differs(from other: RGB) -> Bool { abs(r - other.r) + abs(g - other.g) + abs(b - other.b) > 90 }
    }

    private struct Pixels {
        let data: [UInt8]
        let width: Int, height: Int
        let scale: CGFloat

        init?(_ image: UIImage) {
            guard let cg = image.cgImage else { return nil }
            let w = cg.width, h = cg.height
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            scale = image.scale
            data = bytes
        }

        func color(at point: CGPoint) -> RGB {
            let x = min(max(Int(point.x * scale), 0), width - 1)
            let y = min(max(Int(point.y * scale), 0), height - 1)
            let i = (y * width + x) * 4
            return RGB(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
        }
    }
}
