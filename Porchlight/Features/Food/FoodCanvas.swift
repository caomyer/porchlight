import PencilKit
import SwiftUI

/// The ink of one page while it is being written on, with undo. The drawing is
/// always kept in page coordinates; canvases convert at their own zoom.
@MainActor
@Observable
final class PageEditor: StoredFirstObservable {
    let day: DayKey
    @ObservationIgnored @StoredFirst private(set) var drawing: PKDrawing
    /// Bumped when the drawing changes from outside a canvas (undo), so canvases reload.
    private(set) var revision = 0
    @ObservationIgnored @StoredFirst private(set) var hasChanges = false
    private var history: [PKDrawing] = []

    init(day: DayKey, drawing: PKDrawing) {
        self.day = day
        self.drawing = drawing
    }

    var canUndo: Bool { !history.isEmpty }

    /// Called by a canvas after the user drew or erased.
    func userChanged(to newDrawing: PKDrawing) {
        history.append(drawing)
        if history.count > 200 { history.removeFirst() }
        drawing = newDrawing
        hasChanges = true
    }

    /// The ink was saved; later changes count as new.
    func markSaved() {
        hasChanges = false
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        drawing = previous
        hasChanges = true
        revision += 1
    }

}

/// A PencilKit canvas showing part of a page through `viewport`. Strokes are converted
/// to page coordinates as they are drawn, so the same ink fits every zoom level.
struct PageCanvas: UIViewRepresentable {
    let editor: PageEditor
    /// Pass `editor.revision` so SwiftUI updates the canvas after undo.
    let revision: Int
    let viewport: PageViewport
    let ink: PageInk
    let tip: PenTip
    let isErasing: Bool
    let allowsFinger: Bool

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.delegate = context.coordinator
        canvas.accessibilityIdentifier = "dayPageCanvas"
        context.coordinator.load(into: canvas, viewport: viewport, revision: revision)
        apply(to: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.viewport != viewport || coordinator.revision != revision {
            coordinator.load(into: canvas, viewport: viewport, revision: revision)
        }
        apply(to: canvas)
    }

    private func apply(to canvas: PKCanvasView) {
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = allowsFinger ? .anyInput : .pencilOnly
        #endif
        canvas.tool = isErasing ? PKEraserTool(.vector) : tip.tool(ink: ink, zoom: viewport.scale)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let editor: PageEditor
        var viewport = PageViewport(scale: 1, origin: .zero)
        var revision = -1
        /// Changes only count once the user has touched the canvas since the last load;
        /// PencilKit may report a change for a drawing we set ourselves.
        private var userHasDrawn = false

        init(editor: PageEditor) {
            self.editor = editor
        }

        func load(into canvas: PKCanvasView, viewport: PageViewport, revision: Int) {
            self.viewport = viewport
            self.revision = revision
            userHasDrawn = false
            canvas.drawing = editor.drawing.inView(viewport)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            userHasDrawn = true
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard userHasDrawn else { return }
            editor.userChanged(to: canvasView.drawing.inPage(from: viewport))
        }
    }
}
