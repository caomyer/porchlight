#if DEBUG
import SwiftUI
import PencilKit
import UIKit

/// `-debugSnapshot <name>`: a few seconds after launch, saves a PNG of the whole
/// window to `<AppFiles.root>/Snapshots/<name>.png`. Used to review the real
/// iPad's rendering (copy the folder off the device with `devicectl`).
/// Only for sandboxed sample launches, never on real data.
enum DebugSnapshot {
    static var requestedName: String? {
        guard AppFiles.isSandboxed else { return nil }
        return UserDefaults.standard.string(forKey: "debugSnapshot")
    }

    @MainActor
    static func captureIfRequested() async {
        guard let name = requestedName else { return }
        let delay = UserDefaults.standard.double(forKey: "debugSnapshotDelay")
        try? await Task.sleep(for: .seconds(delay > 0 ? delay : 8))
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let folder = AppFiles.folder("Snapshots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: folder.appendingPathComponent("\(name).png"))

        // PencilKit draws with Metal, which window snapshots can miss. Record what each
        // canvas actually holds, and PencilKit's own rendering of it, alongside.
        var report: [String] = []
        for (index, canvas) in canvases(in: window).enumerated() {
            let drawing = canvas.drawing
            report.append("canvas \(index): strokes=\(drawing.strokes.count) bounds=\(drawing.bounds) frame=\(canvas.frame) zoom=\(canvas.zoomScale) policy=\(canvas.drawingPolicy.rawValue) hidden=\(canvas.isHidden) alpha=\(canvas.alpha)")
            let rendered = drawing.image(from: CGRect(origin: .zero, size: canvas.bounds.size), scale: 2)
            try? rendered.pngData()?.write(to: folder.appendingPathComponent("\(name)-canvas\(index).png"))
        }
        try? report.joined(separator: "\n").write(to: folder.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }

    private static func canvases(in view: UIView) -> [PKCanvasView] {
        if let canvas = view as? PKCanvasView { return [canvas] }
        return view.subviews.flatMap(canvases(in:))
    }
}
#endif
