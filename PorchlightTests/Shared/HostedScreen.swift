import SwiftUI
import UIKit

/// A whole screen hosted in a phone-sized window inside the unit tests' host app: no
/// launch, no XCUITest. It gives the screen's accessibility elements with their labels and
/// frames (scrolled-off content included, since a scroll view's content is all laid out)
/// and an image of the whole page, in any look, in about a second
/// (docs/design/testing.md, "The middle options").
///
/// What it is not: the screen has no status bar, tab bar, navigation bar or sheet around
/// it, nothing is hit-tested, and no gesture runs. Whether a button can be tapped, a sheet
/// closes or content hides under the keyboard stays with the UI tests.
@MainActor
struct HostedScreen {
    struct Look: CustomStringConvertible {
        var name: String
        var style: UIUserInterfaceStyle
        var textSize: UIContentSizeCategory

        static let light = Look(name: "light", style: .light, textSize: .large)
        static let dark = Look(name: "dark", style: .dark, textSize: .large)
        static let largest = Look(name: "largest", style: .light, textSize: .accessibilityExtraExtraExtraLarge)
        static let largestDark = Look(name: "largest-dark", style: .dark, textSize: .accessibilityExtraExtraExtraLarge)

        static func named(_ name: String) -> Look {
            [light, dark, largest, largestDark].first { $0.name == name } ?? light
        }

        var description: String { name }
    }

    struct Element {
        var label: String
        /// A button, as opposed to text or an image.
        var isButton = false
        /// In the window's coordinates; below `HostedScreen.size.height` is scrolled off.
        var frame: CGRect
    }

    /// An iPhone 15, in points.
    static let size = CGSize(width: 393, height: 852)

    let elements: [Element]
    /// The whole page, as tall as its content.
    let image: UIImage

    /// The first element whose label begins with `prefix`.
    func element(beginningWith prefix: String) -> Element? {
        elements.first { $0.label.hasPrefix(prefix) }
    }

    /// The elements that run off either side of the screen; none, on a screen that fits.
    var offSides: [Element] {
        elements.filter { $0.frame.minX < 0 || $0.frame.maxX > Self.size.width }
    }

    /// Writes the page to `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder>` as `<name>.png`, when
    /// that is set for `xcodebuild test`: the review shots (docs/design/testing.md).
    func saveShot(_ name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["PORCHLIGHT_SCREEN_SHOTS"] else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try image.pngData()?.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// Every element, a line each, for a failure's message.
    var listing: String {
        elements.map { "\($0.isButton ? "button" : "text") \"\($0.label.prefix(50))\" \($0.frame.integral)" }.joined(separator: "\n")
    }

    /// Hosts `screen` in `look`, lets it draw, and reads it. With `activating`, the element
    /// whose label begins with that is activated first, as a tap or VoiceOver's double tap
    /// would (a tab picked, a section opened), and the screen is read after it has redrawn.
    static func host(_ screen: some View, look: Look, activating: String? = nil) async throws -> HostedScreen {
        enableAccessibility()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw Failure.noScene
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: screen)
        host.overrideUserInterfaceStyle = look.style
        host.traitOverrides.preferredContentSizeCategory = look.textSize
        // The unit tests run on the iPad simulator; the phone's screens lay out for a phone.
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        // A few turns of the main loop: the stores' first read and the lazy content.
        for _ in 0..<5 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        if let activating {
            guard let target = find(host.view as Any, beginningWith: activating), target.accessibilityActivate() else {
                throw Failure.nothingToActivate(activating)
            }
            for _ in 0..<3 {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let elements = read(host.view as Any)
        let image = try await picture(of: window, elements: elements)
        return HostedScreen(elements: elements, image: image)
    }

    enum Failure: Error, CustomStringConvertible {
        case noScene
        case nothingToActivate(String)
        /// The picture has nothing drawn where the page has words: from this many points
        /// down to this many.
        case blankPicture(from: Int, to: Int, of: Int)

        var description: String {
            switch self {
            case .noScene: "The unit tests' host has no window scene to host a screen in"
            case let .nothingToActivate(label): "Nothing to activate beginning with \"\(label)\""
            case let .blankPicture(from, to, of):
                "The page's picture is blank from \(from) to \(to) points down (of \(of)), where the page has words: the shot would be an empty image"
            }
        }
    }

    /// The tallest piece drawn at once, in points. `drawHierarchy` gives back a blank picture,
    /// with no error, once what it draws is taller than about 8192 pixels, which at this
    /// simulator's two pixels a point is 4096 points: a long page at the largest text size
    /// is past that (Free together's fourteen rows came to about 5,400 points on November
    /// 22, 2026, and its saved shot was an empty image while every check passed).
    static let tallestDrawn: CGFloat = 2400

    /// The whole page as one image, however tall. A page that fits in one piece is drawn in
    /// a window as tall as its content. A taller one is drawn in pieces: the window is kept
    /// at one piece's height, the page's scroll view is moved a piece at a time, and each
    /// piece is put in its place in one tall image. Then the image is checked against the
    /// page: where the page has words, the picture must have something drawn, and a picture
    /// that is blank there fails the test instead of being saved as a shot.
    private static func picture(of window: UIWindow, elements: [Element]) async throws -> UIImage {
        let bottom = elements.map(\.frame.maxY).max() ?? size.height
        let height = max(size.height, bottom + 24)
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        func drawn() async throws -> UIImage {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        var image: UIImage
        if height <= tallestDrawn {
            window.frame.size.height = height
            image = try await drawn()
        } else if let scroll = tallestScrollView(in: window) {
            window.frame.size.height = tallestDrawn
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            // Where the scroll view sits in the window, and how far its content goes.
            let port = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            let top = -scroll.adjustedContentInset.top
            let last = max(top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            let whole = CGSize(width: size.width, height: port.minY + (last - top) + port.height)
            var pieces: [(image: UIImage, at: CGFloat)] = []
            var offset = top
            while true {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                pieces.append((try await drawn(), offset - top))
                if offset >= last { break }
                offset = min(offset + port.height, last)
            }
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: false)
            image = UIGraphicsImageRenderer(size: whole, format: format).image { context in
                for (index, piece) in pieces.enumerated() {
                    // The first piece brings what is above the scroll view with it; the others
                    // only the part of the window the scroll view shows.
                    let source = index == 0 ? CGRect(x: 0, y: 0, width: size.width, height: port.maxY) : port
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: CGRect(x: source.minX, y: source.minY + piece.at, width: source.width, height: source.height))
                    piece.image.draw(at: CGPoint(x: 0, y: piece.at))
                    context.cgContext.restoreGState()
                }
            }
        } else {
            // No scroll view to move: the top of the page, as much as can be drawn.
            window.frame.size.height = tallestDrawn
            image = try await drawn()
        }
        try checkNotBlank(image, against: elements)
        return image
    }

    /// The scroll view with the most content below its own height: the page's.
    private static func tallestScrollView(in view: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func look(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height,
               scroll.contentSize.height > (best?.contentSize.height ?? 0) {
                best = scroll
            }
            view.subviews.forEach(look)
        }
        look(view)
        return best
    }

    /// Fails when a stretch of the picture that the page has words in is one flat colour.
    /// The picture is looked at in bands of 400 points; a band counts when an element with a
    /// label sits wholly inside it and inside the picture.
    static func checkNotBlank(_ image: UIImage, against elements: [Element]) throws {
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return }
        let scale = image.scale, perPixel = cgImage.bitsPerPixel / 8, perRow = cgImage.bytesPerRow
        let band: CGFloat = 400
        var y: CGFloat = 0
        while y < image.size.height {
            let stretch = CGRect(x: 0, y: y, width: image.size.width, height: min(band, image.size.height - y))
            defer { y += band }
            guard elements.contains(where: { !$0.label.isEmpty && $0.frame.height >= 8 && stretch.contains($0.frame) }) else { continue }
            var first: [UInt8]?
            var varied = false
            var row = Int(stretch.minY * scale)
            let lastRow = min(Int(stretch.maxY * scale), cgImage.height) - 1
            while row <= lastRow, !varied {
                var column = 0
                while column < cgImage.width {
                    let at = row * perRow + column * perPixel
                    let pixel = [bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]]
                    if let first { if pixel != first { varied = true; break } } else { first = pixel }
                    column += 6
                }
                row += 6
            }
            if !varied { throw Failure.blankPicture(from: Int(stretch.minY), to: Int(stretch.maxY), of: Int(image.size.height)) }
        }
    }

    private static func find(_ root: Any, beginningWith prefix: String, depth: Int = 0) -> NSObject? {
        guard depth < 40, let object = root as? NSObject else { return nil }
        if object.isAccessibilityElement, (object.accessibilityLabel ?? "").hasPrefix(prefix) { return object }
        let children: [Any] = object.accessibilityElements ?? (object as? UIView)?.subviews ?? []
        for child in children {
            if let found = find(child, beginningWith: prefix, depth: depth + 1) { return found }
        }
        return nil
    }

    /// SwiftUI builds its accessibility tree only for a client that asks: VoiceOver, or
    /// automation. This is the switch XCUITest flips in an app it drives. It is a private
    /// call, made only in the test bundle; without it every hosted screen reads as empty, so
    /// a test must check that it found elements rather than pass on nothing.
    private static func enableAccessibility() {
        typealias Setter = @convention(c) (Int32) -> Void
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(library, "_AXSSetAutomationEnabled") else { return }
        unsafeBitCast(symbol, to: Setter.self)(1)
    }

    private static func read(_ root: Any, depth: Int = 0) -> [Element] {
        guard depth < 40, let object = root as? NSObject else { return [] }
        var found: [Element] = []
        if object.isAccessibilityElement {
            found.append(Element(
                label: object.accessibilityLabel ?? "", isButton: object.accessibilityTraits.contains(.button), frame: object.accessibilityFrame
            ))
        }
        if let children = object.accessibilityElements {
            for child in children { found += read(child, depth: depth + 1) }
        } else if let view = object as? UIView {
            for child in view.subviews { found += read(child, depth: depth + 1) }
        }
        return found
    }
}
