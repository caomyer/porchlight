import SwiftUI

/// The month overview: whole weeks, bold chips for all-day events, dotted
/// lines for timed ones, "+N more", celebration stickers, and feature lane
/// marks on past days.
struct MonthGrid: View {
    let anchor: Date
    let today: DayKey
    let lanes: [CalendarLane]
    let onSelectDay: (DayKey) -> Void

    @Environment(CalendarStore.self) private var store

    private static let headerHeight: CGFloat = 34
    private static let dayNumberHeight: CGFloat = 24
    private static let entryHeight: CGFloat = 21
    private static let laneHeight: CGFloat = 24

    private var calendar: Calendar { store.calendar }

    var body: some View {
        let dates = calendar.monthGridDays(containing: anchor)
        let weeks = stride(from: 0, to: dates.count, by: 7).map { Array(dates[$0..<min($0 + 7, dates.count)]) }
        let month = calendar.component(.month, from: anchor)
        GeometryReader { proxy in
            let rowHeight = (proxy.size.height - Self.headerHeight) / CGFloat(max(weeks.count, 1))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(weeks.first ?? [], id: \.self) { date in
                        Text(EventText.format(date, calendar, "EEE").uppercased())
                            .font(.body(12, weight: 700))
                            .tracking(1)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: Self.headerHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.element) { index, date in
                            let day = DayKey(date, calendar: calendar)
                            cell(day: day, date: date, isInMonth: calendar.component(.month, from: date) == month)
                                .overlay(alignment: .trailing) {
                                    if index < 6 { Rectangle().fill(Theme.line).frame(width: 1) }
                                }
                        }
                    }
                    .frame(height: rowHeight)
                    .overlay(alignment: .bottom) {
                        if week != weeks.last { Rectangle().fill(Theme.line).frame(height: 1) }
                    }
                }
            }
        }
        .background(SurfaceShape(cornerRadius: Theme.radius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func cell(day: DayKey, date: Date, isInMonth: Bool) -> some View {
        let events = isInMonth ? sorted(store.events(on: day)) : []
        let showsLanes = isInMonth && day <= today && !lanes.isEmpty
        let sticker = events.lazy.compactMap(\.sticker).first

        return VStack(alignment: .leading, spacing: 3) {
            dayNumber(day: day, date: date, isInMonth: isInMonth)
            // Events take the room the lane marks leave, however many lines those wrap to.
            GeometryReader { proxy in
                entries(events, room: proxy.size.height)
            }
            if showsLanes {
                FlowLayout(spacing: 7, lineSpacing: 4) {
                    ForEach(lanes) { lane in
                        lane.cell(day, .month)
                            .frame(minHeight: Self.laneHeight - 8)
                    }
                }
                .padding(.bottom, 1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            if let sticker {
                Text(sticker)
                    .font(.system(size: 24))
                    .rotationEffect(.degrees(-8))
                    .padding(.trailing, 7)
                    .padding(.bottom, 5)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if isInMonth { onSelectDay(day) } }
    }

    /// As many event lines as fit, then "+N more".
    private func entries(_ events: [CalendarEvent], room: CGFloat) -> some View {
        let capacity = max(0, Int((room + 3) / Self.entryHeight))
        let visible = events.count > capacity ? Array(events.prefix(max(capacity - 1, 0))) : events
        let hidden = events.count - visible.count
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(visible) { event in
                MonthEntry(event: event, color: store.color(for: event.owner))
            }
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.body(11, weight: 700))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dayNumber(day: DayKey, date: Date, isInMonth: Bool) -> some View {
        let number = calendar.component(.day, from: date)
        let label = !isInMonth && number == 1 ? EventText.monthDay(date, calendar) : "\(number)"
        let isToday = day == today
        return Text(label)
            .font(.body(15, weight: 700))
            .monospacedDigit()
            .foregroundStyle(isToday ? Theme.accentInk : (isInMonth ? Theme.ink : Theme.muted.opacity(0.5)))
            .frame(minWidth: isToday ? 28 : nil, minHeight: 28)
            .background(isToday ? Theme.accent : .clear, in: Circle())
            .padding(.leading, isToday ? -4 : 0)
            .frame(height: Self.dayNumberHeight)
    }

    /// All-day chips first (longest first), then timed events by start.
    private func sorted(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { a, b in
            if a.isAllDayLike != b.isAllDayLike { return a.isAllDayLike }
            if a.isAllDayLike { return (a.start, b.end, a.id) < (b.start, a.end, b.id) }
            return (a.start, a.id) < (b.start, b.id)
        }
    }
}

/// One line in a month cell.
private struct MonthEntry: View {
    let event: CalendarEvent
    let color: Color

    var body: some View {
        let title = [event.emoji, event.title].compactMap { $0 }.joined(separator: " ")
        if event.isAllDayLike {
            Text(title)
                .font(.body(11.5, weight: 700))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .background(color.wash(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.body(11.5, weight: 700))
                    .foregroundStyle(event.isBusy ? Theme.muted : Theme.ink)
                    .lineLimit(1)
            }
            .padding(.leading, 2)
            .frame(minHeight: 18)
        }
    }
}
