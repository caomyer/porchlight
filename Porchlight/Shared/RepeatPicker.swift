import SwiftUI

/// What the repeat picker edits: the pattern, its details and the day it starts
/// (the due day for one-offs). Turns into a `Recurrence` plus a start `DayKey`.
struct RepeatChoice: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case daily, weekdays, interval, monthly, once
        var id: String { rawValue }
        var label: String {
            switch self {
            case .daily: "Every day"
            case .weekdays: "Some days"
            case .interval: "Every few days"
            case .monthly: "Monthly"
            case .once: "Just once"
            }
        }
    }

    var kind: Kind
    var weekdays: Set<Int>
    var interval: Int
    var start: Date

    init(recurrence: Recurrence, start: DayKey, calendar: Calendar) {
        self.start = start.startDate(in: calendar)
        weekdays = [calendar.component(.weekday, from: self.start)]
        interval = 3
        switch recurrence {
        case .daily: kind = .daily
        case let .weekdays(days): kind = .weekdays; weekdays = days
        case let .everyNDays(n): kind = .interval; interval = max(n, 2)
        case .monthly: kind = .monthly
        case .once: kind = .once
        }
    }

    var recurrence: Recurrence {
        switch kind {
        case .daily: .daily
        case .weekdays: .weekdays(weekdays)
        case .interval: .everyNDays(interval)
        case .monthly: .monthly
        case .once: .once
        }
    }

    func startDay(calendar: Calendar) -> DayKey { DayKey(start, calendar: calendar) }

    /// "Every Mon and Thu, from Nov 10", read back under the picker.
    func summary(today: DayKey, calendar: Calendar) -> String {
        let day = startDay(calendar: calendar)
        if kind == .once {
            return "Due " + day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day(), calendar: calendar)
                + ". It stays on the board until it's done."
        }
        if kind == .weekdays && weekdays.isEmpty { return "Pick at least one day." }
        let pattern = recurrence.describe(start: day, calendar: calendar)
        let first = recurrence.nextDay(onOrAfter: day, start: day, calendar: calendar)
        let from: String
        if day <= today {
            if let next = recurrence.nextDay(onOrAfter: today, start: day, calendar: calendar) {
                from = next == today ? "Next: today" : "Next: " + next.formatted(.dateTime.weekday(.wide).month(.abbreviated).day(), calendar: calendar)
            } else {
                from = ""
            }
        } else {
            from = "First: " + (first ?? day).formatted(.dateTime.weekday(.wide).month(.abbreviated).day(), calendar: calendar)
        }
        return pattern.prefix(1).uppercased() + pattern.dropFirst() + (from.isEmpty ? "." : ". " + from + ".")
    }
}

/// How often something repeats and when it starts, the same for chores and routines:
/// the pattern chips, their detail (days of the week, how many days), a start (or due)
/// date, and a plain sentence saying what that means.
struct RepeatPicker: View {
    @Binding var choice: RepeatChoice
    var kinds: [RepeatChoice.Kind] = RepeatChoice.Kind.allCases
    let calendar: Calendar
    let today: DayKey
    var maxInterval = 365

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(kinds) { kind in
                    ChoiceChip(title: kind.label, isSelected: choice.kind == kind) { choice.kind = kind }
                }
            }
            detail
            HStack(spacing: 10) {
                Text(choice.kind == .once ? "Due" : "Starts")
                    .font(.body(15, weight: 700))
                DatePicker(choice.kind == .once ? "Due" : "Starts", selection: $choice.start, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.accent)
                Spacer(minLength: 0)
            }
            Text(choice.summary(today: today, calendar: calendar))
                .font(.body(14, weight: 600))
                .foregroundStyle(choice.kind == .weekdays && choice.weekdays.isEmpty ? Theme.accent : Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("repeatSummary")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch choice.kind {
        case .weekdays:
            HStack(spacing: 6) {
                ForEach(Recurrence.orderedWeekdays(calendar: calendar), id: \.self) { day in
                    let isOn = choice.weekdays.contains(day)
                    Button {
                        if isOn { choice.weekdays.remove(day) } else { choice.weekdays.insert(day) }
                    } label: {
                        Text(calendar.veryShortWeekdaySymbols[day - 1])
                            .font(.body(15, weight: 700))
                            .foregroundStyle(isOn ? Theme.surface : Theme.ink)
                            .frame(width: 40, height: 40)
                            .background(isOn ? Theme.ink : Theme.surface2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendar.weekdaySymbols[day - 1])
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        case .interval:
            CountStepper(value: $choice.interval, range: 2...maxInterval, suffix: "days")
        case .daily, .monthly, .once:
            EmptyView()
        }
    }
}
