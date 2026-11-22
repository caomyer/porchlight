import SwiftUI

// The one time control in the app. At rest a time is a pill in Today's serif
// numerals. Tapping it opens a small card from the pill, already showing that
// time: a few suggestions for the usual cases, the hour and the minutes in
// their own boxes, and a number pad that types into the selected box. The
// iPad's keyboard never comes up (iPad has no small number keyboard, and the
// full one covers half the wall), though a hardware keyboard types straight
// in. A start and end is two pills.

/// Which end of a stretch of hours is being set.
enum HoursEnd: Hashable, Sendable {
    case start, end
}

/// A one-tap choice in the card: "1 hr ago", "Usual dinner", "9:00 PM".
struct TimeSuggestion: Identifiable {
    var title: String
    /// The time it means, when the title doesn't say it.
    var detail: String?
    var isSelected = false
    /// Sets the time; returns why it can't, if it can't.
    var apply: () -> String?

    var id: String { title }
}

// MARK: - The control

/// A time pill and the card it opens. The owner says which times it can take.
struct TimeFieldControl: View {
    let minute: Int
    var nextDay = false
    var clock: ClockStyle = .current
    var suggestions: [TimeSuggestion] = []
    let accessibilityLabel: String
    let identifier: String
    /// Sets the time (minutes from midnight); returns why it can't, if it can't.
    let apply: (Int) -> String?

    @State private var isOpen = false
    @State private var typing = TimeTyping()
    /// A time typed that can't be used, shown with the reason until it's fixed.
    @State private var refused: Int?
    @State private var note: String?

    var body: some View {
        TimeFieldPill(
            minute: minute, nextDay: nextDay, isOpen: isOpen, clock: clock,
            accessibilityLabel: accessibilityLabel, identifier: identifier
        ) {
            typing = TimeTyping()
            refused = nil
            note = nil
            isOpen = true
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            TimeKeypadCard(
                minute: refused ?? minute, nextDay: nextDay && refused == nil, clock: clock,
                suggestions: suggestions, note: note, typing: $typing,
                onChange: change,
                onSuggestion: { suggestion in
                    if let problem = suggestion.apply() { note = problem } else { isOpen = false }
                },
                onClose: { isOpen = false }
            )
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Theme.surface)
        }
        .onChange(of: isOpen) { _, open in
            // Closing drops a time that couldn't be used; good ones are already set.
            if !open {
                refused = nil
                note = nil
            }
        }
    }

    private func change(_ new: Int) {
        if let problem = apply(new) {
            refused = new
            note = problem
        } else {
            refused = nil
            note = nil
        }
    }
}

/// A time at rest, or while its card is open.
struct TimeFieldPill: View {
    let minute: Int
    var nextDay = false
    var isOpen = false
    var clock: ClockStyle = .current
    let accessibilityLabel: String
    let identifier: String
    let action: () -> Void

    /// The phone's compact layout follows Dynamic Type; the wall's type is fixed, as
    /// everywhere on the wall (`PhoneType.swift`).
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .title3) private var timeSize: CGFloat = 19
    @ScaledMetric(relativeTo: .footnote) private var periodSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var nextDaySize: CGFloat = 10
    @ScaledMetric(relativeTo: .title3) private var inset: CGFloat = 14

    private var scales: Bool { sizeClass == .compact }

    var body: some View {
        let parts = clock.parts(minute)
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(parts.time)
                    .font(.display(scales ? timeSize : 19))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if let period = parts.period {
                    Text(period)
                        .font(.body(scales ? periodSize : 12, weight: 700))
                        .foregroundStyle(Theme.muted)
                }
                if nextDay {
                    Text("+1")
                        .font(.body(scales ? nextDaySize : 10, weight: 800))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, scales ? inset : 14)
            .padding(.top, 6)
            .padding(.bottom, 7)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOpen ? Theme.accent : Theme.line, lineWidth: isOpen ? 2 : 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(clock.text(minute) + (nextDay ? ", next day" : ""))
        .accessibilityHint("Pick or type a time")
        .accessibilityIdentifier(identifier)
    }
}

/// The card: suggestions, the hour and minutes in their own boxes (with AM | PM
/// on a 12-hour clock), what typing does next or why a time can't be used, the
/// number pad, and Done.
struct TimeKeypadCard: View {
    let minute: Int
    var nextDay = false
    var clock: ClockStyle = .current
    var suggestions: [TimeSuggestion] = []
    let note: String?
    @Binding var typing: TimeTyping
    let onChange: (Int) -> Void
    let onSuggestion: (TimeSuggestion) -> Void
    let onClose: () -> Void

    @FocusState private var hasKeys: Bool

    private static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
    private static let warn = Color(hex: 0xB4532A)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions) { suggestion in
                        chip(suggestion)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                readout
                if let note {
                    Text(note)
                        .font(.body(13, weight: 600))
                        .foregroundStyle(Self.warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("time-note")
                } else {
                    Text(typing.hint(clock))
                        .font(.body(13, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("time-hint")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Array(Self.keys.enumerated()), id: \.offset) { _, key in
                    if key.isEmpty {
                        Color.clear.frame(minHeight: 46).accessibilityHidden(true)
                    } else {
                        Button { press(key) } label: {
                            Text(key)
                                .font(key == "⌫" ? .body(17, weight: 700) : .display(21))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "⌫" ? "Delete" : key)
                        .accessibilityIdentifier("key-\(key == "⌫" ? "delete" : key)")
                    }
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Text("Done")
                        .font(.body(14, weight: 800))
                        .foregroundStyle(Theme.surface)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.ink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(note != nil)
                .opacity(note == nil ? 1 : 0.35)
                .accessibilityIdentifier("time-done")
            }
        }
        .padding(14)
        .frame(width: 272)
        // A hardware keyboard types straight in.
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeys)
        .onKeyPress(phases: .down) { press in
            switch press.key {
            case .return:
                if note == nil { onClose() }
                return .handled
            case .escape: onClose(); return .handled
            case .delete, .deleteForward: typing.delete(); return .handled
            case .leftArrow: typing.select(.hour); return .handled
            case .rightArrow, .tab: typing.select(.minute); return .handled
            case .upArrow: onChange(typing.nudging(minute, by: 1)); return .handled
            case .downArrow: onChange(typing.nudging(minute, by: -1)); return .handled
            default:
                let typed = press.characters.lowercased()
                if typed.count == 1, Int(typed) != nil {
                    self.press(typed)
                    return .handled
                }
                if !clock.uses24Hours, typed == "a" || typed == "p" {
                    onChange(TimeTyping.flipping(minute, toPM: typed == "p"))
                    return .handled
                }
                return .ignored
            }
        }
        .onAppear { hasKeys = true }
    }

    private var readout: some View {
        let fields = clock.fields(minute)
        let period = clock.parts(minute).period
        return HStack(alignment: .center, spacing: 2) {
            box(.hour, typing.part == .hour && typing.open == 0 && !clock.uses24Hours ? "0" : fields.hour)
            Text(":")
                .font(.display(28))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            box(.minute, fields.minute)
            if nextDay {
                Text("+1 day")
                    .font(.body(12, weight: 800))
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 8)
            if let period {
                HStack(spacing: 0) {
                    periodButton("AM", isOn: period == "AM") { onChange(TimeTyping.flipping(minute, toPM: false)) }
                    periodButton("PM", isOn: period == "PM") { onChange(TimeTyping.flipping(minute, toPM: true)) }
                }
                .padding(2)
                .background(Theme.surface2, in: Capsule())
            }
        }
    }

    private func box(_ part: TimeTyping.Part, _ value: String) -> some View {
        let isSelected = typing.part == part
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button { typing.select(part) } label: {
            Text(value)
                .font(.display(32))
                .monospacedDigit()
                .foregroundStyle(isSelected && typing.open != nil ? Theme.accent : Theme.ink)
                .frame(minWidth: 52)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isSelected ? Theme.accent.opacity(0.14) : .clear, in: shape)
                .overlay(shape.strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(part == .hour ? "Hour" : "Minutes")
        .accessibilityValue(value)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(part == .hour ? "time-hour" : "time-minute")
    }

    private func press(_ key: String) {
        if key == "⌫" {
            typing.delete()
        } else if let digit = Int(key) {
            onChange(typing.type(digit, into: minute, clock: clock))
        }
    }

    private func chip(_ suggestion: TimeSuggestion) -> some View {
        Button { onSuggestion(suggestion) } label: {
            HStack(spacing: 4) {
                Text(suggestion.title).font(.body(13.5, weight: 700))
                if let detail = suggestion.detail {
                    Text(detail)
                        .font(.body(13.5, weight: 700))
                        .foregroundStyle(suggestion.isSelected ? Theme.surface.opacity(0.7) : Theme.muted)
                }
            }
            .foregroundStyle(suggestion.isSelected ? Theme.surface : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(suggestion.isSelected ? Theme.ink : Theme.surface2, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(suggestion.isSelected ? .isSelected : [])
    }

    private func periodButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body(13, weight: 800))
                .foregroundStyle(isOn ? Theme.surface : Theme.muted)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(isOn ? Theme.ink : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - A time something happened

/// The times a log can take on its day, as minutes from that day's midnight: only times
/// that have happened that day. Shared by the time pill and the phone's inline pad.
struct LogTimeDay {
    /// Within one day, e.g. the meal's day up to now.
    let range: ClosedRange<Date>
    var calendar: Calendar = .current
    var clock: ClockStyle = .current

    private var dayStart: Date { calendar.startOfDay(for: range.lowerBound) }

    func minute(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.day, .hour, .minute], from: dayStart, to: date)
        return (parts.day ?? 0) * TimeEntry.day + (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    func date(_ minute: Int) -> Date {
        calendar.date(byAdding: .minute, value: minute, to: dayStart) ?? dayStart
    }

    func clamp(_ date: Date) -> Date { min(max(date, range.lowerBound), range.upperBound) }

    /// When `time` starts on this day, kept inside it.
    func resolved(_ time: LogTime, now: Date, lasting: Int) -> Date {
        clamp(time.start(now: now, lasting: lasting))
    }

    private var allowed: ClosedRange<Int> { minute(range.lowerBound)...max(minute(range.lowerBound), minute(range.upperBound)) }

    /// Why `minute` can't be used, if it can't.
    func problem(_ minute: Int) -> String? {
        guard !allowed.contains(minute) else { return nil }
        return minute > allowed.upperBound
            ? "\(clock.text(minute)) is later than now, so it can't be logged yet."
            : "\(clock.text(minute)) is too early for this day."
    }

    /// The card's one-tap choices that fall on this day; choosing one calls `choose`.
    func suggestions(
        _ suggestions: [(title: String, time: LogTime)], selected: LogTime, now: Date, lasting: Int, choose: @escaping (LogTime) -> Void
    ) -> [TimeSuggestion] {
        suggestions.compactMap { suggestion in
            let start = suggestion.time.start(now: now, lasting: lasting)
            // "Just now" is offered whenever now is in range, even if a walk that just
            // ended started before midnight. A minute's slack: "now" was read a moment
            // after the range was.
            let probe = suggestion.time == .justNow ? now : start
            guard probe >= range.lowerBound, probe <= range.upperBound.addingTimeInterval(60) else { return nil }
            let showsTime = !suggestion.title.contains(":")
            return TimeSuggestion(
                title: suggestion.title,
                detail: showsTime && suggestion.time != .justNow ? clock.text(minute(clamp(start))) : nil,
                isSelected: selected == suggestion.time
            ) {
                choose(suggestion.time)
                return nil
            }
        }
    }
}

/// When something happened on a day: the label, then the time on the right.
/// Only times that have happened that day can be set.
struct LogTimeField<Leading: View>: View {
    @Binding var time: LogTime
    /// Within one day, e.g. the meal's day up to now.
    let range: ClosedRange<Date>
    var now: Date = CompanionClock.now()
    /// How long it lasted, so "just now" means it just ended.
    var lasting = 0
    var suggestions: [(title: String, time: LogTime)] = []
    let accessibilityLabel: String
    let identifier: String
    var calendar: Calendar = .current
    var clock: ClockStyle = .current
    @ViewBuilder var leading: () -> Leading

    private var day: LogTimeDay { LogTimeDay(range: range, calendar: calendar, clock: clock) }

    var body: some View {
        // Beside its label where both fit; at large text sizes, under it.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                leading()
                    .fixedSize()
                Spacer(minLength: 8)
                control
            }
            VStack(alignment: .leading, spacing: 8) {
                leading()
                control
            }
        }
    }

    private var control: some View {
        TimeFieldControl(
            minute: day.minute(day.resolved(time, now: now, lasting: lasting)), clock: clock,
            suggestions: day.suggestions(suggestions, selected: time, now: now, lasting: lasting) { time = $0 },
            accessibilityLabel: accessibilityLabel, identifier: identifier,
            apply: apply
        )
    }

    private func apply(_ minute: Int) -> String? {
        if let problem = day.problem(minute) { return problem }
        time = .at(day.date(minute))
        return nil
    }
}

// MARK: - A stretch of hours

/// A start and end time of day, e.g. a routine's window or the night. Minutes
/// from midnight. The night may end the next morning; a window can't.
struct HoursField<Leading: View>: View {
    @Binding var start: Int
    @Binding var end: Int
    /// The end may be the next day ("+1"), as for the night.
    var allowsNextDay = false
    var startSuggestions: [Int] = []
    var endSuggestions: [Int] = []
    let accessibilityLabel: String
    let identifier: String
    var clock: ClockStyle = .current
    @ViewBuilder var leading: () -> Leading

    private var nextDay: Bool { allowsNextDay && end <= start }

    var body: some View {
        HStack(spacing: 8) {
            leading()
            field(.start)
            Text("to")
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
            field(.end)
        }
    }

    private func field(_ which: HoursEnd) -> some View {
        TimeFieldControl(
            minute: value(which) % TimeEntry.day,
            nextDay: which == .end && nextDay,
            clock: clock,
            suggestions: (which == .start ? startSuggestions : endSuggestions).map { minute in
                TimeSuggestion(title: clock.text(minute), isSelected: value(which) == minute) {
                    if let problem = problem(which, minute) { return problem }
                    set(which, minute)
                    return nil
                }
            },
            accessibilityLabel: "\(accessibilityLabel) \(which == .start ? "from" : "to")",
            identifier: "\(identifier)-\(which == .start ? "start" : "end")",
            apply: { minute in apply(minute, to: which) }
        )
    }

    private func value(_ which: HoursEnd) -> Int { which == .start ? start : end }

    private func set(_ which: HoursEnd, _ minute: Int) {
        if which == .start { start = minute } else { end = minute }
    }

    /// Why `minute` can't be this end, if it can't.
    private func problem(_ which: HoursEnd, _ minute: Int) -> String? {
        guard !allowsNextDay else { return minute == (which == .start ? end : start) ? "Start and end can't be the same time." : nil }
        switch which {
        case .start: return minute < end ? nil : "\(clock.text(minute)) is after it ends."
        case .end: return minute > start ? nil : "\(clock.text(minute)) is before it starts."
        }
    }

    private func apply(_ minute: Int, to which: HoursEnd) -> String? {
        // Midnight ends the day for a window that can't run into the next one.
        let minute = which == .end && !allowsNextDay && minute == 0 ? TimeEntry.day : minute
        if let problem = problem(which, minute) { return problem }
        set(which, minute)
        return nil
    }
}
