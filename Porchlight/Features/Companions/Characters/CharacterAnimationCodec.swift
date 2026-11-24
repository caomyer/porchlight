import CoreGraphics
import Foundation
import ImageIO

/// A mood's animation between the relay and the database (docs/design/companion-characters.md,
/// "A mood's animation").
///
/// The relay sends a GIF: nine frames, 512 pixels square, on clear. The app keeps it as
/// `CharacterImage` defines an animation: one PNG strip of square frames side by side, each
/// `CharacterImage.frameSide` pixels, scaled down without smoothing so the pixel art stays
/// crisp. A strip is one picture to store, sync and decode, and a frame is drawn by sliding
/// the strip, with nothing decoded while it plays.
///
/// Whatever comes back that isn't an animation (a still, a refusal page, bytes cut short)
/// makes no strip: the mood's still stands on its own.
enum CharacterAnimationCodec {
    /// A strip ready to store.
    struct Strip: Equatable, Sendable {
        /// The PNG: `frameCount` squares of `frameSide` pixels, left to right.
        var image: Data
        var frameCount: Int
    }

    /// How long each frame shows. The relay's GIFs carry their own delays, but the model
    /// writes them unevenly; one steady pace reads better, and nothing needs storing.
    static let frameDuration: TimeInterval = 0.12

    /// The most frames a strip keeps. A longer answer is sampled evenly down to this many, so
    /// a strip never grows past what one PNG decodes comfortably on the wall's old iPad.
    static let maxFrames = 16

    /// The strip for the relay's GIF, or nil when the bytes aren't an animation.
    static func strip(fromGIF data: Data, frameSide: Int = CharacterImage.frameSide) -> Strip? {
        guard let frames = frames(ofGIF: data), let strip = strip(of: frames, frameSide: frameSide) else { return nil }
        return strip
    }

    /// Every frame of a GIF as it would show: whole, the canvas's size, with earlier frames
    /// already under a frame that only repaints part of the picture. Nil when the bytes aren't
    /// a GIF, or hold fewer than two frames.
    static func frames(ofGIF data: Data) -> [CGImage]? {
        // Only a GIF: a PNG or JPEG answer is a still, never an animation of one frame.
        guard isGIF(data), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count >= 2 else { return nil }
        // Each frame is asked for as displayed. ImageIO composes a GIF's frames (offsets, clear
        // pixels and how the frame before is disposed of) before handing one over, which
        // `CharacterAnimationCodecTests` pins on GIFs written each way.
        let frames = (0..<count).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
        guard frames.count == count, let first = frames.first, first.width > 0, first.height > 0 else { return nil }
        return frames
    }

    /// Lays frames out as a strip. Frames keep their shape: one that isn't square is fitted
    /// inside its square and centred, on clear. More than `maxFrames` are sampled evenly.
    static func strip(of frames: [CGImage], frameSide: Int = CharacterImage.frameSide) -> Strip? {
        let kept = sampled(frames, to: maxFrames)
        guard kept.count >= 2, frameSide > 0,
              let context = CGContext(
                data: nil, width: frameSide * kept.count, height: frameSide, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // Nearest neighbour: each stored pixel is one of the frame's own.
        context.interpolationQuality = .none
        for (index, frame) in kept.enumerated() {
            context.draw(frame, in: fitted(width: frame.width, height: frame.height, into: frameSide).offsetBy(dx: CGFloat(index * frameSide), dy: 0))
        }
        guard let image = context.makeImage(), let png = png(image) else { return nil }
        return Strip(image: png, frameCount: kept.count)
    }

    /// The frames of a stored strip, left to right, for drawing them one at a time outside
    /// SwiftUI (a widget, a test). Screens slide the strip instead (`CharacterAnimationView`).
    static func frames(ofStrip strip: CGImage, count: Int) -> [CGImage] {
        guard count > 0, strip.width >= count else { return [] }
        let side = strip.width / count
        return (0..<count).compactMap { strip.cropping(to: CGRect(x: $0 * side, y: 0, width: side, height: strip.height)) }
    }

    /// Whether stored bytes are a strip this build can play: a picture `frameCount` squares wide.
    static func isPlayable(width: Int, height: Int, frameCount: Int) -> Bool {
        frameCount >= 2 && height > 0 && width == height * frameCount
    }

    // MARK: Pieces

    static func isGIF(_ data: Data) -> Bool {
        data.count > 6 && (data.prefix(6) == Data("GIF89a".utf8) || data.prefix(6) == Data("GIF87a".utf8))
    }

    /// `count` items spread evenly over `items`, first to last; all of them when there are fewer.
    static func sampled<T>(_ items: [T], to count: Int) -> [T] {
        guard items.count > count, count > 1 else { return items }
        return (0..<count).map { items[Int((Double($0) * Double(items.count - 1) / Double(count - 1)).rounded())] }
    }

    /// Where a picture sits in a square of `side`: as large as fits, centred.
    static func fitted(width: Int, height: Int, into side: Int) -> CGRect {
        guard width > 0, height > 0 else { return .zero }
        let scale = min(CGFloat(side) / CGFloat(width), CGFloat(side) / CGFloat(height))
        let size = CGSize(width: (CGFloat(width) * scale).rounded(), height: (CGFloat(height) * scale).rounded())
        return CGRect(x: ((CGFloat(side) - size.width) / 2).rounded(), y: ((CGFloat(side) - size.height) / 2).rounded(), width: size.width, height: size.height)
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// The relay's animation as the journey stores it: the strip and its frame count, or nil
/// when what came back is no animation (then the mood's still stands on its own).
enum CharacterFrames {
    static func strip(_ animation: CharacterAnimation) -> (strip: Data, frames: Int)? {
        CharacterAnimationCodec.strip(fromGIF: animation.gif).map { ($0.image, $0.frameCount) }
    }
}
