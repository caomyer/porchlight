import SwiftUI

// The one time control in the app. At rest a time is a pill in Today's serif
// numerals. Tapping it opens a small card from the pill: a few suggestions for
// the usual cases and a number pad for any other time. The iPad's keyboard
// never comes up (iPad has no small number keyboard, and the full one covers
// half the wall), though a hardware keyboard types straight in. A start and
// end is two pills.

/// Which end of a stretch of hours is being typed.
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

/// A time pill and the card it opens. The owner says what a typed time means.
struct TimeFieldControl: View {
    let minute: Int
    var nextDay = false
    var clock: ClockStyle = .current
    var suggestions: [TimeSuggestion] = []
    let accessibilityLabel: String
    let identifier: String
    /// Applies what was typed; returns why it can't be used, if it can't.
    let apply: (String) -> String?
    /// Switches to AM (false) or PM (true); returns why it can't, if it can't.
    let setPeriod: (Bool) -> String?

    @State private var isOpen = false
    @State private var text = ""
    @State private var note: String?

    var body: some View {
        TimeFieldPill(
            minute: minute, nextDay: nextDay, isOpen: isOpen, typed: isOpen ? text : "", clock: clock,
            accessibilityLabel: accessibilityLabel, identifier: identifier
        ) {
            text = ""
            note = nil
            isOpen = true
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            TimeKeypadCard(
                text: $text, note: $note, minute: minute, nextDay: nextDay, clock: clock,
                suggestions: suggestions, accessibilityLabel: accessibilityLabel,
                onSuggestion: { suggestion in
                    if let problem = suggestion.apply() { note = problem } else { close() }
                },
                onPeriod: { pm in
                    // With something typed, AM or PM finishes it: "5" then AM is 5 AM.
                    if !text.isEmpty {
                        if let problem = apply(text + (pm ? "p" : "a")) { note = problem } else { close() }
                    } else {
                        note = setPeriod(pm)
                    }
                },
                onDone: done,
                onCancel: close
            )
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Theme.surface)
        }
        .onChange(of: isOpen) { _, open in
            // Tapping elsewhere keeps a good typed time; a bad one is dropped.
            if !open, !text.isEmpty {
                _ = apply(text)
                text = ""
            }
        }
    }

    private func done() {
        guard !text.isEmpty else { return close() }
        if let problem = apply(text) { note = problem } else { close() }
    }

    private func close() {
        text = ""
        note = nil
        isOpen = false
    }
}

/// A time at rest, or while its card is open with what's been typed so far.
struct TimeFieldPill: View {
    let minute: Int
    var nextDay = false
    var isOpen = false
    var typed = ""
    var clock: ClockStyle = .current
    let accessibilityLabel: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        let parts = clock.parts(minute)
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(typed.isEmpty ? parts.time : typed)
                    .font(.display(19))
                    .monospacedDigit()
                    .foregroundStyle(isOpen && typed.isEmpty ? Theme.muted : Theme.ink)
                if let period = parts.period, typed.isEmpty {
                    Text(period)
                        .font(.body(12, weight: 700))
                        .foregroundStyle(Theme.muted)
                }
                if nextDay {
                    Text("+1")
                        .font(.body(10, weight: 800))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
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

/// The card: what's typed, why it can't be used (if it can't), suggestions,
/// the number pad, AM | PM on a 12-hour clock, and Done.
struct TimeKeypadCard: View {
    @Binding var text: String
    @Binding var note: String?
    let minute: Int
    var nextDay = false
    var clock: ClockStyle = .current
    var suggestions: [TimeSuggestion] = []
    let accessibilityLabel: String
    let onSuggestion: (TimeSuggestion) -> Void
    let onPeriod: (Bool) -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    @FocusState private var hasKeys: Bool

    private static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ":", "0", "⌫"]
    private static let warn = Color(hex: 0xB4532A)

    var body: some View {
        let parts = clock.parts(minute)
        VStack(alignment: .leading, spacing: 12) {
            readout(parts)
            if let note {
                Text(note)
                    .font(.body(13, weight: 600))
                    .foregroundStyle(Self.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("time-note")
            }
            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions) { suggestion in
                        chip(suggestion)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Self.keys, id: \.self) { key in
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
                    .accessibilityIdentifier("key-\(key == "⌫" ? "delete" : key == ":" ? "colon" : key)")
                }
            }
            HStack(spacing: 8) {
                if let period = parts.period {
                    HStack(spacing: 0) {
                        periodButton("AM", isOn: period == "AM") { onPeriod(false) }
                        periodButton("PM", isOn: period == "PM") { onPeriod(true) }
                    }
                    .padding(2)
                    .background(Theme.surface2, in: Capsule())
                }
                Spacer(minLength: 8)
                Button(action: onDone) {
                    Text("Done")
                        .font(.body(14, weight: 800))
                        .foregroundStyle(Theme.surface)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.ink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
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
            case .return: onDone(); return .handled
            case .escape: onCancel(); return .handled
            case .delete, .deleteForward: self.press("⌫"); return .handled
            default:
                let typed = press.characters.lowercased()
                guard typed.count == 1, "0123456789:.apm".contains(typed) else { return .ignored }
                if typed == "a" || typed == "p" {
                    if text.isEmpty { onPeriod(typed == "p") } else { self.press(typed) }
                } else if typed != "m" {
                    self.press(typed == "." ? ":" : typed)
                }
                return .handled
            }
        }
        .onAppear { hasKeys = true }
    }

    private func readout(_ parts: (time: String, period: String?)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text.isEmpty ? parts.time : text)
                .font(.display(30))
                .monospacedDigit()
                .foregroundStyle(text.isEmpty ? Theme.muted : Theme.ink)
            if text.isEmpty, let period = parts.period {
                Text(period).font(.body(13, weight: 700)).foregroundStyle(Theme.muted)
            }
            if nextDay, text.isEmpty {
                Text("+1 day").font(.body(12, weight: 800)).foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(note == nil ? Theme.accent : Self.warn).frame(height: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityLabel), typed")
        .accessibilityValue(text.isEmpty ? clock.text(minute) : text)
        .accessibilityIdentifier("time-entry")
    }

    private func press(_ key: String) {
        note = nil
        if key == "⌫" {
            if !text.isEmpty { text.removeLast() }
        } else if text.count < 6 {
            text.append(key)
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

/// When something happened on a day: the label, then the time on the right.
/// Typed times without AM or PM take the half of the day nearest the time shown,
/// among times that have happened.
struct LogTimeField<Leading: View>: View {
    @Binding var time: LogTime
    /// Within one day, e.g. the meal's day up to now.
    let range: ClosedRange<Date>
    var now: Date = .now
    /// How long it lasted, so "just now" means it just ended.
    var lasting = 0
    var suggestions: [(title: String, time: LogTime)] = []
    let accessibilityLabel: String
    let identifier: String
    var calendar: Calendar = .current
    var clock: ClockStyle = .current
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            leading()
            Spacer(minLength: 8)
            TimeFieldControl(
                minute: minute(resolved), clock: clock, suggestions: shownSuggestions,
                accessibilityLabel: accessibilityLabel, identifier: identifier,
                apply: apply, setPeriod: setPeriod
            )
        }
    }

    private var shownSuggestions: [TimeSuggestion] {
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
                isSelected: time == suggestion.time
            ) {
                time = suggestion.time
                return nil
            }
        }
    }

    // MARK: Times on the day

    private var dayStart: Date { calendar.startOfDay(for: range.lowerBound) }

    private func minute(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.day, .hour, .minute], from: dayStart, to: date)
        return (parts.day ?? 0) * TimeEntry.day + (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func date(_ minute: Int) -> Date {
        calendar.date(byAdding: .minute, value: minute, to: dayStart) ?? dayStart
    }

    private func clamp(_ date: Date) -> Date { min(max(date, range.lowerBound), range.upperBound) }

    private var resolved: Date { clamp(time.start(now: now, lasting: lasting)) }

    private var allowed: ClosedRange<Int> { minute(range.lowerBound)...max(minute(range.lowerBound), minute(range.upperBound)) }

    private func outside(_ minute: Int) -> String {
        minute > allowed.upperBound
            ? "\(clock.text(minute)) is later than now, so it can't be logged yet."
            : "\(clock.text(minute)) is too early for this day."
    }

    // MARK: Typing

    private func apply(_ text: String) -> String? {
        guard let typed = TypedTime.parse(text) else { return "Type a time like 715 or 7:15." }
        switch TimeEntry.pickLogged(typed.candidates(clock), allowed: allowed, near: minute(resolved)) {
        case let .success(minute):
            time = .at(date(minute))
            return nil
        case let .failure(out):
            return outside(out.minute)
        }
    }

    private func setPeriod(_ pm: Bool) -> String? {
        let current = minute(resolved)
        guard (current >= 12 * 60) != pm else { return nil }
        let flipped = pm ? current + 12 * 60 : current - 12 * 60
        guard allowed.contains(flipped) else { return outside(flipped) }
        time = .at(date(flipped))
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
            minute: value(which),
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
            apply: { text in apply(text, to: which) },
            setPeriod: { pm in setPeriod(which, pm) }
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

    private func apply(_ text: String, to which: HoursEnd) -> String? {
        guard let typed = TypedTime.parse(text) else { return "Type a time like 715 or 7:15." }
        let candidates = typed.candidates(clock)
        let minute: Int
        switch which {
        case .start:
            minute = TimeEntry.pickNear(candidates, to: start)
        case .end where allowsNextDay:
            minute = TimeEntry.pickEnd(candidates, after: start)
        case .end:
            // Midnight ends the day.
            minute = candidates.map { $0 == 0 ? TimeEntry.day : $0 }.filter { $0 > start }.min() ?? candidates[0]
        }
        if let problem = problem(which, minute) { return problem }
        set(which, minute)
        return nil
    }

    private func setPeriod(_ which: HoursEnd, _ pm: Bool) -> String? {
        let current = value(which) % TimeEntry.day
        guard (current >= 12 * 60) != pm else { return nil }
        let flipped = pm ? current + 12 * 60 : current - 12 * 60
        if let problem = problem(which, flipped) { return problem }
        set(which, flipped)
        return nil
    }
}
