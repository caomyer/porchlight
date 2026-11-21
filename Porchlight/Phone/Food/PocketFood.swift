import Foundation

/// The words and shapes of Food on the phone, worked out from the diary without any view:
/// the week the tab shows, its header, who ate a meal and who added it, and what saving
/// says. Pure, covered by PocketFoodTests.
enum PocketFood {
    /// The seven days ending today, as on the wall, so the current week is always full
    /// and today is the last column.
    static func week(endingOn today: DayKey, calendar: Calendar) -> [DayKey] {
        (-6...0).map { today.adding(days: $0, calendar: calendar) }
    }

    /// The seven days `weeksBack` weeks before the ones ending today: the same seven-day
    /// steps as the wall's "previous week" (docs/proposals/food-diary-polish.html).
    static func week(endingOn today: DayKey, weeksBack: Int, calendar: Calendar) -> [DayKey] {
        week(endingOn: today.adding(days: -7 * weeksBack, calendar: calendar), calendar: calendar)
    }

    /// How many weeks back the diary goes: to the week holding the household's first meal,
    /// and no further. With no meals, or none before this week, it stays on this week.
    static func weeksBackLimit(firstDay: DayKey?, today: DayKey, calendar: Calendar) -> Int {
        firstDay.map { weeksBack(of: $0, today: today, calendar: calendar) } ?? 0
    }

    /// Which week a day is in, counted back from the one ending today: after a meal is
    /// saved the diary shows its week, so "Snap a meal" (which logs now) comes back to this
    /// week, and a slot filled in a past week stays there.
    static func weeksBack(of day: DayKey, today: DayKey, calendar: Calendar) -> Int {
        guard day < today else { return 0 }
        let days = calendar.dateComponents([.day], from: day.startDate(in: calendar), to: today.startDate(in: calendar)).day ?? 0
        return max(0, days / 7)
    }

    /// The week pager's name for a week: "This week", "Last week", "3 weeks ago".
    static func weekName(weeksBack: Int) -> String {
        switch weeksBack {
        case ...0: "This week"
        case 1: "Last week"
        default: "\(weeksBack) weeks ago"
        }
    }

    /// What the week pager says to VoiceOver: "Last week, Nov 8 to 14, 18 meals".
    static func weekSpoken(_ days: [DayKey], weeksBack: Int, meals: Int, calendar: Calendar) -> String {
        "\(weekName(weeksBack: weeksBack)), \(range(days, calendar: calendar)), \(mealCount(meals))"
    }

    /// A past week with nothing in it: what it says in place of the day cards.
    static func emptyWeek(_ days: [DayKey], calendar: Calendar) -> (title: String, detail: String) {
        ("Nothing logged \(range(days, calendar: calendar))", "Tap a slot to add a meal you remember.")
    }

    /// "Nov 10 to 16 · 20 meals", "Oct 27 to Nov 2 · 1 meal", or "Oct 25 to 31 · no meals".
    static func weekLine(_ days: [DayKey], meals: Int, calendar: Calendar) -> String {
        guard !days.isEmpty else { return "" }
        return "\(range(days, calendar: calendar)) · \(mealCount(meals))"
    }

    private static func mealCount(_ meals: Int) -> String {
        switch meals {
        case 0: "no meals"
        case 1: "1 meal"
        default: "\(meals) meals"
        }
    }

    /// "Nov 10 to 16", or "Oct 27 to Nov 2".
    static func range(_ days: [DayKey], calendar: Calendar) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let start = first.startDate(in: calendar)
        let end = last.startDate(in: calendar)
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let from = start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
        let to = sameMonth
            ? "\(calendar.component(.day, from: end))"
            : end.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
        return "\(from) to \(to)"
    }

    /// A slot's name where a column of seven is tight: "Bkfst", "Lunch", "Dinner".
    static func shortSlot(_ slot: String) -> String {
        slot.caseInsensitiveCompare("Breakfast") == .orderedSame ? "Bkfst" : slot
    }

    /// "Sunday dinner": the meal a photo goes to, as the polaroid's caption says it.
    static func mealName(day: DayKey, slot: String, calendar: Calendar) -> String {
        let weekday = day.startDate(in: calendar).formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide))
        return "\(weekday) \(slot.lowercased())"
    }

    /// "Today", "Yesterday", then the weekday, for the diary's day headings.
    static func dayTitle(_ day: DayKey, today: DayKey, calendar: Calendar) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1, calendar: calendar) { return "Yesterday" }
        return day.startDate(in: calendar).formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide))
    }

    /// Who ate, with me as "you" and first: "You and Mia", "Mia", or "Everyone" when the
    /// whole household of three or more did.
    static func eaters(_ people: [Person], everyone: Bool, householdSize: Int, me: Person.ID?) -> String {
        if everyone && householdSize > 2 { return "Everyone" }
        let mine = people.filter { $0.id == me }.map { _ in "you" }
        let names = mine + people.filter { $0.id != me }.map(\.name)
        let sentence = ListFormat.join(names)
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// "added by you", "added by Mia", "added on Hallway iPad": who wrote the meal, from the
    /// device stamped on it. Nil for a meal from before devices were known.
    static func addedBy(_ deviceId: Device.ID?, devices: [Device], everyone: [Person], me: Person.ID?) -> String? {
        guard let device = deviceId.flatMap({ id in devices.first { $0.id == id } }) else { return nil }
        if let owner = device.owner {
            if owner == me { return "added by you" }
            if let person = everyone.person(owner) { return "added by \(person.name)" }
        }
        return "added on \(device.name)"
    }

    /// What the toast says once a meal is saved: "Saved to Sunday dinner", then where it
    /// came from and who ate it, "Pho Huynh · you and Mia".
    static func savedToast(_ entry: JournalEntry, placeName: String?, eaters: String, calendar: Calendar) -> (title: String, detail: String) {
        let title = "Saved to \(mealName(day: entry.dayKey, slot: entry.slot, calendar: calendar))"
        let named = placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = entry.sources.hasPlace && named?.isEmpty == false ? named! : entry.sources.label
        // "you and Mia", "everyone", but never "mia".
        let starts = ["You", "Everyone"].contains { eaters == $0 || eaters.hasPrefix($0 + " ") }
        let who = starts ? eaters.prefix(1).lowercased() + eaters.dropFirst() : eaters
        return (title, "\(source) · \(who)")
    }

    /// The details line of a meal row: "Dinner · Dine out · Pho Saigon House".
    static func mealLine(_ entry: JournalEntry, place: FoodPlace?) -> String {
        [entry.slot, entry.sources.label, place?.name].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Dinner · Sunday 6:40pm", over the details of a meal being saved.
    static func whenLine(slot: String, eatenAt: Date, calendar: Calendar) -> String {
        let weekday = eatenAt.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide))
        return "\(slot) · \(weekday) \(CareText.timeWithPeriod(eatenAt, calendar: calendar))"
    }
}
