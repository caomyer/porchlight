import SwiftUI

/// The week (7 columns) and day (1 column) views: day headers, the all-day
/// lane, the time grid with a now line, and feature lanes underneath.
struct TimeGrid: View {
    let days: [DayKey]
    let today: DayKey
    let now: Date
    let lanes: [CalendarLane]
    /// Day view: wider blocks with full details.
    let isDetailed: Bool
    let onSelect: (CalendarEvent) -> Void

    @Environment(CalendarStore.self) private var store

    static let gutter: CGFloat = 52
    private static let topInset: CGFloat = 10
    private static let allDayRowHeight: CGFloat = 26

    private var calendar: Calendar { store.calendar }

    var body: some View {
        let events = days.map { store.events(on: $0) }
        let all = Array(Dictionary(events.joined().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
        let hours = HourRange.fitting(all, days: days, calendar: calendar)
        VStack(spacing: 0) {
            dayHeaders
            allDayLane(all)
            GeometryReader { proxy in
                grid(eventsByDay: events, hours: hours, size: proxy.size)
            }
            .frame(minHeight: 160)
            ForEach(lanes) { lane in
                laneRow(lane)
            }
        }
        .background(SurfaceShape(cornerRadius: Theme.radius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: Headers

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let date = day.startDate(in: calendar)
                let isToday = day == today
                VStack(spacing: 2) {
                    Text(EventText.format(date, calendar, isDetailed ? "EEEE" : "EEE").uppercased())
                        .font(.body(12, weight: 700))
                        .tracking(1)
                        .foregroundStyle(Theme.muted)
                    Text("\(calendar.component(.day, from: date))")
                        .font(.display(24))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? Theme.accentInk : Theme.ink)
                        .frame(width: 38, height: 38)
                        .background(isToday ? Theme.accent : .clear, in: Circle())
                }
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) { VLine() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) { HLine() }
    }

    // MARK: All-day lane

    private func allDayLane(_ events: [CalendarEvent]) -> some View {
        let bars = AllDayLayout.bars(for: events, days: days, calendar: calendar)
        let byId = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = (bars.map(\.row).max() ?? -1) + 1
        let height = max(24, CGFloat(min(rows, 3)) * Self.allDayRowHeight - 2)
        return HStack(spacing: 0) {
            Text("ALL DAY")
                .font(.body(10.5, weight: 700))
                .tracking(0.4)
                .foregroundStyle(Theme.muted)
                .frame(width: Self.gutter)
            GeometryReader { proxy in
                let width = proxy.size.width / CGFloat(max(days.count, 1))
                ZStack(alignment: .topLeading) {
                    ForEach(days.indices, id: \.self) { index in
                        VLine().offset(x: CGFloat(index) * width)
                    }
                    ForEach(bars.filter { $0.row < 3 }) { bar in
                        if let event = byId[bar.id] {
                            AllDayBar(event: event, color: store.color(for: event.owner))
                                .frame(width: CGFloat(bar.endIndex - bar.startIndex + 1) * width - 8, height: Self.allDayRowHeight - 4)
                                .offset(x: CGFloat(bar.startIndex) * width + 4, y: CGFloat(bar.row) * Self.allDayRowHeight)
                                .onTapGesture { onSelect(event) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: height)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { HLine() }
    }

    // MARK: Time grid

    private func grid(eventsByDay: [[CalendarEvent]], hours: ClosedRange<Int>, size: CGSize) -> some View {
        let hourCount = CGFloat(hours.upperBound - hours.lowerBound)
        let available = size.height - Self.topInset * 2
        let hourHeight = max(isDetailed ? 44 : 28, available / max(hourCount, 1))
        let contentHeight = hourHeight * hourCount + Self.topInset * 2
        let columnWidth = (size.width - Self.gutter) / CGFloat(max(days.count, 1))
        let content = ZStack(alignment: .topLeading) {
            // Hour lines and labels.
            ForEach(hours.lowerBound...hours.upperBound, id: \.self) { hour in
                let y = Self.topInset + CGFloat(hour - hours.lowerBound) * hourHeight
                Rectangle()
                    .fill(Theme.line.opacity(0.6))
                    .frame(width: size.width - Self.gutter, height: 1)
                    .offset(x: Self.gutter, y: y)
                if hour < hours.upperBound {
                    Text(EventText.hourLabel(hour))
                        .font(.body(11, weight: 700))
                        .foregroundStyle(Theme.muted)
                        .frame(width: Self.gutter - 8, alignment: .trailing)
                        .offset(y: y - 7)
                }
            }
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                dayColumn(day: day, events: eventsByDay[index], hours: hours, hourHeight: hourHeight, width: columnWidth, height: contentHeight)
                    .offset(x: Self.gutter + CGFloat(index) * columnWidth)
            }
        }
        .frame(width: size.width, height: contentHeight, alignment: .topLeading)

        return Group {
            if contentHeight > size.height + 1 {
                ScrollView(.vertical, showsIndicators: false) { content }
                    .defaultScrollAnchor(.center)
            } else {
                content
            }
        }
    }

    private func dayColumn(day: DayKey, events: [CalendarEvent], hours: ClosedRange<Int>, hourHeight: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let dayStart = day.startDate(in: calendar)
        let timed = events.filter { !$0.isAllDayLike }
        let gridStart = dayStart.addingTimeInterval(Double(hours.lowerBound) * 3600)
        func y(_ date: Date) -> CGFloat {
            Self.topInset + CGFloat(date.timeIntervalSince(gridStart) / 3600) * hourHeight
        }
        // Very short events still need room for a title.
        let minimumDuration = Double(18 / hourHeight) * 3600
        let slots = OverlapLayout.slots(timed.map {
            OverlapLayout.Item(id: $0.id, start: max($0.start, dayStart), end: max($0.end, $0.start.addingTimeInterval(minimumDuration)))
        })
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let isToday = day == today

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(isToday ? Theme.accent.opacity(0.05) : .clear)
                .frame(width: width, height: height)
            VLine()
            ForEach(timed) { event in
                let slot = slots[event.id] ?? .init(column: 0, columns: 1)
                let top = y(max(event.start, dayStart)) + 1
                let bottom = y(min(event.end, dayEnd))
                let inner = width - 8
                let blockWidth = inner / CGFloat(slot.columns) - (slot.columns > 1 ? 2 : 0)
                EventBlock(
                    event: event,
                    color: store.color(for: event.owner),
                    height: max(bottom - top - 2, 18),
                    isDetailed: isDetailed,
                    calendar: calendar,
                    people: store.people
                )
                .frame(width: blockWidth, height: max(bottom - top - 2, 18))
                .offset(x: 4 + CGFloat(slot.column) * (inner / CGFloat(slot.columns)), y: top)
                .onTapGesture { onSelect(event) }
            }
            if isToday, now >= gridStart, now <= gridStart.addingTimeInterval(Double(hours.count - 1) * 3600) {
                NowLine(width: width)
                    .offset(y: y(now) - 5)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    // MARK: Lanes

    private func laneRow(_ lane: CalendarLane) -> some View {
        HStack(spacing: 0) {
            lane.label
                .frame(width: Self.gutter)
            ForEach(days, id: \.self) { day in
                lane.cell(day, .week)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) { VLine() }
            }
        }
        .frame(minHeight: 46)
        .fixedSize(horizontal: false, vertical: true)
        .background(laneTint)
        .overlay(alignment: .top) { HLine() }
    }
}

/// Warm paper tint behind feature lanes.
private let laneTint = Color(hex: 0xE1A75A).wash(0.09)

private struct HLine: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

private struct VLine: View {
    var body: some View { Rectangle().fill(Theme.line).frame(width: 1) }
}

private struct NowLine: View {
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.accent).frame(width: width, height: 2)
            Circle().fill(Theme.accent).frame(width: 10, height: 10).offset(x: -5)
        }
        .frame(height: 10)
        .allowsHitTesting(false)
    }
}

/// A timed event in the grid: tinted block with a colored left edge.
private struct EventBlock: View {
    let event: CalendarEvent
    let color: Color
    let height: CGFloat
    let isDetailed: Bool
    let calendar: Calendar
    let people: [Person]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body(isDetailed ? 16 : 12.5, weight: 700))
                    .foregroundStyle(event.isBusy ? Theme.muted : Theme.ink)
                    .lineLimit(titleLines)
                if showsTime {
                    Text(timeText)
                        .font(.body(isDetailed ? 13 : 11, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if isDetailed, height > 70, let notes = event.notes {
                    Text(notes)
                        .font(.body(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if isDetailed, height >= 36 {
                OwnerAvatar(owner: event.owner, people: people, size: 26)
            }
        }
        .padding(.vertical, isDetailed && height >= 40 ? 7 : 4)
        .padding(.leading, isDetailed ? 14 : 9)
        .padding(.trailing, isDetailed ? 10 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.wash(event.isBusy ? 0.08 : 0.15), in: shape)
        .overlay(alignment: .leading) {
            Rectangle().fill(color.opacity(event.isBusy ? 0.5 : 1)).frame(width: 4)
        }
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var title: String {
        [event.emoji, event.title].compactMap { $0 }.joined(separator: " ")
    }

    private var titleLines: Int {
        isDetailed ? 1 : max(1, Int((height - 8 - (showsTime ? 14 : 0)) / 16))
    }

    private var showsTime: Bool {
        isDetailed ? height >= 40 : event.end.timeIntervalSince(event.start) >= 1.25 * 3600 && height >= 36
    }

    private var timeText: String {
        if isDetailed {
            var text = EventText.timeRange(event, calendar: calendar)
            if let location = event.location { text += " · \(location)" }
            return text
        }
        return "\(EventText.shortTime(event.start, calendar: calendar)) - \(EventText.shortTime(event.end, calendar: calendar))"
    }
}

/// A bar in the all-day lane.
struct AllDayBar: View {
    let event: CalendarEvent
    let color: Color

    var body: some View {
        Text([event.emoji, event.title].compactMap { $0 }.joined(separator: " "))
            .font(.body(12.5, weight: 700))
            .foregroundStyle(event.isBusy ? Theme.muted : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(color.wash(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
    }
}
