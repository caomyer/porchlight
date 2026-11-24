import SwiftUI

/// Which week a page shows, and how to show another: Food's diary and a companion's week.
struct WeekPage {
    let weeksBack: Int
    /// The furthest back it goes: the week of the first thing there is to show.
    let limit: Int
    /// What VoiceOver reads for it: "Last week, Nov 8 to 14, 18 meals".
    let spoken: String
    let go: (Int) -> Void
}

/// A week's top row: "‹ Last week ›", with "Back to this week" when away from it. Back
/// stops at the first week there is; forward isn't there on this week, which ends today.
struct WeekPager: View {
    let page: WeekPage

    @PhoneMetric(upTo: 1.4) private var chevron: CGFloat = 36

    var body: some View {
        // The arrows and the week's name share one row and one centre line, at every text
        // size. "Back to this week" sits under the name in a row of its own, so it never
        // pulls the arrows down; its room is always kept, so the week below doesn't move
        // when stepping away from this week.
        let away = page.weeksBack > 0
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                arrow("chevron.left", label: "Previous week", id: "week-back", shown: page.weeksBack < page.limit) {
                    page.go(page.weeksBack + 1)
                }
                Text(WeekPaging.weekName(weeksBack: page.weeksBack))
                    .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    // Grown to the largest sizes, the words would crowd out the week they name.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .accessibilityLabel(page.spoken)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("week-name")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: if page.weeksBack > 0 { page.go(page.weeksBack - 1) }
                        case .decrement: if page.weeksBack < page.limit { page.go(page.weeksBack + 1) }
                        @unknown default: break
                        }
                    }
                arrow("chevron.right", label: "Next week", id: "week-forward", shown: page.weeksBack > 0) {
                    page.go(page.weeksBack - 1)
                }
            }
            // On this week it is invisible and out of reach. Tucked up a little: the name's
            // row is as tall as an arrow, taller than the name.
            Button("Back to this week") { page.go(0) }
                .phoneFont(.body, 12.5, weight: 800, relativeTo: .footnote)
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.top, -8)
                .opacity(away ? 1 : 0)
                .disabled(!away)
                .accessibilityHidden(!away)
                .accessibilityIdentifier("week-this")
        }
    }

    /// A round chevron, or the room for one so the name stays centered.
    @ViewBuilder
    private func arrow(_ symbol: String, label: String, id: String, shown: Bool, action: @escaping () -> Void) -> some View {
        if shown {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: chevron * 0.42, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: chevron, height: chevron)
                    .background(Theme.surface2, in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
        } else {
            Color.clear.frame(width: max(chevron, 44), height: 44).accessibilityHidden(true)
        }
    }
}
