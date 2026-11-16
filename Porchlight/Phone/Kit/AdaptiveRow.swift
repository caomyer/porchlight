import SwiftUI

/// A row that becomes a column at accessibility text sizes, so two pieces of text never
/// wrap side by side: a title and its count, a time and its event.
struct AdaptiveRow<Content: View>: View {
    var spacing: CGFloat = 10
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content() }
    }
}

/// Someone's share as a bar: avatar, name, bar, count. At accessibility sizes the bar
/// moves under the name and count.
struct PersonBarRow<Avatar: View>: View {
    let name: String
    let count: Int
    let fraction: Double
    let color: Color
    @ViewBuilder var avatar: () -> Avatar

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        avatar()
                        nameText.frame(maxWidth: .infinity, alignment: .leading)
                        countText
                    }
                    bar
                }
            } else {
                HStack(spacing: 8) {
                    avatar()
                    nameText.frame(minWidth: 70, alignment: .leading)
                    bar
                    countText
                }
            }
        }
        .frame(minHeight: 32)
    }

    private var nameText: some View {
        Text(name).phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
    }

    private var countText: some View {
        Text("\(count)")
            .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
            .monospacedDigit()
    }

    private var bar: some View {
        ProgressBar(fraction: fraction, fill: AnyShapeStyle(color), height: 8, track: Theme.surface2)
    }
}
