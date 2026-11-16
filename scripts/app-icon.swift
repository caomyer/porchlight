// Draws Porchlight's app icon. Run: swift scripts/app-icon.swift Porchlight/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// The app icon: the rail's logo (a white house on the accent) at 1024 px, opaque, as
// iOS wants. iOS rounds the corners itself.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
let top = CGColor(srgbRed: 0xE4 / 255, green: 0x76 / 255, blue: 0x4C / 255, alpha: 1)
let bottom = CGColor(srgbRed: 0xCF / 255, green: 0x5A / 255, blue: 0x31 / 255, alpha: 1)
let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: .zero, options: [])

let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
    .applying(.init(paletteColors: [NSColor(srgbRed: 1, green: 0.988, blue: 0.965, alpha: 1)]))
let house = NSImage(systemSymbolName: "house.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
var proposed = NSRect(origin: .zero, size: house.size)
let symbol = house.cgImage(forProposedRect: &proposed, context: nil, hints: nil)!
let width = CGFloat(symbol.width), height = CGFloat(symbol.height)
let scale = 560 / max(width, height)
let drawn = CGSize(width: width * scale, height: height * scale)
context.draw(symbol, in: CGRect(x: (CGFloat(size) - drawn.width) / 2, y: (CGFloat(size) - drawn.height) / 2 - 10, width: drawn.width, height: drawn.height))

let image = context.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
