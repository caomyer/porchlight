import SwiftUI

// Small pieces the wall and the phone share for the shared calendar
// (docs/design/calendar-shared.md, "Showing").

/// Each owner's face, overlapping a little: one event two people have shows both.
struct OwnerFaces: View {
    let owners: [Owner]
    let people: [Person]
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(owners.enumerated()), id: \.offset) { _, owner in
                OwnerAvatar(owner: owner, people: people, size: size)
                    .background(Circle().fill(Theme.surface).padding(-1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(owners.map { ownerName($0, people: people) }.joined(separator: " and "))
    }
}

/// The quiet "updated Tuesday" line for each device whose calendars are over a day old.
struct StaleCalendarLines: View {
    let sources: [StaleCalendarSource]
    var fontSize: CGFloat = 13

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sources) { source in
                    // The phone's grows with the reader's text size; the wall's stays fixed.
                    Label(source.words, systemImage: "clock.arrow.circlepath")
                        .sharedFont(.body, fontSize, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                        .labelStyle(StaleLabelStyle())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("calendar-stale")
        }
    }

    private struct StaleLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                configuration.icon.imageScale(.small)
                configuration.title
            }
        }
    }
}
