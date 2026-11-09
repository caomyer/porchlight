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
///
/// Always reports a finite size: a parent that probes with an unbounded width (an
/// HStack weighing a Spacer does) gets the widest row back, not infinity, which would
/// otherwise make the parent re-lay out without ever settling.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat? = nil

    struct Cache {
        var sizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let rows = arrange(cache.sizes, width: proposal.width ?? .infinity)
        let contentWidth = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * (lineSpacing ?? spacing)
        // Fill a finite proposal so leading-aligned rows sit flush; never claim infinity.
        let width = proposal.width.flatMap { $0.isFinite ? max($0, 0) : nil } ?? contentWidth
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var y = bounds.minY
        for row in arrange(cache.sizes, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = cache.sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + (lineSpacing ?? spacing)
        }
    }

    // The default implementations place every subview to merge their guides, which
    // nested inside stacks that probe repeatedly multiplies into a hang. Flow rows
    // have no guide worth exposing, so parents use the frame's edges.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? {
        nil
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? {
        nil
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ sizes: [CGSize], width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, size) in sizes.enumerated() {
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
    /// Sheets whose text fields sit near the top stay put when the keyboard opens;
    /// re-centering them above the keyboard would push their top off screen.
    var staysAboveKeyboard = false
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
        .ignoresSafeArea(staysAboveKeyboard ? .keyboard : [])
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

/// The avatar for an owner: the person's colored initial, or a heart for the
/// whole household ("Both" / "Anyone").
struct OwnerAvatar: View {
    @Environment(AppModel.self) private var model
    let owner: Owner
    /// People to look the owner up in; defaults to the household's people.
    var people: [Person]? = nil
    var size: CGFloat = 30

    var body: some View {
        switch owner {
        case let .person(id):
            if let person = (people ?? model.people).first(where: { $0.id == id }) {
                Avatar(person: person, size: size)
            } else {
                AnyoneAvatar(size: size)
            }
        case .everyone:
            AnyoneAvatar(size: size)
        }
    }
}

/// The whole-household avatar: a white heart on the shared color.
struct AnyoneAvatar: View {
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.everyone, in: Circle())
            .accessibilityHidden(true)
    }
}
