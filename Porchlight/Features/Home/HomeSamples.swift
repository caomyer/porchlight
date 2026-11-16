#if DEBUG
import Foundation
import UIKit

/// Sample chores, rewards, lists and dinners for `-sampleHousehold`. Dates are relative to today.
enum HomeSamples {
    static func seed(_ database: AppDatabase, household: Household, people: [Person]) throws {
        guard let first = people.first?.id else { return }
        let householdId = household.id
        let second = people.dropFirst().first?.id ?? first
        let calendar = household.calendar
        let today = DayKey(.now, calendar: calendar)
        let week = HomeWeek(containing: today, calendar: calendar)
        let weekday = calendar.component(.weekday, from: today.startDate(in: calendar))
        let start = today.adding(days: -27, calendar: calendar)

        func chore(_ emoji: String, _ title: String, _ owner: Person.ID?, _ recurrence: Recurrence, anchor: DayKey? = nil, hint: String?, stars: Int) throws -> Chore {
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
                try database.toggleChore(id: chore.id, day: day, personId: offset % 2 == 0 ? first : second)
            }
        }
        try database.toggleChore(id: breakfast.id, day: today, personId: nil)
        try database.toggleChore(id: recycling.id, day: today, personId: nil)
        try database.toggleChore(id: plants.id, day: today, personId: nil)
        try database.toggleChore(id: fridge.id, day: today, personId: second)

        // Rewards: personal treats started about a week ago; the shared fund has been going a while.
        let rewards = [
            (RewardDraft(title: "Fancy coffee run", emoji: "☕", targetStars: 20, ownerId: first), today.adding(days: -4, calendar: calendar)),
            (RewardDraft(title: "Spa afternoon", emoji: "💆", targetStars: 80, ownerId: second), today.adding(days: -11, calendar: calendar)),
            (RewardDraft(title: "Date night fund", emoji: "🍷", targetStars: 250, ownerId: nil), today.adding(days: -20, calendar: calendar)),
        ]
        var coffeeRun: Reward?
        for (draft, startDay) in rewards {
            let reward = try database.saveReward(draft, householdId: householdId, today: today)
            try database.restartReward(id: reward.id, from: startDay)
            if draft.targetStars == 20 { coffeeRun = reward }
        }
        // The coffee run should be reached, ready to cash in. How many stars the last few
        // days hold depends on the hour (today's walks are only seeded once they are past),
        // so start it on the latest day that still gets there.
        if let id = coffeeRun?.id {
            for daysAgo in 4...20 {
                let startDay = today.adding(days: -daysAgo, calendar: calendar)
                try database.restartReward(id: id, from: startDay)
                let snapshot = try database.homeSnapshot(since: startDay)
                guard let reward = snapshot.rewards.first(where: { $0.id == id }) else { break }
                if RewardProgress.earned(for: reward, earnings: snapshot.earnings) >= reward.targetStars { break }
            }
        }
        // A treat already enjoyed last week, for the Glow page's "Lately".
        let treat = try database.saveReward(
            RewardDraft(title: "Ice cream trip", emoji: "🍦", targetStars: 20, ownerId: first), householdId: householdId, today: today
        )
        let cashedIn = today.adding(days: -5, calendar: calendar)
        try database.cashInReward(id: treat.id, stars: 20, day: cashedIn, after: nil, now: cashedIn.startDate(in: calendar).addingTimeInterval(17 * 3600))
        try database.setRewardArchived(id: treat.id, archived: true)

        // Lists
        let groceries = try database.createList(title: "Groceries", kind: .grocery, householdId: householdId)
        let groceryItems: [(String, Person.ID?, Bool, String?)] = [
            ("Avocados ×3", second, false, nil), ("Basil", nil, true, nil), ("Scallions", first, false, nil),
            ("Limes", nil, false, nil), ("Oat milk", first, false, nil), ("Parmesan", nil, true, nil),
            ("Greek yogurt", second, false, nil), ("White miso", second, false, nil), ("Rice", nil, true, nil),
            ("Candles: 8 and 0", second, false, "For the party"), ("Balloons", first, false, "For the party"),
        ]
        for (title, by, checked, section) in groceryItems {
            let item = try database.addListItem(title: title, to: groceries.id, section: section, addedBy: by)
            if checked { try database.setListItemChecked(id: item.id, checked: true) }
        }
        let todo = try database.createList(title: "House", kind: .todo, householdId: householdId)
        let todos: [(String, Person.ID, Bool)] = [
            ("Order the birthday cake", first, false), ("Book anniversary dinner", first, true),
            ("Renew car registration", second, false), ("Call plumber if faucet still drips", first, false),
            ("Return library books", second, true), ("Pick holiday card photo", second, false),
        ]
        for (title, by, checked) in todos {
            let item = try database.addListItem(title: title, to: todo.id, addedBy: by)
            if checked { try database.setListItemChecked(id: item.id, checked: true) }
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

    /// `-samplePhotos N` adds N painted photos to the frame, for the photo manager and the slideshow.
    /// Sample launches use their own storage sandbox, so these never reach the household's photos.
    @MainActor
    static func seedPhotos(_ count: Int, database: AppDatabase, householdId: Household.ID) throws {
        let library = AmbientPhotoLibrary.shared
        try FileManager.default.createDirectory(at: library.folder, withIntermediateDirectories: true)
        let months = ["Nov 2026", "Oct 2026", "Sep 2026", "Aug 2026", "Jul 2026", "Jun 2026"]
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        for index in 0..<count {
            let hue = CGFloat(index * 37 % 360) / 360
            let image = renderer.image { context in
                let colors = [
                    UIColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1).cgColor,
                    UIColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.55, alpha: 1).cgColor,
                ] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 900), options: [])
                UIColor.white.withAlphaComponent(0.85).setFill()
                UIBezierPath(ovalIn: CGRect(x: 760, y: 160, width: 180, height: 180)).fill()
            }
            guard let jpeg = image.jpegData(compressionQuality: 0.8) else { continue }
            let fileName = "sample-\(index)-\(UUID().uuidString).jpg"
            try jpeg.write(to: library.url(for: fileName), options: .atomic)
            _ = try database.addAmbientPhoto(
                fileName: fileName, caption: months[(count - 1 - index) / 4 % months.count], householdId: householdId,
                now: .now.addingTimeInterval(Double(index - count) * 3600)
            )
        }
    }
}
#endif
