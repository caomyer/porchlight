import SwiftUI

/// The phone's bottom sheet: an eyebrow saying what it is about ("Yo-Yo · evening
/// walk"), a serif title, the content, and one main button at the bottom. It is as
/// tall as what it holds, and scrolls only when that is more than the screen.
struct PhoneSheet<Content: View, Footer: View>: View {
    var label: String?
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    @State private var height: CGFloat = 320

    var body: some View {
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
        .presentationDetents([.height(height)])
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
