import ImageIO
import UIKit

/// Pictures drawn in code for the sample household, previews and tests: a "photo" of a dog
/// on a lawn, and the sticker cut from it. The repository holds no real pet's picture.
enum CharacterPlaceholders {
    /// A 600 by 600 JPEG of a round brown dog sitting on grass under a pale sky.
    static func photo() -> Data {
        let side: CGFloat = 600
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.80, green: 0.89, blue: 0.95, alpha: 1).cgColor, UIColor(red: 0.93, green: 0.95, blue: 0.90, alpha: 1).cgColor]
            if let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: side * 0.62), options: [])
            }
            UIColor(red: 0.55, green: 0.72, blue: 0.42, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: side * 0.62, width: side, height: side * 0.38))
            let coat = UIColor(red: 0.74, green: 0.52, blue: 0.33, alpha: 1)
            let shade = UIColor(red: 0.58, green: 0.38, blue: 0.22, alpha: 1)
            coat.setFill()
            cg.fillEllipse(in: CGRect(x: 190, y: 300, width: 220, height: 230))
            shade.setFill()
            cg.fillEllipse(in: CGRect(x: 168, y: 160, width: 70, height: 140))
            cg.fillEllipse(in: CGRect(x: 362, y: 160, width: 70, height: 140))
            coat.setFill()
            cg.fillEllipse(in: CGRect(x: 205, y: 120, width: 190, height: 190))
            UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 250, y: 220, width: 100, height: 70))
            UIColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 252, y: 195, width: 18, height: 18))
            cg.fillEllipse(in: CGRect(x: 330, y: 195, width: 18, height: 18))
            cg.fillEllipse(in: CGRect(x: 287, y: 228, width: 26, height: 18))
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }

    /// The sticker of `photo()`, cut by a drawn mask around the dog rather than by Vision,
    /// so it is the same on any device and in the simulator.
    static func sticker() -> Data? {
        guard let photo = PhotoSticker.image(from: photo()) else { return nil }
        let size = 150
        var values = [Float](repeating: 0, count: size * size)
        // The dog's outline on the 600 square, at a quarter of the size.
        let parts: [CGRect] = [
            CGRect(x: 190, y: 300, width: 220, height: 230), CGRect(x: 168, y: 160, width: 70, height: 140),
            CGRect(x: 362, y: 160, width: 70, height: 140), CGRect(x: 205, y: 120, width: 190, height: 190),
        ]
        for y in 0..<size {
            for x in 0..<size {
                let point = CGPoint(x: (CGFloat(x) + 0.5) * 4, y: (CGFloat(y) + 0.5) * 4)
                if parts.contains(where: { rect in
                    let dx = (point.x - rect.midX) / (rect.width / 2), dy = (point.y - rect.midY) / (rect.height / 2)
                    return dx * dx + dy * dy <= 1
                }) { values[y * size + x] = 1 }
            }
        }
        let grid = MaskGrid(width: size, height: size, values: values)
        guard let mask = grid.image(), let box = grid.bounds(),
              let result = try? PhotoSticker.render(photo: photo, subject: Subject(mask: mask, bounds: box, others: 0, touchesEdge: false))
        else { return nil }
        return result.sticker
    }

    // MARK: Sprites for the stand-in relay

    /// Frames in a placeholder animation, as many as the relay's.
    static let frameCount = 9

    /// Coat colours, one per try, so three tries look different and a mood matches its try.
    private static let coats: [(UInt8, UInt8, UInt8)] = [
        (196, 132, 82), (232, 196, 140), (92, 70, 58), (170, 170, 176), (214, 120, 60), (150, 104, 72),
        (240, 226, 200), (60, 52, 48), (204, 160, 110),
    ]

    /// A pixel sprite of a dog or cat in a mood, 512 pixels square on clear, as a PNG: a
    /// stand-in for a drawn character, made of 32 by 32 blocks.
    static func sprite(species: CharacterSpecies, variant: Int, mood: CharacterMood, frame: Int = 0) -> Data? {
        let grid = 32, block = 16
        let coat = coats[((variant % coats.count) + coats.count) % coats.count]
        var cells = [[(UInt8, UInt8, UInt8)?]](repeating: Array(repeating: nil, count: grid), count: grid)
        func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ colour: (UInt8, UInt8, UInt8)) {
            for y in max(0, y0)...min(grid - 1, y1) { for x in max(0, x0)...min(grid - 1, x1) { cells[y][x] = colour } }
        }
        let ink: (UInt8, UInt8, UInt8) = (40, 30, 24), white: (UInt8, UInt8, UInt8) = (255, 255, 255)
        let lift = mood == .zoomies ? (frame % 3 == 1 ? -2 : 0) : (frame % 4 == 2 ? -1 : 0)
        let lying = mood == .asleep
        // Body and head, sitting up, or lying down asleep.
        if lying {
            fill(6, 20, 25, 27, coat)
            fill(4, 15, 13, 24, coat)
        } else {
            fill(10, 17 + lift, 21, 28 + lift, coat)
            fill(9, 7 + lift, 22, 17 + lift, coat)
        }
        // Ears: floppy for a dog, pointed for a cat.
        let headTop = lying ? 15 : 7 + lift
        let headLeft = lying ? 4 : 9, headRight = lying ? 13 : 22
        if species == .dog {
            fill(headLeft - 2, headTop + 1, headLeft, headTop + 6, (coat.0 / 4 * 3, coat.1 / 4 * 3, coat.2 / 4 * 3))
            fill(headRight, headTop + 1, headRight + 2, headTop + 6, (coat.0 / 4 * 3, coat.1 / 4 * 3, coat.2 / 4 * 3))
        } else {
            fill(headLeft, headTop - 3, headLeft + 2, headTop - 1, coat)
            fill(headRight - 2, headTop - 3, headRight, headTop - 1, coat)
        }
        // Eyes: open, or closed lines asleep.
        let eyeY = headTop + 4
        if lying {
            fill(headLeft + 2, eyeY, headLeft + 3, eyeY, ink)
            fill(headLeft + 6, eyeY, headLeft + 7, eyeY, ink)
            fill(17, 9 - frame % 3, 18, 10 - frame % 3, (120, 140, 200))
        } else {
            let blink = frame == 4
            fill(headLeft + 3, eyeY, headLeft + 4, eyeY + (blink ? 0 : 1), ink)
            fill(headRight - 4, eyeY, headRight - 3, eyeY + (blink ? 0 : 1), ink)
            fill((headLeft + headRight) / 2 - 1, eyeY + 3, (headLeft + headRight) / 2, eyeY + 4, ink)
        }
        // What the mood holds: a leash waiting, motion lines with the zoomies.
        if mood == .waiting { fill(16, 18 + lift, 17, 26 + lift, (200, 60, 60)) }
        if mood == .zoomies {
            for (row, length) in [(19, 4), (22, 6), (25, 3)] { fill(2, row, 2 + length - (frame % 2), row, (180, 180, 190)) }
        }
        _ = white
        let side = grid * block
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<grid {
            for x in 0..<grid {
                guard let colour = cells[y][x] else { continue }
                for py in 0..<block {
                    for px in 0..<block {
                        let at = ((y * block + py) * side + x * block + px) * 4
                        bytes[at] = colour.0; bytes[at + 1] = colour.1; bytes[at + 2] = colour.2; bytes[at + 3] = 255
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return PhotoSticker.png(image)
    }

    /// Which try a sprite was: read back from its coat at the middle of its body.
    static func variant(of sprite: Data) -> Int? {
        guard let image = UIImage(data: sprite)?.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Block (15, 22) is body sitting or lying.
        let x = 15 * 16 + 8, y = 22 * 16 + 8
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return coats.firstIndex { abs(Int($0.0) - Int(pixel[0])) < 6 && abs(Int($0.1) - Int(pixel[1])) < 6 && abs(Int($0.2) - Int(pixel[2])) < 6 }
    }

    /// A placeholder animation: `frameCount` sprites of the mood as a looping GIF, as the relay sends.
    static func animation(species: CharacterSpecies, variant: Int, mood: CharacterMood) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, frameCount, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frameCount {
            guard let png = sprite(species: species, variant: variant, mood: mood, frame: frame),
                  let image = UIImage(data: png)?.cgImage else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.12]] as CFDictionary)
        }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
