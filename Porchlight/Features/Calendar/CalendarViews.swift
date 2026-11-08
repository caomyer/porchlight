import SwiftUI

/// The Calendar destination: Week / Month / Day.
/// `lanes` come from other features (walks, meals) and are drawn under the week
/// grid and inside month cells.
struct CalendarScreen: View {
    var lanes: [CalendarLane]

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var store

    @State private var mode: CalendarMode = .initial
    /// Any date inside the visible week, month or day.
    @State private var anchor = Date.now
    @State private var selected: CalendarEvent?

    private var calendar: Calendar { store.calendar }

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 16) {
                header(now: context.date)
                content(now: context.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .simultaneousGesture(swipe)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
        }
        .overlay {
            if let selected {
                WallSheet(width: 540, onClose: { withAnimation(.easeOut(duration: 0.2)) { self.selected = nil } }) {
                    EventDetail(event: selected, calendar: calendar)
                }
            }
        }
        .task(id: visibleInterval) {
            if let visibleInterval { store.show(visibleInterval) }
        }
        #if DEBUG
        .onAppear {
            // `-calendarShowEvent <title>` opens that event's sheet, for screenshots.
            if let title = UserDefaults.standard.string(forKey: "calendarShowEvent") {
                selected = store.events.first { $0.title == title }
            }
        }
        #endif
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 14) {
            title
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 6) {
                ForEach(CalendarMode.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { mode = option }
                    } label: {
                        HeaderChip(title: option.title, isSelected: mode == option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == option ? .isSelected : [])
                }
            }
            .padding(.leading, 4)
            HStack(spacing: 6) {
                Button { step(-1) } label: { HeaderChip(symbol: "chevron.left") }
                    .accessibilityLabel("Previous")
                Button { step(1) } label: { HeaderChip(symbol: "chevron.right") }
                    .accessibilityLabel("Next")
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { anchor = now }
                } label: {
                    HeaderChip(title: "Today", isSelected: false)
                }
                .disabled(isShowingToday(now))
                .opacity(isShowingToday(now) ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                legend(withLanes: true)
                legend(withLanes: false)
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .frame(minHeight: 48)
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var title: some View {
        switch mode {
        case .week:
            Text(weekTitle).font(.display(40))
        case .month:
            (Text(EventText.format(anchor, calendar, "MMMM")) + Text(" \(EventText.format(anchor, calendar, "y"))").foregroundColor(Theme.muted))
                .font(.display(40))
        case .day:
            Text(EventText.format(anchor, calendar, "EEEE MMMM d")).font(.display(40))
        }
    }

    private var weekTitle: String {
        let days = calendar.weekDays(containing: anchor)
        guard let first = days.first, let last = days.last else { return "" }
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(EventText.format(first, calendar, "MMMM d")) - \(calendar.component(.day, from: last))"
        }
        return "\(EventText.monthDay(first, calendar)) - \(EventText.monthDay(last, calendar))"
    }

    private func legend(withLanes: Bool) -> some View {
        HStack(spacing: 14) {
            ForEach(model.people) { person in
                LegendItem(color: person.color.color, title: person.name)
            }
            LegendItem(color: Theme.everyone, title: "Both")
            if withLanes {
                ForEach(lanes) { lane in
                    lane.label
                        .frame(maxWidth: 28, maxHeight: 20)
                        .font(.body(13, weight: 600))
                }
            }
        }
        .fixedSize()
    }

    // MARK: Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        let today = DayKey(now, calendar: calendar)
        switch mode {
        case .week:
            TimeGrid(
                days: calendar.weekDays(containing: anchor).map { DayKey($0, calendar: calendar) },
                today: today,
                now: now,
                lanes: lanes,
                isDetailed: false,
                onSelect: select
            )
        case .day:
            TimeGrid(
                days: [DayKey(anchor, calendar: calendar)],
                today: today,
                now: now,
                lanes: lanes,
                isDetailed: true,
                onSelect: select
            )
        case .month:
            MonthGrid(
                anchor: anchor,
                today: today,
                lanes: lanes,
                onSelectDay: { day in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        anchor = day.startDate(in: calendar)
                        mode = .day
                    }
                }
            )
        }
    }

    private func select(_ event: CalendarEvent) {
        withAnimation(.easeOut(duration: 0.2)) { selected = event }
    }

    // MARK: Navigation

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 80, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                step(dx < 0 ? 1 : -1)
            }
    }

    private func step(_ direction: Int) {
        let component: Calendar.Component = switch mode {
        case .week: .weekOfYear
        case .month: .month
        case .day: .day
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            anchor = calendar.date(byAdding: component, value: direction, to: anchor) ?? anchor
        }
    }

    private func isShowingToday(_ now: Date) -> Bool {
        let granularity: Calendar.Component = switch mode {
        case .week: .weekOfYear
        case .month: .month
        case .day: .day
        }
        return calendar.isDate(anchor, equalTo: now, toGranularity: granularity)
    }

    /// What the current mode shows, so the store can load it.
    private var visibleInterval: DateInterval? {
        switch mode {
        case .week: calendar.dateInterval(of: .weekOfYear, for: anchor)
        case .day: calendar.dateInterval(of: .day, for: anchor)
        case .month:
            calendar.monthGridDays(containing: anchor).first.flatMap { first in
                calendar.date(byAdding: .day, value: 42, to: first).map { DateInterval(start: first, end: $0) }
            }
        }
    }
}

enum CalendarMode: String, CaseIterable {
    case week, month, day

    static var initial: CalendarMode {
        #if DEBUG
        // e.g. launch with `-calendarMode month` for screenshots
        if let name = UserDefaults.standard.string(forKey: "calendarMode"), let mode = CalendarMode(rawValue: name) {
            return mode
        }
        #endif
        return .week
    }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .day: "Day"
        }
    }
}

/// The small rounded chip used in the calendar header.
private struct HeaderChip: View {
    var title: String? = nil
    var symbol: String? = nil
    var isSelected = false

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34)
            } else if let title {
                Text(title)
                    .font(.body(13, weight: 700))
                    .padding(.horizontal, 13)
            }
        }
        .frame(height: 34)
        .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
        .background(isSelected ? Theme.ink : Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(isSelected ? Theme.ink : Theme.line))
        .contentShape(Capsule())
    }
}

private struct LegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.body(13, weight: 600))
        }
    }
}

// MARK: - Shared event pieces

/// The square on the left of a Today row: the event's emoji, or a soft dot.
struct EventMark: View {
    let event: CalendarEvent
    let color: Color

    var body: some View {
        Group {
            if let emoji = event.emoji {
                Text(emoji).font(.system(size: 22))
            } else {
                Image(systemName: event.isBusy ? "lock.fill" : "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.wash(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

/// A person's avatar, or a heart for the whole household.
struct OwnerAvatar: View {
    let owner: Owner
    let people: [Person]
    var size: CGFloat = 30

    /// A text-style heart (U+FE0E), so it draws white instead of as a red emoji.
    static let heart = "\u{2665}\u{FE0E}"

    var body: some View {
        switch owner {
        case .everyone:
            Avatar(initial: OwnerAvatar.heart, color: Theme.everyone, size: size)
        case let .person(id):
            if let person = people.first(where: { $0.id == id }) {
                Avatar(person: person, size: size)
            } else {
                Avatar(initial: OwnerAvatar.heart, color: Theme.everyone, size: size)
            }
        }
    }
}

/// "James", "Mia" or "Both".
func ownerName(_ owner: Owner, people: [Person]) -> String {
    switch owner {
    case .everyone: "Both"
    case let .person(id): people.first { $0.id == id }?.name ?? "Both"
    }
}

/// The small sheet shown when an event is tapped.
private struct EventDetail: View {
    let event: CalendarEvent
    let calendar: Calendar

    @Environment(CalendarStore.self) private var store

    var body: some View {
        let color = store.color(for: event.owner)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if let emoji = event.emoji {
                        Text(emoji).font(.system(size: 32))
                    } else {
                        Image(systemName: event.isBusy ? "lock.fill" : "calendar")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }
                .frame(width: 60, height: 60)
                .background(color.wash(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.display(28))
                        .lineLimit(2)
                    Text(when)
                        .font(.body(15, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.trailing, 40)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let location = event.location {
                    row("mappin", location)
                }
                HStack(spacing: 12) {
                    OwnerAvatar(owner: event.owner, people: store.people, size: 26)
                        .frame(width: 22)
                    Text("\(ownerName(event.owner, people: store.people)) · \(event.calendarTitle) calendar")
                        .font(.body(15, weight: 600))
                }
                if event.isBusy {
                    row("eye.slash", "This calendar is shown as Busy only, so details stay private.")
                }
                if let notes = event.notes {
                    Text(notes)
                        .font(.body(15))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(6)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var when: String {
        let date = EventText.format(event.start, calendar, "EEEE MMMM d")
        if event.isAllDayLike {
            if let span = EventText.daySpan(event, calendar: calendar) { return "All day · \(span)" }
            return "\(date) · All day"
        }
        return "\(date) · \(EventText.timeRange(event, calendar: calendar, withPeriod: true))"
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
            Text(text).font(.body(15, weight: 600))
        }
    }
}

// MARK: - Today: Coming up

/// "Coming up" countdown card for Today: birthdays, anniversaries and holidays
/// in the next month. Hidden when there are none.
struct CountdownsCard: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        let countdowns = store.countdowns()
        if !countdowns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Coming up").font(.display(22))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(countdowns) { countdown in
                        CountdownRow(countdown: countdown, color: store.color(for: countdown.event.owner), calendar: store.calendar)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .card()
        }
    }
}

private struct CountdownRow: View {
    let countdown: Countdown
    let color: Color
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                if countdown.daysUntil == 0 {
                    Text("Today")
                        .font(.display(15))
                } else {
                    Text("\(countdown.daysUntil)")
                        .font(.display(20))
                        .monospacedDigit()
                    Text(countdown.daysUntil == 1 ? "DAY" : "DAYS")
                        .font(.body(10, weight: 700))
                        .tracking(0.5)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 52, height: 52)
            .background(color.wash(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text([countdown.event.emoji, countdown.event.title].compactMap { $0 }.joined(separator: " "))
                    .font(.body(15, weight: 700))
                    .lineLimit(1)
                Text(detail)
                    .font(.body(13, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Thu Nov 12 · 6:00 · Lucia's"
    private var detail: String {
        let event = countdown.event
        var parts = [EventText.shortDate(event.start, calendar: calendar)]
        if !event.isAllDayLike { parts.append(EventText.format(event.start, calendar, "jmm")) }
        if let location = event.location { parts.append(location) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Settings and onboarding

/// Calendar section inside Settings.
struct CalendarSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Calendars")
            CalendarSourcesPanel()
                .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

/// Onboarding step: connect calendars.
struct CalendarOnboardingStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeading(
                title: "Bring your calendars together",
                subtitle: "Porchlight reads every calendar this iPad already knows about. Assign each one to a person so it gets their color."
            )
            CalendarSourcesPanel()
            Text("Read-only. Porchlight never changes your calendars.")
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
        }
    }
}
