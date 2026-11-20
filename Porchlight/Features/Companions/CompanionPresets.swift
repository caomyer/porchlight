import Foundation

/// Editable defaults per species: starting routines and mood wording.
enum CompanionPresets {
    /// Starting routines for a new companion.
    static func routines(for species: Species) -> [CareRoutineDraft] {
        let morning = CareWindow.hours("Morning", 6, 10)
        let evening = CareWindow.hours("Evening", 17, 20)
        let breakfast = CareWindow.hours("Breakfast", 6, 9)
        let dinner = CareWindow.hours("Dinner", 17, 19)
        switch species {
        case .dog:
            return [
                CareRoutineDraft(kind: .walk, windows: [morning, evening],
                             trackedFields: CareField.allCases, stars: 2, nudgeAfterMinutes: 60),
                CareRoutineDraft(kind: .feed, windows: [breakfast, dinner], stars: 1),
            ]
        case .cat:
            return [
                CareRoutineDraft(kind: .feed, windows: [breakfast, dinner], stars: 1),
                CareRoutineDraft(kind: .litter, windows: [.hours("Evening", 18, 22)], stars: 1),
            ]
        case .bird:
            return [
                CareRoutineDraft(kind: .feed, windows: [.hours("Morning", 7, 10)], stars: 1),
                CareRoutineDraft(kind: .clean, title: "Clean cage", emoji: "🫧", recurrence: .everyNDays(7), windows: [.anyTime], stars: 2),
            ]
        case .rabbit:
            return [
                CareRoutineDraft(kind: .feed, windows: [breakfast, dinner], stars: 1),
                CareRoutineDraft(kind: .clean, title: "Clean hutch", emoji: "🧺", recurrence: .everyNDays(3), windows: [.anyTime], stars: 2),
            ]
        case .fish:
            return [
                CareRoutineDraft(kind: .feed, windows: [.hours("Morning", 7, 10)], stars: 1),
                CareRoutineDraft(kind: .clean, title: "Clean tank", emoji: "🫧", recurrence: .everyNDays(14), windows: [.anyTime], stars: 3),
            ]
        case .plant:
            return [
                CareRoutineDraft(kind: .water, recurrence: .everyNDays(3), windows: [.anyTime], stars: 1),
            ]
        case .other:
            return [
                CareRoutineDraft(kind: .custom, windows: [.hours("Morning", 7, 11)], stars: 1),
            ]
        }
    }

    /// Default window labels and hours when a routine goes to `count` times a day.
    static func windows(count: Int) -> [CareWindow] {
        switch count {
        case ...1: [.hours("Morning", 7, 11)]
        case 2: [.hours("Morning", 6, 10), .hours("Evening", 17, 20)]
        case 3: [.hours("Morning", 6, 10), .hours("Midday", 11, 14), .hours("Evening", 17, 20)]
        default: [.hours("Morning", 6, 9), .hours("Midday", 11, 13), .hours("Afternoon", 15, 17), .hours("Evening", 19, 22)]
        }
    }

    // MARK: Mood

    /// Five moods from low to high, with an emoji each.
    static func moods(for species: Species) -> [(emoji: String, label: String)] {
        switch species {
        case .dog: [("🥺", "Staring at door"), ("😐", "Hopeful sighs"), ("🙂", "Doing fine"), ("😌", "Content, mildly smug"), ("🤪", "Zoomies")]
        case .cat: [("😾", "Plotting revenge"), ("😼", "Judging you"), ("🐱", "Tolerating everyone"), ("😺", "Purring"), ("😻", "Biscuit mode")]
        case .bird: [("🪶", "Ruffled"), ("😐", "Quiet perch"), ("🐦", "Chirpy"), ("🎶", "Singing"), ("🥳", "Full concert")]
        case .rabbit: [("😑", "Thumping"), ("😐", "Loafing"), ("🐰", "Nibbling"), ("😊", "Flopped happy"), ("🤸", "Binkies")]
        case .fish: [("🫧", "Glass surfing"), ("😐", "Hovering"), ("🐟", "Cruising"), ("😊", "Shimmering"), ("✨", "Showing off")]
        case .plant: [("🥀", "Thirsty"), ("😐", "Drooping a bit"), ("🌿", "Doing fine"), ("🌱", "Perky"), ("🌻", "Thriving")]
        case .other: [("😟", "Needs you"), ("😐", "Waiting"), ("🙂", "Doing fine"), ("😊", "Happy"), ("🤩", "Over the moon")]
        }
    }

    static func mood(for species: Species, level: Double) -> (emoji: String, label: String) {
        let moods = moods(for: species)
        let index = min(Int(max(level, 0) * Double(moods.count)), moods.count - 1)
        return moods[index]
    }

    /// Falling confetti for the celebration.
    static func confetti(for species: Species) -> [String] {
        switch species {
        case .dog: ["🐾", "⭐", "🦴", "💛"]
        case .cat: ["🐾", "⭐", "🐟", "💛"]
        case .bird: ["🪶", "⭐", "🌾", "💛"]
        case .rabbit: ["🥕", "⭐", "🌿", "💛"]
        case .fish: ["🫧", "⭐", "🐚", "💙"]
        case .plant: ["💧", "🌱", "⭐", "💚"]
        case .other: ["✨", "⭐", "🎉", "💛"]
        }
    }

    /// The preview line when a companion has just been added.
    static func welcome(name: String, species: Species, routines: [CareRoutineDraft]) -> String {
        guard let first = routines.first else { return "\(name) has joined the household." }
        let noun = CareWords(kind: first.kind, title: first.title, species: species).noun
        if case let .everyNDays(days) = first.recurrence {
            return "\(name) has joined the household and expects a \(noun) every \(days) days. Zero excuses."
        }
        let count = max(first.windows.count, 1)
        let times = count == 1 ? "one \(noun)" : "\(number(count)) \(noun)s"
        return "\(name) has joined the household and expects \(times) a day. Zero excuses."
    }

    static func number(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }
}
