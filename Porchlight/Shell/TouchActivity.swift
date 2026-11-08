import SwiftUI
import UIKit

extension View {
    /// Calls `action` whenever a finger or Pencil touches the window, anywhere.
    ///
    /// The observer sits on the window as a UIKit recognizer that never recognizes,
    /// never cancels or delays touches, and can neither prevent nor be prevented by
    /// other gestures. A SwiftUI gesture on the wall would instead join gesture
    /// arbitration, and on iOS 17 a parent drag gesture steals pans from scroll views.
    func onAnyTouch(_ action: @escaping @MainActor () -> Void) -> some View {
        background(TouchActivityInstaller(action: action).allowsHitTesting(false))
    }
}

private struct TouchActivityInstaller: UIViewRepresentable {
    let action: @MainActor () -> Void

    func makeUIView(context: Context) -> InstallerView {
        InstallerView(action: action)
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.observer.action = action
    }

    final class InstallerView: UIView {
        let observer: TouchActivityRecognizer

        init(action: @escaping @MainActor () -> Void) {
            observer = TouchActivityRecognizer(action: action)
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observer.view?.removeGestureRecognizer(observer)
            window?.addGestureRecognizer(observer)
        }
    }
}

/// Watches touches without ever taking part in recognition.
final class TouchActivityRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var action: @MainActor () -> Void
    /// Touch moves arrive every frame; reporting once a second is plenty for an idle timer.
    private var lastReport = Date.distantPast

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        report(force: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        report(force: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        report(force: true)
        if numberOfTouches == touches.count { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if numberOfTouches == touches.count { state = .failed }
    }

    private func report(force: Bool) {
        let now = Date.now
        guard force || now.timeIntervalSince(lastReport) >= 1 else { return }
        lastReport = now
        action()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
