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

    /// Hosts `screen` in `look`, lets it draw, and reads it.
    static func host(_ screen: some View, look: Look) async throws -> HostedScreen {
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
        let elements = read(host.view as Any)
        // As tall as the content, so the image is the whole page.
        let bottom = elements.map(\.frame.maxY).max() ?? size.height
        window.frame.size.height = min(max(size.height, bottom + 24), 8000)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return HostedScreen(elements: elements, image: image)
    }

    enum Failure: Error { case noScene }

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
