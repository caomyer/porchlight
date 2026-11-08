import SwiftUI
import UIKit

extension Color {
    /// This color laid at `opacity` over the paper surface, as a solid color.
    /// The Sunday Paper tint used for event blocks, chips and selected states.
    func wash(_ opacity: Double, over base: Color = Theme.surface) -> Color {
        let top = UIColor(self).rgba
        let bottom = UIColor(base).rgba
        return Color(
            .sRGB,
            red: bottom.r + (top.r - bottom.r) * opacity,
            green: bottom.g + (top.g - bottom.g) * opacity,
            blue: bottom.b + (top.b - bottom.b) * opacity
        )
    }
}

private extension UIColor {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * (lineSpacing ?? spacing)
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + (lineSpacing ?? spacing)
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// A rounded pill used for filters, choices and small actions (Week / Month, "Snap a meal").
struct Pill: View {
    let title: String
    var symbol: String? = nil
    var isSelected = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .semibold)) }
            Text(title).font(.body(15, weight: 700))
        }
        .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isSelected ? Theme.ink : Theme.surface2, in: Capsule())
        .contentShape(Capsule())
    }
}

/// A modal sheet on the wall: dims the screen and centers a paper card.
struct WallSheet<Content: View>: View {
    var width: CGFloat = 640
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color(hex: 0x14_0F0A).opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            content()
                .padding(26)
                .frame(width: width)
                .background(SurfaceShape(cornerRadius: 28, elevation: 2.5))
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 36, height: 36)
                            .background(Theme.surface2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(18)
                    .accessibilityLabel("Close")
                }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

/// Current weather in the Today header (STUB until weather lands).
struct WeatherBadge: View {
    var body: some View { EmptyView() }
}
