import SwiftUI
import UIKit

/// The phone's Calendar tab (docs/proposals/family-calendar.html, "iPhone";
/// docs/design/calendar-phone-tab.md): the household's calendar, this phone's own events and
/// what the other devices passed on. The month on top (tap it for the month), a chip per
/// person, a week strip with a dot per person each day, and a list that starts at the picked
/// day and runs on through the next two weeks. "+" adds an event to the household's home
/// calendar, and an event's page changes or deletes one this phone may write
/// (docs/design/calendar-add-edit.md). "Free together" swaps the week and the list for the
/// coming evenings and weekend days (docs/design/calendar-free-together.md).
struct PocketCalendarScreen: View {
    @Environment(CalendarStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State private var filter: PocketCalendarLogic.Filter = .everyone
    /// The picked day; nil until one is picked, which is today.
    @State private var picked: DayKey?
    /// Weeks from today's week to the one the strip shows.
    @State private var weekOffset = 0
    @State private var monthOpen = false
    @State private var openEvent: CalendarEvent?
    /// The sheet adding or changing an event.
    @State private var editing: PocketEventEditor.Start?
    /// An edit the event's page asked for, opened once the page has gone.
    @State private var pendingEdit: PocketEventEditor.Start?
    @State private var choosingHome = false
    /// Why "+" can't add here: no home calendar on this phone, or one it can't write.
    @State private var cantAdd: String?
    /// Free together instead of the calendar (docs/design/calendar-free-together.md).
    @State private var showsFree = false
    /// When a free evening was tapped: the new event starts then, once a home calendar is chosen.
    @State private var planStart: Date?
    /// The day it opens on, when not today (hosted checks; a link to a day later).
    private let start: DayKey?

    init(start: DayKey? = nil, free: Bool = false) {
        self.start = start
        _showsFree = State(initialValue: free)
    }

    var body: some View {
        let calendar = store.calendar
        let today = store.today
        let day = picked ?? today
        let week = PocketCalendarLogic.week(offset: weekOffset, from: today, calendar: calendar)
        let events: (DayKey) -> [CalendarEvent] = { PocketCalendarLogic.filter(store.events(on: $0), by: filter) }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(week: week, day: day, calendar: calendar)
                viewPicker
                chips
                if showsFree {
                    PocketFreeTogether(filter: filter) { add(at: $0) }
                } else if monthOpen {
                    PocketCalendarMonth(month: day, picked: day, today: today, filter: filter, events: events) { chosen in
                        pick(chosen, today: today, calendar: calendar)
                        withAnimation(.easeOut(duration: 0.2)) { monthOpen = false }
                    }
                } else {
                    pager(week: week, today: today, calendar: calendar)
                    PocketWeekStrip(days: week, picked: day, today: today, filter: filter, events: events) { pick($0, today: today, calendar: calendar) }
                        .gesture(swipe(today: today, calendar: calendar))
                }
                StaleCalendarLines(sources: store.staleSources, fontSize: 12.5)
                if !showsFree {
                    list(from: day, today: today, calendar: calendar, events: events)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .paperUnderStatusBar()
        .sheet(item: $openEvent, onDismiss: {
            if let pendingEdit { editing = pendingEdit; self.pendingEdit = nil } else { toasts.showPending() }
        }) { event in
            PocketEventPage(event: event) { start in
                pendingEdit = start
                openEvent = nil
            }
        }
        .sheet(item: $editing, onDismiss: toasts.showPending) { start in
            PocketEventEditor(start: start) { words in toasts.showAfterSheet(UndoToast(emoji: "📅", title: words)) }
        }
        .sheet(isPresented: $choosingHome) {
            PocketHomeCalendarSheet { calendar in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    if let found = store.home.calendar ?? (calendar.allowsWrites ? calendar : nil) { editing = .new(found, at: planStart) }
                }
            }
        }
        .alert(cantAdd ?? "", isPresented: Binding(get: { cantAdd != nil }, set: { if !$0 { cantAdd = nil } })) {
            Button("Choose another home calendar") { choosingHome = true }
            Button("OK", role: .cancel) {}
        }
        .task(id: [weekOffset, monthOpen ? 1 : 0]) {
            // Loads what the strip, the month and the list show, beyond the days kept loaded.
            let first = monthOpen ? PocketCalendarLogic.monthGrid(containing: day, calendar: calendar).first?.first : week.first
            if let first {
                let start = first.startDate(in: calendar)
                store.show(DateInterval(start: start, duration: 7 * 86_400 * 7))
            }
        }
        .onAppear {
            if let start, picked == nil { pick(start, today: store.today, calendar: store.calendar) }
        }
        #if DEBUG
        .onAppear(perform: applyDebug)
        #endif
    }

    private func pick(_ day: DayKey, today: DayKey, calendar: Calendar) {
        picked = day
        weekOffset = PocketCalendarLogic.weekOffset(of: day, from: today, calendar: calendar)
    }

    // MARK: Header

    /// "November 2026 ⌄": tapping it opens the month, and folds it again.
    private func header(week: [DayKey], day: DayKey, calendar: Calendar) -> some View {
        let title = monthOpen
            ? EventText.format(day.startDate(in: calendar), calendar, "MMMM y")
            : PocketCalendarLogic.title(for: week, calendar: calendar)
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(showsFree ? "Evenings and weekends" : "Calendar")
                    .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                if showsFree {
                    // No month to open here: the title says what the rows are.
                    Text("Free together")
                        .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { monthOpen.toggle() }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            // One line, made smaller where it must be, rather than "Novemb" over "er".
                            Text(title)
                                .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Image(systemName: monthOpen ? "chevron.up" : "chevron.down")
                                .phoneFont(.body, 14, weight: 800, relativeTo: .title3)
                                .foregroundStyle(Theme.accent)
                        }
                        .foregroundStyle(Theme.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityValue(monthOpen ? "Month open" : "Week")
                    .accessibilityHint(monthOpen ? "Folds the month back to the week" : "Opens the month")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("calendar-month-title")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { add() } label: {
                Image(systemName: "plus")
                    .phoneFont(.body, 17, weight: 800, relativeTo: .title3)
                    // The circle keeps its size; the plus stays inside it.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Theme.surface)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an event")
            .accessibilityIdentifier("calendar-add")
            PocketYouButton()
        }
    }

    /// "+": the sheet, in the home calendar; first choosing one if the household hasn't.
    /// From a free evening, the new event starts `at` then.
    private func add(at start: Date? = nil) {
        planStart = start
        switch store.home {
        case let .found(calendar): editing = .new(calendar, at: start)
        case .notChosen, .ambiguous: choosingHome = true
        case let .notHere(home):
            cantAdd = "Add events from a phone that has \(HomeCalendarLogic.name(home)), the household's home calendar."
        case let .readOnly(calendar):
            cantAdd = "\(calendar.title) can't be added to on this \(DeviceWords.this) any more."
        }
    }

    // MARK: Calendar or Free together

    /// "Calendar | Free together", as the proposal's frame shows.
    /// The picked half: paper on the track by day, a step lighter than the track at night
    /// (the night paper is darker than the track, which read as the half not picked).
    private static let segmentOn = Color(light: 0xFFFCF6, dark: 0x4A413A)

    private var viewPicker: some View {
        HStack(spacing: 4) {
            viewOption("Calendar", isOn: !showsFree, id: "calendar-view-calendar") { showsFree = false }
            viewOption("Free together", isOn: showsFree, id: "calendar-view-free") { showsFree = true }
        }
        .padding(3)
        .background(Theme.surface2, in: Capsule())
    }

    private func viewOption(_ title: String, isOn: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { action() }
        } label: {
            // A two-way switch, grown no further than its words fit whole on one line each.
            Text(title)
                .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isOn ? Self.segmentOn : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    // MARK: People

    /// Everyone, then each person: on as many lines as they need, never off the side.
    private var chips: some View {
        FlowLayout(spacing: 8, lineSpacing: 0) {
            chip("Everyone", owner: nil, value: .everyone)
            ForEach(store.people) { person in
                chip(person.name, owner: person, value: .person(person.id))
            }
        }
    }

    private func chip(_ title: String, owner: Person?, value: PocketCalendarLogic.Filter) -> some View {
        let isOn = filter == value
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { filter = value }
        } label: {
            HStack(spacing: 6) {
                if let owner {
                    Circle().fill(owner.color.color).frame(width: 9, height: 9)
                }
                Text(title).phoneFont(.body, 13, weight: 700, relativeTo: .footnote)
            }
            .foregroundStyle(isOn ? Theme.surface : Theme.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .background(isOn ? Theme.ink : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.line))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("calendar-chip-\(title)")
    }

    // MARK: Week

    /// "‹ This week ›", with "Back to this week" when away from it, as Food's diary pages.
    private func pager(week: [DayKey], today: DayKey, calendar: Calendar) -> some View {
        HStack(spacing: 6) {
            PocketPagerArrow(symbol: "chevron.left", label: "Previous week", id: "calendar-week-back") { weekOffset -= 1 }
            VStack(spacing: 0) {
                Text(weekName(week, calendar: calendar))
                    .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calendar-week-name")
                // Only when away from today, so "This week" sits level with the arrows.
                if weekOffset != 0 || (picked.map { $0 != today } ?? false) {
                    Button("Back to today") {
                        weekOffset = 0
                        picked = nil
                    }
                    .phoneFont(.body, 12.5, weight: 800, relativeTo: .footnote)
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("calendar-today")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            PocketPagerArrow(symbol: "chevron.right", label: "Next week", id: "calendar-week-forward") { weekOffset += 1 }
        }
    }

    private func weekName(_ week: [DayKey], calendar: Calendar) -> String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        default:
            guard let first = week.first, let last = week.last else { return "" }
            return "\(EventText.format(first.startDate(in: calendar), calendar, "MMM d")) - \(EventText.format(last.startDate(in: calendar), calendar, "MMM d"))"
        }
    }

    /// A sideways swipe on the strip pages a week.
    private func swipe(today: DayKey, calendar: Calendar) -> some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            guard abs(value.translation.width) > max(60, abs(value.translation.height) * 1.5) else { return }
            withAnimation(.easeOut(duration: 0.2)) { weekOffset += value.translation.width < 0 ? 1 : -1 }
        }
    }

    // MARK: The list

    @ViewBuilder
    private func list(from day: DayKey, today: DayKey, calendar: Calendar, events: @escaping (DayKey) -> [CalendarEvent]) -> some View {
        let sections = PocketCalendarLogic.sections(from: day, today: today, calendar: calendar, events: events)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 2) {
                    // The day and its count side by side where they fit, else one over the
                    // other: words wrap whole, never split.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            dayTitle(section).fixedSize()
                            Spacer(minLength: 8)
                            dayCount(section).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            dayTitle(section).fixedSize(horizontal: false, vertical: true)
                            dayCount(section)
                        }
                    }
                    .padding(.bottom, 4)
                    if section.events.isEmpty {
                        Text("Nothing planned.")
                            .phoneFont(.body, 13.5, weight: 600)
                            .foregroundStyle(Theme.muted)
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("calendar-empty-day")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(section.events.enumerated()), id: \.element.id) { index, event in
                                if index > 0 { RowDivider() }
                                PocketCalendarRow(event: event, day: section.day) { openEvent = event }
                            }
                        }
                        .phoneCard()
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("calendar-day-\(section.day.rawValue)")
            }
        }
    }

    private func dayTitle(_ section: PocketCalendarLogic.Section) -> some View {
        Text(section.title)
            .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func dayCount(_ section: PocketCalendarLogic.Section) -> some View {
        if !section.events.isEmpty {
            Text(section.count)
                .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
        }
    }

    #if DEBUG
    /// `-debugCalendarDay +2` picks a day from today; `-debugCalendarMonth YES` opens the month.
    private func applyDebug() {
        if let offset = UserDefaults.standard.string(forKey: "debugCalendarDay").flatMap({ Int($0) }) {
            pick(store.today.adding(days: offset, calendar: store.calendar), today: store.today, calendar: store.calendar)
        }
        if UserDefaults.standard.bool(forKey: "debugCalendarMonth") { monthOpen = true }
        if UserDefaults.standard.string(forKey: "debugCalendarView") == "free" { showsFree = true }
    }
    #endif
}

/// A round chevron, as Food's week pager has.
struct PocketPagerArrow: View {
    let symbol: String
    let label: String
    let id: String
    let action: () -> Void
    @PhoneMetric(upTo: 1.4) private var size: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(Theme.surface2, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

// MARK: - The week strip

/// Seven days from the household's first weekday: the weekday's letter, the date, and a dot
/// per person with something on it. Today's date is in the accent color, the picked day sits
/// in a filled pill.
struct PocketWeekStrip: View {
    let days: [DayKey]
    let picked: DayKey
    let today: DayKey
    let filter: PocketCalendarLogic.Filter
    let events: (DayKey) -> [CalendarEvent]
    let onPick: (DayKey) -> Void

    @Environment(CalendarStore.self) private var store
    @PhoneMetric(upTo: 1.5) private var dot: CGFloat = 6

    var body: some View {
        let calendar = store.calendar
        HStack(spacing: 2) {
            ForEach(days, id: \.self) { day in
                let date = day.startDate(in: calendar)
                let isPicked = day == picked
                let isToday = day == today
                let dots = PocketCalendarLogic.dots(events(day), people: store.people, filter: filter)
                Button { onPick(day) } label: {
                    VStack(spacing: 5) {
                        Text(EventText.format(date, calendar, "EEEEE"))
                            .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                            .foregroundStyle(isPicked ? Theme.surface.opacity(0.8) : Theme.muted)
                        Text(EventText.format(date, calendar, "d"))
                            .phoneFont(.display, 18, weight: 600, relativeTo: .headline)
                            .monospacedDigit()
                            .foregroundStyle(isPicked ? Theme.surface : (isToday ? Theme.accent : Theme.ink))
                        HStack(spacing: 3) {
                            ForEach(Array(dots.enumerated()), id: \.offset) { _, owner in
                                Circle()
                                    .fill(isPicked ? Theme.surface : store.color(for: owner))
                                    .frame(width: dot, height: dot)
                            }
                        }
                        // Always as tall as a dot, so the dates line up with or without them.
                        .frame(height: dot)
                    }
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isPicked ? Theme.ink : Color.clear)
                    }
                    .overlay {
                        if isToday && !isPicked {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PocketCalendarLogic.dayTitle(day, today: today, calendar: calendar) + ", " + EventText.format(date, calendar, "MMMM d"))
                .accessibilityValue(dots.isEmpty ? "Nothing planned" : PocketCalendarLogic.count(events(day).count))
                .accessibilityAddTraits(isPicked ? .isSelected : [])
                .accessibilityIdentifier("calendar-strip-\(day.rawValue)")
            }
        }
        .padding(6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Seven dates across the smallest phone: grown further, they crowd their pill.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

// MARK: - The month

/// The picked day's month in whole weeks, a dot per person each day; tapping a day picks it
/// and folds the month away.
struct PocketCalendarMonth: View {
    let month: DayKey
    let picked: DayKey
    let today: DayKey
    let filter: PocketCalendarLogic.Filter
    let events: (DayKey) -> [CalendarEvent]
    let onPick: (DayKey) -> Void

    @Environment(CalendarStore.self) private var store
    @PhoneMetric(upTo: 1.5) private var dot: CGFloat = 5

    var body: some View {
        let calendar = store.calendar
        let rows = PocketCalendarLogic.monthGrid(containing: month, calendar: calendar)
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(rows.first ?? [], id: \.self) { day in
                    Text(EventText.format(day.startDate(in: calendar), calendar, "EEEEE"))
                        .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { day in
                        cell(day, calendar: calendar)
                    }
                }
            }
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Seven dates across the smallest phone: grown further, they crowd their pill.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-month")
    }

    private func cell(_ day: DayKey, calendar: Calendar) -> some View {
        let inMonth = PocketCalendarLogic.isInMonth(day, of: month, calendar: calendar)
        let isPicked = day == picked
        let isToday = day == today
        let dots = PocketCalendarLogic.dots(events(day), people: store.people, filter: filter, limit: 3)
        return Button { onPick(day) } label: {
            VStack(spacing: 4) {
                Text(EventText.format(day.startDate(in: calendar), calendar, "d"))
                    .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isPicked ? Theme.surface : (isToday ? Theme.accent : (inMonth ? Theme.ink : Theme.muted.opacity(0.6))))
                HStack(spacing: 2) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, owner in
                        Circle().fill(isPicked ? Theme.surface : store.color(for: owner)).frame(width: dot, height: dot)
                    }
                }
                .frame(height: dot)
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isPicked ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(EventText.format(day.startDate(in: calendar), calendar, "EEEE MMMM d"))
        .accessibilityValue(dots.isEmpty ? "Nothing planned" : PocketCalendarLogic.count(events(day).count))
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityIdentifier("calendar-month-\(day.rawValue)")
    }
}

// MARK: - A row

/// One event in the list: its time (morning or afternoon always said), a bar in its owner's
/// color as tall as its words, the title, the end and place, and everyone's face.
struct PocketCalendarRow: View {
    let event: CalendarEvent
    let day: DayKey
    let onOpen: () -> Void

    @Environment(CalendarStore.self) private var store

    var body: some View {
        let calendar = store.calendar
        let detail = PocketCalendarLogic.detail(event, calendar: calendar)
        Button(action: onOpen) {
            AdaptiveRow {
                Text(PocketCalendarLogic.time(event, on: day, calendar: calendar))
                    .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 62, alignment: .leading)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text([event.emoji, event.title].compactMap { $0 }.joined(separator: " "))
                            .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                            .foregroundStyle(event.isBusy || event.isQuiet ? Theme.muted : Theme.ink)
                        if let detail {
                            Text(detail)
                                .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 28)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(store.color(for: event.owner).opacity(event.isQuiet || event.isBusy ? 0.5 : 1))
                            .frame(width: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PocketFaces(owners: event.owners)
                }
            }
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the event")
        .accessibilityIdentifier("calendar-event-\(event.title)")
    }
}

// MARK: - An event's page

/// An event inside the app: when, where, notes, who it is for, and where it came from. An
/// event from this phone opens in Calendar too; one passed on from another device can't, so
/// it says whose it is. Read only in this step.
struct PocketEventPage: View {
    let event: CalendarEvent
    /// Asks the screen to open the edit sheet once this page has gone.
    var onEdit: (PocketEventEditor.Start) -> Void = { _ in }

    @Environment(CalendarStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var failure: String?

    /// This phone's own event: one it can open in Calendar.
    private var isOwn: Bool { event.from == nil && !event.isQuiet }

    var body: some View {
        let calendar = store.calendar
        PhoneSheet(label: label(calendar), title: [event.emoji, event.title].compactMap { $0 }.joined(separator: " ")) {
            VStack(alignment: .leading, spacing: 12) {
                row("clock", when(calendar))
                if let location = event.location { row("mappin.and.ellipse", location) }
                if event.owners.allSatisfy({ $0 == .everyone }) {
                    // The household has no face: a plain row, as the filter and the sheet say it.
                    row("person.2", "For everyone")
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        PocketFaces(owners: event.owners)
                            .frame(minWidth: 22, alignment: .leading)
                        Text("For \(event.owners.map { ownerName($0, people: store.people) }.joined(separator: " and "))")
                            .phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                row("calendar", source)
                if let repeats = event.repeats {
                    row("repeat", repeats == .custom ? "Repeats, as set in Calendar" : "Repeats \(repeats.label.lowercased())")
                }
                if let device = event.fromDevice {
                    row("lock", "\(device) can change this.")
                }
                if let failure {
                    Text(failure).phoneFont(.body, 13, weight: 700, relativeTo: .footnote).foregroundStyle(Theme.accent)
                }
                if event.isBusy {
                    row("eye.slash", "Shared as Busy only, so its words stay on the phone it came from.")
                }
                if event.isQuiet, !event.quietEvents.isEmpty {
                    quietList(calendar)
                }
                if let notes = event.notes {
                    Text(notes)
                        .phoneFont(.body, 14, weight: 500)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        } footer: {
            VStack(spacing: 8) {
                if store.canChange(event), let draft = store.draft(for: event) {
                    Button("Edit") { onEdit(.edit(event, draft)) }
                        .buttonStyle(PhoneButtonStyle())
                        .accessibilityIdentifier("event-edit")
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(PhoneButtonStyle(kind: .ghost))
                        .accessibilityIdentifier("event-delete")
                }
                if isOwn {
                    Button("Open in Calendar") {
                        if let url = URL(string: "calshow:\(event.start.timeIntervalSinceReferenceDate)") { openURL(url) }
                    }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
                    .accessibilityIdentifier("open-in-calendar")
                }
            }
        }
        .confirmationDialog(event.repeats == nil ? "Delete \(event.title)?" : "\(event.title) repeats", isPresented: $confirmingDelete, titleVisibility: .visible) {
            if event.repeats == nil {
                Button("Delete", role: .destructive) { delete(.thisEvent) }
            } else {
                Button("Delete this event only", role: .destructive) { delete(.thisEvent) }
                Button("Delete this and future events", role: .destructive) { delete(.futureEvents) }
            }
            Button("Keep it", role: .cancel) {}
        }
        .accessibilityIdentifier("event-page")
    }

    private func delete(_ span: EventSpan) {
        do {
            guard let undo = try store.delete(event, span: span) else { return }
            dismiss()
            toasts.showAfterSheet(UndoToast(
                emoji: "🗑️", title: "\(undo.draft.title) deleted", detail: nil,
                action: UndoToast.Action(title: "Undo") { [store] in _ = try? store.save(undo.draft, for: undo.people) }
            ))
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func label(_ calendar: Calendar) -> String {
        PocketCalendarLogic.dayTitle(DayKey(event.start, calendar: calendar), today: store.today, calendar: calendar)
    }

    private func when(_ calendar: Calendar) -> String {
        let date = EventText.format(event.start, calendar, "EEEE, MMMM d")
        if event.isQuiet { return "\(date) · \(QuietWords.detail(event, calendar: calendar))" }
        if event.isAllDayLike {
            if let span = EventText.daySpan(event, calendar: calendar) { return "All day · \(span)" }
            return "\(date) · All day"
        }
        return "\(date) · \(ClockFormat.phoneTime(event.start, calendar: calendar)) to \(ClockFormat.phoneTime(event.end, calendar: calendar))"
    }

    /// "From Sam's Google · Mia Soccer", or this phone's own calendar.
    private var source: String {
        if let from = event.from { return from }
        let title = store.calendarName(event)
        let name = title.isEmpty ? "calendar" : "\(title) calendar"
        return "Your \(name), on this \(DeviceWords.this)"
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .phoneFont(.body, 13, weight: 700, relativeTo: .subheadline)
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 22, alignment: .leading)
                .accessibilityHidden(true)
            Text(text)
                .phoneFont(.body, 14.5, weight: 600, relativeTo: .subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func quietList(_ calendar: Calendar) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(event.quietEvents.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                AdaptiveRow {
                    Text(item.isAllDayLike ? "All day" : ClockFormat.phoneTime(item.start, calendar: calendar))
                        .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .frame(minWidth: 62, alignment: .leading)
                    Text(item.title)
                        .phoneFont(.body, 14, weight: 600, relativeTo: .subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quiet-events")
    }
}
