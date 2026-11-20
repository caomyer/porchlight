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

    /// "Nov 10 to 16 · 20 meals", or "Oct 27 to Nov 2 · 1 meal".
    static func weekLine(_ days: [DayKey], meals: Int, calendar: Calendar) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let start = first.startDate(in: calendar)
        let end = last.startDate(in: calendar)
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let from = start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
        let to = sameMonth
            ? "\(calendar.component(.day, from: end))"
            : end.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
        return "\(from) to \(to) · \(meals == 1 ? "1 meal" : "\(meals) meals")"
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
