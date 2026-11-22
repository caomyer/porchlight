import SwiftUI

/// The glass cards shown over Ambient photos: what's next, from every feature.
struct AmbientGlance: View {
    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendarStore

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .bottom, spacing: 14) {
                if let next = nextEvent(after: CompanionClock.at(context.date)) {
                    AmbientGlassCard {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(next.label.uppercased())
                                .font(.body(11.5, weight: 800))
                                .tracking(1)
                                .opacity(0.7)
                            Text(next.item.title)
                                .font(.body(17, weight: 700))
                                .lineLimit(1)
                            Text(next.detail)
                                .font(.body(13.5, weight: 500))
                                .opacity(0.8)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private struct Next {
        var label: String
        var item: TimelineItem
        var detail: String
    }

    /// The next timed event today, or the first one tomorrow.
    private func nextEvent(after now: Date) -> Next? {
        let calendar = model.calendar
        let today = DayKey(now, calendar: calendar)
        if let item = calendarStore.timelineItems(for: today).first(where: { $0.kind == .event && $0.time > now }) {
            return Next(label: "Next up", item: item, detail: detail(item, prefix: nil))
        }
        let tomorrow = today.adding(days: 1, calendar: calendar)
        if let item = calendarStore.timelineItems(for: tomorrow).first(where: { $0.kind == .event }) {
            return Next(label: "Tomorrow", item: item, detail: detail(item, prefix: nil))
        }
        return nil
    }

    private func detail(_ item: TimelineItem, prefix: String?) -> String {
        item.subtitle ?? ClockFormat.time(item.time)
    }
}
