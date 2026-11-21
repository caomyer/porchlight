import SwiftUI
import UIKit

/// The phone's bottom sheet: an eyebrow saying what it is about ("Yo-Yo · evening
/// walk"), a serif title, the content, and one main button at the bottom. It is as
/// tall as what it holds, and scrolls only when that is more than the screen.
struct PhoneSheet<Content: View, Footer: View>: View {
    var label: String?
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    @State private var height: CGFloat = 320
    /// Grows to full height while the keyboard is up, so it never covers the button.
    @State private var detent: PresentationDetent = .large

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let label {
                    Text(label.uppercased())
                        .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                        .tracking(1.1)
                        .foregroundStyle(Theme.muted)
                }
                Text(title)
                    .phoneFont(.display, 22, weight: 600, relativeTo: .title2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                content()
                footer()
                    .padding(.top, 4)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Dragging the sheet's content puts the keyboard away, uncovering its button.
        .scrollDismissesKeyboard(.immediately)
        // A dish field in the sheet (Edit meal) stays over the keyboard as it suggests.
        .keepsDishFieldInView(proxy)
        }
        .presentationDetents([.height(height), .large], selection: $detent)
        .onAppear { detent = .height(height) }
        .onChange(of: height) { _, new in if detent != .large { detent = .height(new) } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in detent = .large }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in detent = .height(height) }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(26)
        .presentationBackground(Theme.surface)
    }
}

/// One of the wall's editors (a chore, a dinner) in a phone sheet. The editor brings its
/// own title and buttons and lays itself out for a compact width; closing it closes the
/// sheet, as it closes its wall sheet there.
struct PhoneEditorSheet<Editor: View>: View {
    @ViewBuilder var editor: () -> Editor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            editor()
                .padding(.horizontal, 18)
                .padding(.top, 26)
                .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .environment(\.closeWallSheet, CloseWallSheetAction { dismiss() })
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(26)
        .presentationBackground(Theme.surface)
    }
}

extension PhoneSheet where Footer == EmptyView {
    init(label: String? = nil, title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(label: label, title: title, content: content, footer: { EmptyView() })
    }
}
