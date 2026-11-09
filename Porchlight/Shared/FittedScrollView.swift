import SwiftUI

/// A vertical scroll view only as tall as its content, up to the space it's offered.
/// A sheet stays its natural size and scrolls only when the screen, or the keyboard,
/// leaves too little room.
struct FittedScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HeightCap {
            ScrollView(showsIndicators: false) {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Sizes its one subview to its ideal height, capped at the proposed height.
private struct HeightCap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let ideal = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let limit = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? ideal.height
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal.width, height: min(ideal.height, limit))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
