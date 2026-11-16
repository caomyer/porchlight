import Observation
import SwiftUI
import UIKit

/// A short note at the top of the screen after something was logged, with one way to
/// take it back. Logging never asks "are you sure?"; it does it and offers Undo.
struct UndoToast: Identifiable {
    struct Action {
        let title: String
        let run: @MainActor () -> Void
    }

    let id = UUID()
    var emoji: String
    var title: String
    var detail: String?
    /// "Undo", or "I went too" when someone else had already done it.
    var action: Action?
}

/// Shows one toast at a time; a new one replaces the last. Toasts leave on their own,
/// later when VoiceOver is reading them.
@MainActor
@Observable
final class ToastCenter {
    private(set) var current: UndoToast?
    @ObservationIgnored private var timer: Task<Void, Never>?

    static let seconds: Double = 5
    static let voiceOverSeconds: Double = 12

    func show(_ toast: UndoToast) {
        withAnimation(.easeOut(duration: 0.2)) { current = toast }
        UIAccessibility.post(notification: .announcement, argument: [toast.title, toast.detail].compactMap { $0 }.joined(separator: ". "))
        timer?.cancel()
        let id = toast.id
        let seconds = UIAccessibility.isVoiceOverRunning ? Self.voiceOverSeconds : Self.seconds
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self?.current?.id == id else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        timer?.cancel()
        withAnimation(.easeIn(duration: 0.18)) { current = nil }
    }

    /// Runs the toast's action, then takes the toast away.
    func runAction() {
        guard let action = current?.action else { return }
        dismiss()
        action.run()
    }
}

extension View {
    /// Shows `center`'s toasts over this view, just under the status bar.
    func hostsToasts(_ center: ToastCenter) -> some View {
        overlay(alignment: .top) {
            if let toast = center.current {
                UndoToastView(toast: toast, onAction: center.runAction)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
            }
        }
    }
}

private struct UndoToastView: View {
    let toast: UndoToast
    let onAction: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            HStack(alignment: .center, spacing: 10) {
                Text(toast.emoji).phoneFont(.body, 20).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(toast.title)
                        .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                        .foregroundStyle(Theme.toastInk)
                    if let detail = toast.detail {
                        Text(detail)
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.toastMuted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if let action = toast.action {
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                Button(action: onAction) {
                    Text(action.title)
                        .phoneFont(.body, 13, weight: 800, relativeTo: .subheadline)
                        .foregroundStyle(Theme.toastAction)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toast-action")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, toast.action == nil ? 14 : 6)
        .padding(.vertical, toast.action == nil ? 12 : 2)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Theme.toast, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}
