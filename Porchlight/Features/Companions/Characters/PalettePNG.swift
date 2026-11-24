import CoreGraphics
import Foundation
import zlib

/// A PNG with a palette: each pixel one byte, an index into at most 256 colours, with a
/// clearness for each. A character's animation strip is pixel art cut from a GIF, which is
/// itself a palette picture, so its strip keeps every colour it has at about a third of the
/// bytes of a full-colour PNG (docs/design/companion-characters.md, "A mood's animation").
///
/// ImageIO reads such a PNG like any other but does not write one, so this writes it: the
/// header, the palette, the clearness of each colour, and the pixels deflated by zlib.
/// It never changes a colour: a picture with more than 256 is not written this way at all.
enum PalettePNG {
    /// One colour: red, green, blue, and how opaque, not multiplied together.
    struct Colour: Hashable, Sendable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8

        static let clear = Colour(red: 0, green: 0, blue: 0, alpha: 0)
    }

    /// The most colours a palette holds.
    static let maxColours = 256

    /// `image` as a palette PNG, exactly: every pixel the colour it was. Nil when it has more
    /// than 256 colours (then it stays a full-colour PNG, with nothing lost), or can't be read.
    static func data(_ image: CGImage) -> Data? {
        guard let pixels = pixels(of: image), let (palette, indices) = indexed(pixels) else { return nil }
        return encode(width: image.width, height: image.height, palette: palette, indices: indices)
    }

    /// How many different colours a picture has, every fully clear pixel counting as one.
    static func colourCount(_ image: CGImage) -> Int? {
        pixels(of: image).map { Set($0).count }
    }

    // MARK: Pixels

    /// Every pixel, row by row from the top. Clear pixels are all the one clear colour,
    /// whatever colour lay under their clearness.
    static func pixels(of image: CGImage) -> [Colour]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = [Colour](repeating: .clear, count: width * height)
        for index in 0..<(width * height) {
            let alpha = bytes[index * 4 + 3]
            guard alpha > 0 else { continue }
            // The context multiplied colour by clearness; undo it, so a soft edge keeps its colour.
            func plain(_ value: UInt8) -> UInt8 {
                alpha == 255 ? value : UInt8(min(255, (Int(value) * 255 + Int(alpha) / 2) / Int(alpha)))
            }
            pixels[index] = Colour(red: plain(bytes[index * 4]), green: plain(bytes[index * 4 + 1]), blue: plain(bytes[index * 4 + 2]), alpha: alpha)
        }
        return pixels
    }

    // MARK: The palette

    /// The palette and each pixel's place in it, or nil when the picture has more colours than
    /// a palette holds. Most used colours first: a stable order whatever order they are met in.
    static func indexed(_ pixels: [Colour]) -> (palette: [Colour], indices: [UInt8])? {
        var counts: [Colour: Int] = [:]
        for pixel in pixels {
            counts[pixel, default: 0] += 1
            if counts.count > maxColours { return nil }
        }
        let palette = counts.sorted { ($0.value, key($1.key)) > ($1.value, key($0.key)) }.map(\.key)
        let place = Dictionary(uniqueKeysWithValues: palette.enumerated().map { ($1, UInt8($0)) })
        return (palette, pixels.map { place[$0] ?? 0 })
    }

    private static func key(_ colour: Colour) -> UInt32 {
        UInt32(colour.alpha) << 24 | UInt32(colour.red) << 16 | UInt32(colour.green) << 8 | UInt32(colour.blue)
    }

    // MARK: The file

    /// The PNG's bytes: signature, header, palette, each colour's clearness, pixels, end.
    static func encode(width: Int, height: Int, palette: [Colour], indices: [UInt8]) -> Data? {
        guard width > 0, height > 0, !palette.isEmpty, palette.count <= maxColours, indices.count == width * height else { return nil }
        var header = Data()
        header.append(bigEndian: UInt32(width))
        header.append(bigEndian: UInt32(height))
        // Eight bits a pixel, palette colour, deflate, the standard filters, not interlaced.
        header.append(contentsOf: [8, 3, 0, 0, 0])

        // Each row starts with its filter: none. Flat pixel art deflates best unfiltered.
        var rows = Data(capacity: (width + 1) * height)
        indices.withUnsafeBufferPointer { buffer in
            for row in 0..<height {
                rows.append(0)
                rows.append(UnsafeBufferPointer(rebasing: buffer[(row * width)..<((row + 1) * width)]))
            }
        }
        guard let deflated = deflate(rows) else { return nil }

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(chunk("IHDR", header))
        png.append(chunk("PLTE", Data(palette.flatMap { [$0.red, $0.green, $0.blue] })))
        // Clearness only as far as the last colour that isn't opaque; the rest are opaque.
        if let last = palette.lastIndex(where: { $0.alpha != 255 }) {
            png.append(chunk("tRNS", Data(palette[...last].map(\.alpha))))
        }
        png.append(chunk("IDAT", deflated))
        png.append(chunk("IEND", Data()))
        return png
    }

    private static func chunk(_ type: String, _ body: Data) -> Data {
        var chunk = Data()
        chunk.append(bigEndian: UInt32(body.count))
        let typed = Data(type.utf8) + body
        chunk.append(typed)
        let check = typed.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
        chunk.append(bigEndian: UInt32(check))
        return chunk
    }

    /// zlib's deflate, at its most thorough: a strip is written once and read many times.
    private static func deflate(_ data: Data) -> Data? {
        var length = compressBound(uLong(data.count))
        var out = Data(count: Int(length))
        let status = out.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compress2(target.bindMemory(to: Bytef.self).baseAddress, &length, source.bindMemory(to: Bytef.self).baseAddress, uLong(data.count), Z_BEST_COMPRESSION)
            }
        }
        guard status == Z_OK else { return nil }
        out.count = Int(length)
        return out
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}
