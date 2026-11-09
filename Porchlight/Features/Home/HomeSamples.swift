#if DEBUG
import Foundation

/// Sample chores, rewards, lists and dinners for `-sampleHousehold`. Dates are relative to today.
enum HomeSamples {
    static func seed(_ database: AppDatabase, household: Household, people: [Person]) throws {
        guard let householdId = household.id, let first = people.first?.id else { return }
        let second = people.dropFirst().first?.id ?? first
        let calendar = household.calendar
        let today = DayKey(.now, calendar: calendar)
        let week = HomeWeek(containing: today, calendar: calendar)
        let weekday = calendar.component(.weekday, from: today.startDate(in: calendar))
        let start = today.adding(days: -27, calendar: calendar)

        func chore(_ emoji: String, _ title: String, _ owner: Int64?, _ recurrence: Recurrence, anchor: DayKey? = nil, hint: String?, stars: Int) throws -> Chore {
            try database.saveChore(
                ChoreDraft(title: title, emoji: emoji, ownerId: owner, recurrence: recurrence, anchorDay: anchor ?? start, timeHint: hint, stars: stars),
                householdId: householdId
            )
        }

        // First person
        let breakfast = try chore("🍳", "Make breakfast", first, .daily, hint: "7-9am", stars: 1)
        let recycling = try chore("♻️", "Take out recycling", first, .weekdays([weekday]), hint: "before noon", stars: 2)
        _ = try chore("🔧", "Fix the leaky faucet", first, .once, anchor: week.last, hint: "this weekend", stars: 3)
        // Second person
        let plants = try chore("🪴", "Water the plants", second, .everyNDays(3), hint: nil, stars: 1)
        let dishes = try chore("🍽️", "Run the dishwasher", second, .daily, hint: "after dinner", stars: 1)
        _ = try chore("👕", "Fold laundry", second, .weekdays([weekday, (weekday + 2) % 7 + 1]), hint: "anytime", stars: 2)
        // Anyone
        _ = try chore("🧹", "Vacuum the living room", nil, .once, anchor: week.last, hint: "this weekend", stars: 2)
        let fridge = try chore("🧊", "Clean out the fridge", nil, .once, anchor: today.adding(days: 1, calendar: calendar), hint: "before the weekend", stars: 2)
        let sheets = try chore("🛏️", "Change the sheets", nil, .weekdays([weekday]), hint: "this week", stars: 1)

        // A few weeks of history so stars and the shared goal have something to show.
        let repeating = [breakfast, recycling, plants, dishes, sheets]
        for offset in 1...27 {
            let day = today.adding(days: -offset, calendar: calendar)
            for (index, chore) in repeating.enumerated() where ChoreSchedule.occurs(chore, on: day, calendar: calendar) {
                guard (offset * 7 + index * 3) % 5 != 0 else { continue }
                try database.toggleChore(id: chore.id!, day: day, personId: offset % 2 == 0 ? first : second)
            }
        }
        try database.toggleChore(id: breakfast.id!, day: today, personId: nil)
        try database.toggleChore(id: recycling.id!, day: today, personId: nil)
        try database.toggleChore(id: plants.id!, day: today, personId: nil)
        try database.toggleChore(id: fridge.id!, day: today, personId: second)

        // Rewards: personal treats started about a week ago; the shared fund has been going a while.
        let rewards = [
            (RewardDraft(title: "Fancy coffee run", emoji: "☕", targetStars: 30, ownerId: first), today.adding(days: -9, calendar: calendar)),
            (RewardDraft(title: "Spa afternoon", emoji: "💆", targetStars: 40, ownerId: second), today.adding(days: -11, calendar: calendar)),
            (RewardDraft(title: "Date night fund", emoji: "🍷", targetStars: 100, ownerId: nil), today.adding(days: -20, calendar: calendar)),
        ]
        for (draft, startDay) in rewards {
            let reward = try database.saveReward(draft, householdId: householdId, today: today)
            try database.restartReward(id: reward.id!, from: startDay)
        }

        // Lists
        let groceries = try database.createList(title: "Groceries", kind: .grocery, householdId: householdId)
        let groceryItems: [(String, Int64?, Bool, String?)] = [
            ("Avocados ×3", second, false, nil), ("Basil", nil, true, nil), ("Scallions", first, false, nil),
            ("Limes", nil, false, nil), ("Oat milk", first, false, nil), ("Parmesan", nil, true, nil),
            ("Greek yogurt", second, false, nil), ("White miso", second, false, nil), ("Rice", nil, true, nil),
            ("Candles: 8 and 0", second, false, "For the party"), ("Balloons", first, false, "For the party"),
        ]
        for (title, by, checked, section) in groceryItems {
            let item = try database.addListItem(title: title, to: groceries.id!, section: section, addedBy: by)
            if checked { try database.setListItemChecked(id: item.id!, checked: true) }
        }
        let todo = try database.createList(title: "House", kind: .todo, householdId: householdId)
        let todos: [(String, Int64, Bool)] = [
            ("Order the birthday cake", first, false), ("Book anniversary dinner", first, true),
            ("Renew car registration", second, false), ("Call plumber if faucet still drips", first, false),
            ("Return library books", second, true), ("Pick holiday card photo", second, false),
        ]
        for (title, by, checked) in todos {
            let item = try database.addListItem(title: title, to: todo.id!, addedBy: by)
            if checked { try database.setListItemChecked(id: item.id!, checked: true) }
        }

        // This week's dinners
        let dinners = [
            ("Pancake brunch", "🥞"), ("Pesto pasta", "🍝"), ("Taco Tuesday", "🌮"), ("Miso salmon", "🍲"),
            ("Grandma's dinner", "🎂"), ("Sushi night", "🍣"), ("Dan dan noodles", "🍜"),
        ]
        for (day, dinner) in zip(week.days, dinners) {
            try database.setMeal(day: day, title: dinner.0, emoji: dinner.1, householdId: householdId)
        }
    }
}
#endif
