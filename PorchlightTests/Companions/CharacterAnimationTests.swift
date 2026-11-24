import ImageIO
import Testing
import UIKit
@testable import Porchlight

/// A mood's animation between the relay and the screen (docs/design/companion-characters.md,
/// "A mood's animation"): the GIF the relay sends becomes the strip `CharacterImage` stores,
/// and the strip plays once, then rests.
@Suite("A character's animation")
struct CharacterAnimationTests {
    /// A 64 by 64 GIF of four frames written the thrifty way: after the first, each frame
    /// holds only the small box that changed, at an offset, with clear pixels where nothing
    /// did. Red everywhere, and one green box that steps right. Read frame by frame without
    /// composing, every frame after the first would be a green box on nothing.
    private static let partialFrames = Data(base64Encoded: [
        "R0lGODlhQABAAPcfMQAAACQAAEgAAGwAAJAAALQAANgAAPwAAAAkACQkAEgkAGwkAJAkALQkANgkAPwkAABIACRIAEhIAGxIAJBIALRIANhIAP",
        "xIAABsACRsAEhsAGxsAJBsALRsANhsAPxsAACQACSQAEiQAGyQAJCQALSQANiQAPyQAAC0ACS0AEi0AGy0AJC0ALS0ANi0APy0AADYACTYAEjY",
        "AGzYAJDYALTYANjYAPzYAAD8ACT8AEj8AGz8AJD8ALT8ANj8APz8AAAAVSQAVUgAVWwAVZAAVbQAVdgAVfwAVQAkVSQkVUgkVWwkVZAkVbQkVd",
        "gkVfwkVQBIVSRIVUhIVWxIVZBIVbRIVdhIVfxIVQBsVSRsVUhsVWxsVZBsVbRsVdhsVfxsVQCQVSSQVUiQVWyQVZCQVbSQVdiQVfyQVQC0VSS0",
        "VUi0VWy0VZC0VbS0Vdi0Vfy0VQDYVSTYVUjYVWzYVZDYVbTYVdjYVfzYVQD8VST8VUj8VWz8VZD8VbT8Vdj8Vfz8VQAAqiQAqkgAqmwAqpAAqr",
        "QAqtgAqvwAqgAkqiQkqkgkqmwkqpAkqrQkqtgkqvwkqgBIqiRIqkhIqmxIqpBIqrRIqthIqvxIqgBsqiRsqkhsqmxsqpBsqrRsqthsqvxsqgCQ",
        "qiSQqkiQqmyQqpCQqrSQqtiQqvyQqgC0qiS0qki0qmy0qpC0qrS0qti0qvy0qgDYqiTYqkjYqmzYqpDYqrTYqtjYqvzYqgD8qiT8qkj8qmz8qp",
        "D8qrT8qtj8qvz8qgAA/yQA/0gA/2wA/5AA/7QA/9gA//wA/wAk/yQk/0gk/2wk/5Ak/7Qk/9gk//wk/wBI/yRI/0hI/2xI/5BI/7RI/9hI//xI",
        "/wBs/yRs/0hs/2xs/5Bs/7Rs/9hs//xs/wCQ/ySQ/0iQ/2yQ/5CQ/7SQ/9iQ//yQ/wC0/yS0/0i0/2y0/5C0/7S0/9i0//y0/wDY/yTY/0jY/2",
        "zY/5DY/7TY/9jY//zY/wD8/yT8/0j8/2z8/5D8/7T8/9j8//z8/yH/C05FVFNDQVBFMi4wAwEAAAAh+QQEDQAfACwAAAAAQABAAAAIjQAPCBxI",
        "sKDBgwgTKlzIsKHDhxAjSpxIsaLFixgzatzIsaPHjyBDihxJsqTJkyhTqlzJsqXLlzBjypxJs6bNmwRz6NypU0cOmzlwCB061CbRoziMIi1aM+",
        "jSpDWfClX6FKhUqkuxIsVJ8IFAr1zDih1LtqzZs2jTql3Ltq3bt3Djyp1Lt67du3jz6l0YEAAh+QQFDAAAACwIABgAFgALAAAITQAPCBxIEAAA",
        "Hjp2JNzBkCHBhwcM5sBBsWJFiAUB6LDIEeNAiRwtehQIMiTFkREBTDSJA2VJky5Vsmw58mXImCtNGtwJIGVKngYfBA0IACH5BAUNAAAALBQAGA",
        "AWAAsAAAhMAA8IHEgQAIAfO3goXNiDB8GHBwzqwEGxYkWIBQFMtFgxB8aBEjla/CgwpEiKJCNqPImSpMmTKV+KjLmSJc2NJw3qBKBS5U6DD4AG",
        "BAAh+QQFDQAAACwgABgAFgALAAAITgAPCBxIEACAHz569EjI0AfBhwcM8sBBsWJFiAUB7LDIEeNAgxs5XvQYUaPIkR5BnqRIsmTIky0N6liJI6",
        "bJlTZfijTIE0DJkj0NPhAaEAA7",
    ].joined())!

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return pixel
    }

    private static func isRed(_ pixel: [UInt8]) -> Bool { pixel[0] > 200 && pixel[1] < 60 && pixel[3] == 255 }
    private static func isGreen(_ pixel: [UInt8]) -> Bool { pixel[1] > 200 && pixel[0] < 60 && pixel[3] == 255 }

    /// A GIF of `count` frames, each `width` by `height` and one flat colour, brighter each frame.
    private static func gif(frames count: Int, width: Int = 64, height: Int = 64) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, count, nil))
        for frame in 0..<count {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                UIColor(white: CGFloat(frame + 1) / CGFloat(count + 1), alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            CGImageDestinationAddImage(destination, try #require(image.cgImage), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("A GIF whose frames hold only what changed is read as it would show: each frame whole")
    func partialFramesAreComposed() throws {
        let frames = try #require(CharacterAnimationCodec.frames(ofGIF: Self.partialFrames))
        #expect(frames.count == 4)
        for (index, frame) in frames.enumerated() {
            #expect(frame.width == 64 && frame.height == 64, "frame \(index) is the canvas's size")
            #expect(Self.isRed(Self.pixel(frame, x: 2, y: 2)), "frame \(index) keeps what no frame repainted")
            #expect(Self.isGreen(Self.pixel(frame, x: 12 + index * 12, y: 28)), "frame \(index) has its own box")
            if index > 0 {
                #expect(Self.isRed(Self.pixel(frame, x: 12, y: 28)), "frame \(index) no longer has the first frame's box")
            }
        }
    }

    @Test("The relay's GIF becomes one strip: its frames side by side, each the stored size, in order")
    func strip() throws {
        let gif = try #require(CharacterPlaceholders.animation(species: .dog, variant: 0, mood: .fine))
        let strip = try #require(CharacterAnimationCodec.strip(fromGIF: gif))
        #expect(strip.frameCount == CharacterPlaceholders.frameCount)
        let image = try #require(UIImage(data: strip.image)?.cgImage)
        #expect(image.width == CharacterImage.frameSide * strip.frameCount && image.height == CharacterImage.frameSide)
        #expect(CharacterAnimationCodec.isPlayable(width: image.width, height: image.height, frameCount: strip.frameCount))
        #expect(strip.image.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "a PNG, as a still is")

        // Each stored frame is the GIF's frame, scaled without smoothing: the same colours at
        // the same places, and clear where the sprite is clear.
        let source = try #require(CharacterAnimationCodec.frames(ofGIF: gif))
        let stored = CharacterAnimationCodec.frames(ofStrip: image, count: strip.frameCount)
        #expect(stored.count == source.count)
        for (index, frame) in stored.enumerated() {
            #expect(frame.width == CharacterImage.frameSide && frame.height == CharacterImage.frameSide)
            // The sprite's body, and a corner it never fills.
            let body = Self.pixel(frame, x: 15 * 8 + 4, y: 22 * 8 + 4)
            let same = Self.pixel(source[index], x: 15 * 16 + 8, y: 22 * 16 + 8)
            #expect(zip(body, same).allSatisfy { abs(Int($0) - Int($1)) <= 12 }, "frame \(index) keeps its colours: \(body) \(same)")
            #expect(Self.pixel(frame, x: 1, y: 1)[3] == 0, "frame \(index) is clear where the sprite is")
        }
        // The frames differ: the strip is the animation, not nine copies of one frame.
        // (The placeholder sprite lifts a block on some frames: the row above its head fills.)
        #expect(Set(stored.map { Self.pixel($0, x: 15 * 8 + 4, y: 6 * 8 + 4)[3] }).count > 1)
    }

    @Test("A GIF of another size or shape still makes square frames, fitted and centred on clear")
    func otherShapes() throws {
        let wide = try #require(CharacterAnimationCodec.strip(fromGIF: try Self.gif(frames: 3, width: 120, height: 60)))
        let image = try #require(UIImage(data: wide.image)?.cgImage)
        #expect(wide.frameCount == 3 && image.width == CharacterImage.frameSide * 3 && image.height == CharacterImage.frameSide)
        let first = try #require(CharacterAnimationCodec.frames(ofStrip: image, count: 3).first)
        #expect(Self.pixel(first, x: CharacterImage.frameSide / 2, y: CharacterImage.frameSide / 2)[3] == 255, "the picture is in the middle")
        #expect(Self.pixel(first, x: CharacterImage.frameSide / 2, y: 4)[3] == 0, "with clear above and below a wide one")
        #expect(CharacterAnimationCodec.fitted(width: 120, height: 60, into: 256) == CGRect(x: 0, y: 64, width: 256, height: 128))
        #expect(CharacterAnimationCodec.fitted(width: 0, height: 60, into: 256) == .zero)
    }

    @Test("More frames than a strip keeps are sampled evenly, first and last kept; fewer are all kept")
    func frameCounts() throws {
        let long = try #require(CharacterAnimationCodec.strip(fromGIF: try Self.gif(frames: 30, width: 16, height: 16), frameSide: 16))
        #expect(long.frameCount == CharacterAnimationCodec.maxFrames)
        #expect(CharacterAnimationCodec.sampled(Array(0..<30), to: 16).first == 0)
        #expect(CharacterAnimationCodec.sampled(Array(0..<30), to: 16).last == 29)
        #expect(CharacterAnimationCodec.sampled(Array(0..<30), to: 16) == CharacterAnimationCodec.sampled(Array(0..<30), to: 16).sorted())
        #expect(CharacterAnimationCodec.sampled([1, 2, 3], to: 16) == [1, 2, 3])
        let short = try #require(CharacterAnimationCodec.strip(fromGIF: try Self.gif(frames: 2, width: 16, height: 16), frameSide: 16))
        #expect(short.frameCount == 2)
    }

    @Test("Anything that isn't an animation makes no strip, so the still stands on its own")
    func notAnAnimation() throws {
        let still = try #require(CharacterPlaceholders.sprite(species: .cat, variant: 1, mood: .fine))
        #expect(CharacterAnimationCodec.strip(fromGIF: still) == nil, "a PNG")
        #expect(CharacterAnimationCodec.strip(fromGIF: CharacterPlaceholders.photo()) == nil, "a JPEG")
        #expect(CharacterAnimationCodec.strip(fromGIF: try Self.gif(frames: 1)) == nil, "a GIF of one frame")
        #expect(CharacterAnimationCodec.strip(fromGIF: Data()) == nil)
        #expect(CharacterAnimationCodec.strip(fromGIF: Data("GIF89a and then nothing".utf8)) == nil, "a GIF cut short")
        #expect(CharacterAnimationCodec.strip(fromGIF: Data("<html>503</html>".utf8)) == nil, "an error page")
        let whole = try Self.gif(frames: 4)
        #expect(CharacterAnimationCodec.strip(fromGIF: whole.prefix(whole.count / 3)) == nil || CharacterAnimationCodec.strip(fromGIF: whole.prefix(whole.count / 3))!.frameCount >= 2,
                "a GIF cut off part way is either refused or keeps only whole frames")
        #expect(!CharacterAnimationCodec.isPlayable(width: 512, height: 256, frameCount: 1))
        #expect(!CharacterAnimationCodec.isPlayable(width: 500, height: 256, frameCount: 2))
        #expect(CharacterAnimationCodec.frames(ofStrip: try #require(UIImage(data: still)?.cgImage), count: 0).isEmpty)
    }

    @Test("Four moods of a pet, stills and animations, are a few megabytes at most")
    func bytesPerPet() throws {
        var total = 0
        for mood in CharacterMood.allCases {
            total += try #require(CharacterPlaceholders.sprite(species: .dog, variant: 0, mood: mood)).count
            let gif = try #require(CharacterPlaceholders.animation(species: .dog, variant: 0, mood: mood))
            total += try #require(CharacterAnimationCodec.strip(fromGIF: gif)).image.count
        }
        // Flat sprites drawn in code are tiny; the relay's drawings measured about 0.6 MB a
        // strip. The ceiling is what a strip can be at all: nine frames of 256, uncompressed.
        #expect(total < 4 * (CharacterImage.frameSide * CharacterImage.frameSide * 4 * 9 + CharacterImage.stillSide * CharacterImage.stillSide * 4))
    }

    // MARK: The palette PNG

    /// A picture `width` by `height` made by `colour(x, y)`: red, green, blue and alpha.
    private static func picture(width: Int, height: Int, _ colour: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (red, green, blue, alpha) = colour(x, y)
                // Stored multiplied by its clearness, as a bitmap context holds it.
                let at = (y * width + x) * 4
                bytes[at] = UInt8(Int(red) * Int(alpha) / 255)
                bytes[at + 1] = UInt8(Int(green) * Int(alpha) / 255)
                bytes[at + 2] = UInt8(Int(blue) * Int(alpha) / 255)
                bytes[at + 3] = alpha
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    @Test("A strip is stored as a palette PNG that reads back pixel for pixel, clear where it was clear")
    func paletteStrip() throws {
        let gif = try #require(CharacterPlaceholders.animation(species: .dog, variant: 2, mood: .waiting))
        let frames = try #require(CharacterAnimationCodec.frames(ofGIF: gif))
        let strip = try #require(CharacterAnimationCodec.strip(of: frames))
        // Colour type 3 in the header: a palette.
        #expect(strip.image[25] == 3 && strip.image[24] == 8, "eight bits a pixel, by palette")
        let read = try #require(UIImage(data: strip.image)?.cgImage)
        #expect(read.width == CharacterImage.frameSide * frames.count && read.height == CharacterImage.frameSide)
        // Against the frames themselves, scaled as the codec scales them.
        let stored = CharacterAnimationCodec.frames(ofStrip: read, count: frames.count)
        for (index, frame) in frames.enumerated() {
            for (x, y) in [(15, 22), (10, 12), (1, 1), (30, 30), (16, 20)] {
                let was = Self.pixel(frame, x: x * 16 + 8, y: y * 16 + 8)
                let now = Self.pixel(stored[index], x: x * 8 + 4, y: y * 8 + 4)
                #expect(zip(was, now).allSatisfy { abs(Int($0) - Int($1)) <= 2 }, "frame \(index) at block (\(x), \(y)): \(was) became \(now)")
            }
        }
    }

    @Test("A palette PNG keeps every colour and every clearness it was given, exactly")
    func paletteExact() throws {
        // A hundred colours, each opaque and half clear, and a clear corner: about 200 in all.
        let image = try Self.picture(width: 40, height: 20) { x, y in
            if x < 4 && y < 4 { return (0, 0, 0, 0) }
            let step = UInt8((x + y * 40) % 100)
            return (step, 255 - step, UInt8((Int(step) * 7) % 256), y > 14 ? 128 : 255)
        }
        let before = try #require(PalettePNG.pixels(of: image))
        #expect(try #require(PalettePNG.colourCount(image)) <= 256)
        let data = try #require(PalettePNG.data(image))
        let read = try #require(UIImage(data: data)?.cgImage)
        #expect(read.width == 40 && read.height == 20)
        let after = try #require(PalettePNG.pixels(of: read))
        #expect(after.count == before.count)
        var worst = 0
        for (was, now) in zip(before, after) {
            worst = max(worst, abs(Int(was.red) - Int(now.red)), abs(Int(was.green) - Int(now.green)), abs(Int(was.blue) - Int(now.blue)), abs(Int(was.alpha) - Int(now.alpha)))
        }
        // Half-clear colours come back through a multiply and a divide: within a step or two.
        #expect(worst <= 2, "worst channel off by \(worst)")
        #expect(after[0] == .clear && after[5 * 40 + 20].alpha == 255 && after[17 * 40 + 20].alpha == 128)
        // The same picture always makes the same bytes: nothing is rewritten, so nothing re-syncs.
        #expect(PalettePNG.data(image) == data)
    }

    @Test("A picture with more colours than a palette holds is not reduced: it stays full colour")
    func tooManyColours() throws {
        let rich = try Self.picture(width: 64, height: 64) { x, y in (UInt8(x * 4), UInt8(y * 4), UInt8((x + y) * 2), 255) }
        #expect(try #require(PalettePNG.colourCount(rich)) > 256)
        #expect(PalettePNG.data(rich) == nil)
        // Two such frames still make a strip, a full-colour one, with nothing lost.
        let strip = try #require(CharacterAnimationCodec.strip(of: [rich, rich], frameSide: 64))
        #expect(strip.frameCount == 2 && strip.image[25] == 6, "colour type 6: full colour with alpha")
        let read = try #require(UIImage(data: strip.image)?.cgImage)
        for x in [10, 64 + 10] {
            let pixel = Self.pixel(read, x: x, y: 20)
            #expect(zip(pixel, [40, 80, 60, 255]).allSatisfy { abs(Int($0) - $1) <= 3 }, "both frames keep their colours: \(pixel)")
        }
        #expect(PalettePNG.encode(width: 2, height: 2, palette: [], indices: [0, 0, 0, 0]) == nil)
        #expect(PalettePNG.encode(width: 2, height: 2, palette: [.clear], indices: [0]) == nil, "pixels that don't fill the picture")
    }

    // MARK: When it plays

    @Test("A play shows each frame in turn for its moment, then nothing: the still")
    func playback() {
        let step = CharacterAnimationCodec.frameDuration
        #expect(CharacterPlayback.frame(at: 0, frameCount: 9) == 0)
        #expect(CharacterPlayback.frame(at: step * 0.99, frameCount: 9) == 0)
        #expect(CharacterPlayback.frame(at: step * 1.01, frameCount: 9) == 1)
        #expect(CharacterPlayback.frame(at: step * 8.5, frameCount: 9) == 8)
        #expect(CharacterPlayback.frame(at: step * 9.01, frameCount: 9) == nil, "over: it never loops")
        #expect(CharacterPlayback.frame(at: 3600, frameCount: 9) == nil)
        #expect(CharacterPlayback.frame(at: -1, frameCount: 9) == nil, "not begun")
        #expect(CharacterPlayback.frame(at: 0, frameCount: 1) == nil && CharacterPlayback.frame(at: 0, frameCount: 0) == nil, "one frame is no animation")
        #expect(abs(CharacterPlayback.duration(frameCount: 9) - step * 9) < 0.0001)
        #expect(CharacterPlayback.duration(frameCount: 9) < 2, "a play is a moment")
        #expect(CharacterPlayback.rest >= 60, "then about a minute's rest")
    }

    @Test("A face plays only with frames, in front, large enough, and never under Reduce Motion")
    func whetherItPlays() {
        #expect(CharacterPlayback.plays(frameCount: 9, size: 66, reduceMotion: false, isActive: true))
        #expect(!CharacterPlayback.plays(frameCount: 9, size: 66, reduceMotion: true, isActive: true), "Reduce Motion: the still only")
        #expect(!CharacterPlayback.plays(frameCount: 9, size: 66, reduceMotion: false, isActive: false), "the app is not in front")
        #expect(!CharacterPlayback.plays(frameCount: nil, size: 66, reduceMotion: false, isActive: true), "no animation was drawn")
        #expect(!CharacterPlayback.plays(frameCount: 1, size: 66, reduceMotion: false, isActive: true))
        #expect(!CharacterPlayback.plays(frameCount: 9, size: 28, reduceMotion: false, isActive: true), "a small dot stays still")
        #expect(CharacterPlayback.plays(frameCount: 9, size: CharacterPlayback.smallestAnimated, reduceMotion: false, isActive: true))
    }
}
