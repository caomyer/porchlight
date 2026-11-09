import SwiftUI

/// The default wall screen: clock, the day as one timeline, and what needs doing.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(CompanionStore.self) private var companions
    @Environment(FoodStore.self) private var food
    @Environment(HomeStore.self) private var home
    @Environment(\.openTimelineTarget) private var openTarget

    var body: some View {
        TimelineView(.everyMinute) { context in
            let calendar = model.calendar
            let day = DayKey(context.date, calendar: calendar)
            VStack(alignment: .leading, spacing: 16) {
                header(now: context.date)
                HStack(alignment: .top, spacing: 16) {
                    TodayAgenda(
                        now: context.date,
                        allDay: calendarStore.allDayItems(for: day),
                        items: (calendarStore.timelineItems(for: day)
                            + companions.timelineItems(for: day)
                            + food.timelineItems(for: day)
                            + home.timelineItems(for: day, people: model.people)).sorted { $0.time < $1.time },
                        tomorrow: calendarStore.timelineItems(for: day.adding(days: 1, calendar: calendar))
                            .filter { $0.kind == .event },
                        onOpen: { openTarget?($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Cards keep their natural height; the column scrolls if a
                    // household has many companions or cards.
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            CompanionTodayCards()
                            PitchInTodayCard()
                            FoodTodayCard()
                            CountdownsCard()
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 420)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 18) {
            Clock(date: now)
            VStack(alignment: .leading, spacing: 2) {
                Text(now, format: .dateTime.weekday(.wide))
                    .font(.display(26))
                Text(now, format: .dateTime.month(.wide).day())
                    .font(.body(16, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            WeatherBadge()
            HStack(spacing: -6) {
                ForEach(model.people) { person in
                    Avatar(person: person, size: 34, ringed: true)
                }
            }
            .padding(.leading, 12)
        }
        .foregroundStyle(Theme.ink)
    }
}

/// The left card: all-day chips, the merged timeline with a NOW line, and tomorrow.
struct TodayAgenda: View {
    let now: Date
    let allDay: [AllDayItem]
    let items: [TimelineItem]
    let tomorrow: [TimelineItem]
    /// Called when a row with a target is tapped.
    var onOpen: ((TimelineTarget) -> Void)? = nil

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.display(22))
                Spacer()
                Text(summary)
                    .font(.body(13, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            if !allDay.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(allDay) { item in
                        AllDayChip(item: item, color: model.color(for: item.owner))
                    }
                }
            }
            if items.isEmpty {
                Spacer()
                EmptyState(
                    symbol: "sun.max",
                    title: "A wide-open day",
                    message: "Nothing on the calendar today. Events from the calendars you connect show up here."
                )
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rows) { row in
                            switch row {
                            case .now: NowLine()
                            case let .item(item): timelineRow(item)
                            }
                        }
                    }
                }
            }
            if !tomorrow.isEmpty {
                Spacer(minLength: 0)
                HStack(spacing: 16) {
                    Text("TOMORROW")
                        .font(.body(12, weight: 800))
                        .tracking(1)
                    ForEach(tomorrow.prefix(3)) { item in
                        Text("\(item.title) · \(item.time.formatted(.dateTime.hour().minute()))")
                            .lineLimit(1)
                    }
                }
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private enum Row: Identifiable {
        case now
        case item(TimelineItem)
        var id: String {
            switch self {
            case .now: "now"
            case let .item(item): item.id
            }
        }
    }

    /// Items with the NOW line inserted before the first upcoming one.
    private var rows: [Row] {
        var rows: [Row] = []
        var placedNow = false
        for item in items {
            if !placedNow && item.time > now {
                rows.append(.now)
                placedNow = true
            }
            rows.append(.item(item))
        }
        if !placedNow { rows.append(.now) }
        return rows
    }

    @ViewBuilder
    private func timelineRow(_ item: TimelineItem) -> some View {
        let row = TimelineRow(item: item, isPast: isPast(item), color: model.color(for: item.owner))
        if let target = item.target, let onOpen {
            Button { onOpen(target) } label: { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func isPast(_ item: TimelineItem) -> Bool {
        item.kind == .log || (item.kind == .event && item.time < now && !Calendar.current.isDate(item.time, equalTo: now, toGranularity: .minute))
    }

    private var summary: String {
        let events = items.filter { $0.kind == .event }.count
        return events == 1 ? "1 event" : "\(events) events"
    }
}

private struct TimelineRow: View {
    let item: TimelineItem
    let isPast: Bool
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.timeLabel ?? ClockFormat.time(item.time))
                .font(.body(14, weight: 700))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
                .frame(width: 62, alignment: .trailing)
                .padding(.top, 10)
            HStack(spacing: 12) {
                item.leading
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body(16, weight: 700))
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.body(13, weight: 600))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                item.trailing
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background(background)
            .opacity(isPast && item.kind == .event ? 0.55 : (item.kind == .log ? 0.75 : 1))
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
        switch item.kind {
        case .event:
            shape.fill(color.wash(0.15))
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(topLeadingRadius: Theme.smallRadius, bottomLeadingRadius: Theme.smallRadius)
                        .fill(color)
                        .frame(width: 5)
                }
        case .log:
            shape.fill(Theme.surface).overlay(shape.stroke(Theme.line, lineWidth: 1.5))
        case .expected:
            shape.stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(Theme.muted.opacity(0.6))
        }
    }
}

private struct NowLine: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("NOW")
                .font(.body(12, weight: 800))
                .foregroundStyle(Theme.accent)
                .frame(width: 62, alignment: .trailing)
            Circle().fill(Theme.accent).frame(width: 10, height: 10)
                .padding(.trailing, -12)
            Rectangle().fill(Theme.accent).frame(height: 2)
        }
        .padding(.vertical, 4)
    }
}

private struct AllDayChip: View {
    let item: AllDayItem
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 18, height: 18)
            Text(item.title)
                .font(.body(14, weight: 600))
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(color.wash(0.18), in: Capsule())
    }
}

/// Big hour and minute, with a small AM/PM when the locale uses a 12-hour clock.
struct Clock: View {
    let date: Date
    var size: CGFloat = 68

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(ClockFormat.time(date))
                .font(.display(size))
                .monospacedDigit()
            if let period = ClockFormat.period(date) {
                Text(period)
                    .font(.body(size * 0.26, weight: 700))
                    .opacity(0.6)
            }
        }
    }
}

/// Wall-clock formatting: "9:41" (no leading zero, no AM/PM) plus a separate period.
enum ClockFormat {
    static var usesTwelveHourClock: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = usesTwelveHourClock ? "h:mm" : "H:mm"
        return formatter.string(from: date)
    }

    static func period(_ date: Date, calendar: Calendar = .current) -> String? {
        guard usesTwelveHourClock else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        return calendar.component(.hour, from: date) < 12 ? formatter.amSymbol : formatter.pmSymbol
    }
}

extension AppModel {
    func color(for owner: Owner) -> Color {
        switch owner {
        case .everyone: Theme.everyone
        case let .person(id): people.first { $0.id == id }?.color.color ?? Theme.everyone
        }
    }

    func person(_ id: Int64) -> Person? {
        people.first { $0.id == id }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.accent.opacity(0.12), in: Circle())
            Text(title)
                .font(.display(22))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body(15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
    }
}
