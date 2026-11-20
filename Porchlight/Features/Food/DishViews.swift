import SwiftUI

// Dish pieces the wall and the phone share (docs/design/dishes.md).

/// A dish's picture: the cover of the latest meal it was on that has a photo, else its emoji
/// on a plate over its tint.
struct DishArt: View {
    let dish: Dish
    var size: CGFloat = 34
    /// Corner radius as a fraction of the side.
    var corner: CGFloat = 0.24

    @Environment(FoodStore.self) private var store

    var body: some View {
        Group {
            if let meal = store.book.times(of: dish.id).first(where: { !store.photos(of: $0.entry).isEmpty })?.entry {
                MealIllustration(entry: meal, plate: 0.62, emojiSize: size * 0.5)
            } else {
                PlateArt(emoji: dish.emoji, tint: Color(hex: UInt32(dish.tint)), plate: 0.66, emojiSize: size * 0.42)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * corner, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The four faces of "Would eat again?", one chosen or none. Tapping the chosen one again
/// clears it, so a face is never forced.
struct FaceChoice: View {
    let rating: MealRating?
    var size: CGFloat = 40
    var font: CGFloat = 20
    let choose: (MealRating?) -> Void

    var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(MealRating.allCases, id: \.self) { face in
                let isOn = rating == face
                Button { choose(isOn ? nil : face) } label: {
                    Text(face.emoji)
                        .font(.system(size: font))
                        .frame(width: size * 1.1, height: size)
                        .background(isOn ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                                .strokeBorder(isOn ? Theme.accent : Theme.line, lineWidth: isOn ? 1.5 : 1)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(face.phrase)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Words for dishes, shared by both shells.
enum DishWords {
    /// "8 times", "once", "twice".
    static func times(_ count: Int) -> String {
        switch count {
        case 0: "not yet"
        case 1: "once"
        case 2: "twice"
        default: "\(count) times"
        }
    }

    /// "8th time here", "New here", "7th time".
    static func ordinal(_ n: Int, here: Bool) -> String {
        if n <= 1 { return here ? "New here" : "New" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let word = formatter.string(from: NSNumber(value: n)) ?? "\(n)"
        return here ? "\(word) time here" : "\(word) time"
    }

    /// Where a dish comes from: the restaurant's name, "Home" or "Elsewhere".
    static func kitchen(_ dish: Dish, places: [FoodPlace]) -> String {
        switch dish.kitchen {
        case .home: "Home"
        case let .place(id): places.first { $0.id == id }?.name ?? "A restaurant"
        case .elsewhere: "Elsewhere"
        }
    }

    /// "last today", "last Wednesday", "last Nov 8": when a dish or a place was last had.
    static func last(_ entry: JournalEntry, today: DayKey, calendar: Calendar) -> String {
        let day = day(entry, today: today, calendar: calendar)
        return "last " + (entry.dayKey >= today.adding(days: -1, calendar: calendar) ? day.lowercased() : day)
    }

    /// "Mar '25", "Sunday", "Nov 8": a date in a dish's stats, near ones by weekday.
    static func day(_ entry: JournalEntry, today: DayKey, calendar: Calendar) -> String {
        let date = entry.dayKey.startDate(in: calendar)
        let style = Date.FormatStyle(timeZone: calendar.timeZone)
        if entry.dayKey == today { return "Today" }
        if entry.dayKey == today.adding(days: -1, calendar: calendar) { return "Yesterday" }
        if entry.dayKey > today.adding(days: -7, calendar: calendar) { return date.formatted(style.weekday(.wide)) }
        if calendar.isDate(date, equalTo: today.startDate(in: calendar), toGranularity: .year) {
            return date.formatted(style.month(.abbreviated).day())
        }
        return date.formatted(style.month(.abbreviated)) + " '" + date.formatted(style.year(.twoDigits))
    }

    /// "You 🤩 · Mia 😋 · Ava 🙂": each eater's face on one time.
    static func faces(_ faces: [Person.ID: MealRating], people: [Person], me: Person.ID?) -> String {
        people.compactMap { person in
            faces[person.id].map { "\(person.id == me ? "You" : person.name) \($0.emoji)" }
        }
        .joined(separator: " · ")
    }
}
