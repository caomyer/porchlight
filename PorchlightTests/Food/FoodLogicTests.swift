import Foundation
import Testing
@testable import Porchlight

@Suite("Food: slots, emoji, stats and memories")
struct FoodLogicTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour, minute: minute))!
    }

    // MARK: Slots

    @Test("The meal is guessed from the time of day")
    func guess() {
        let all = ["Breakfast", "Lunch", "Dinner", "Snack"]
        #expect(MealSlot.guess(at: at(7, 30), calendar: calendar, enabled: all) == "Breakfast")
        #expect(MealSlot.guess(at: at(10, 29), calendar: calendar, enabled: all) == "Breakfast")
        #expect(MealSlot.guess(at: at(10, 30), calendar: calendar, enabled: all) == "Lunch")
        #expect(MealSlot.guess(at: at(12, 45), calendar: calendar, enabled: all) == "Lunch")
        #expect(MealSlot.guess(at: at(15, 30), calendar: calendar, enabled: all) == "Snack")
        #expect(MealSlot.guess(at: at(18, 15), calendar: calendar, enabled: all) == "Dinner")
        #expect(MealSlot.guess(at: at(23, 30), calendar: calendar, enabled: all) == "Snack")
        #expect(MealSlot.guess(at: at(2), calendar: calendar, enabled: all) == "Snack")
    }

    @Test("Without a snack slot, the closest enabled meal wins")
    func guessFallback() {
        let main = ["Breakfast", "Lunch", "Dinner"]
        #expect(MealSlot.guess(at: at(15, 30), calendar: calendar, enabled: main) == "Lunch")
        #expect(MealSlot.guess(at: at(16, 50), calendar: calendar, enabled: main) == "Dinner")
        #expect(MealSlot.guess(at: at(23, 30), calendar: calendar, enabled: main) == "Dinner")
        #expect(MealSlot.guess(at: at(2), calendar: calendar, enabled: main) == "Breakfast")
        #expect(MealSlot.guess(at: at(12), calendar: calendar, enabled: ["Dinner"]) == "Dinner")
        #expect(MealSlot.guess(at: at(12), calendar: calendar, enabled: ["Elevenses"]) == "Elevenses")
        #expect(MealSlot.guess(at: at(12), calendar: calendar, enabled: []) == nil)
    }

    @Test("Known and custom slots")
    func slots() {
        #expect(MealSlot.named("lunch") == .lunch)
        #expect(MealSlot.named("Snack").isMain == false)
        #expect(MealSlot.named("Brunch").emoji == "🍽️")
        #expect(MealSlot.named("Brunch").isMain)
    }

    // MARK: Emoji

    @Test("Emoji are suggested from dish names, most specific first")
    func emoji() {
        #expect(DishIllustration.suggestEmoji(for: "Avocado toast") == "🥑")
        #expect(DishIllustration.suggestEmoji(for: "Pancakes") == "🥞")
        #expect(DishIllustration.suggestEmoji(for: "pesto pasta!") == "🍝")
        #expect(DishIllustration.suggestEmoji(for: "Chicken curry") == "🍛")
        #expect(DishIllustration.suggestEmoji(for: "Dan dan noodles") == "🍜")
        #expect(DishIllustration.suggestEmoji(for: "PHO") == "🍜")
        #expect(DishIllustration.suggestEmoji(for: "Taco night") == "🌮")
        #expect(DishIllustration.suggestEmoji(for: "Banh mi") == "🥪")
        #expect(DishIllustration.suggestEmoji(for: "Eggs & toast") == "🍳")
        #expect(DishIllustration.suggestEmoji(for: "Sushi night") == "🍣")
        #expect(DishIllustration.suggestEmoji(for: "Grandma's lasagna") == "🍝")
        #expect(DishIllustration.suggestEmoji(for: "Mystery casserole") == nil)
        // Whole words only: "subway" is not a "sub".
        #expect(DishIllustration.suggestEmoji(for: "Subway") == nil)
    }

    @Test("Tints are stable, and known dishes get their tablecloth")
    func tints() {
        #expect(DishIllustration.suggestTint(for: "Pancakes") == 0xF3D9A4)
        let tint = DishIllustration.suggestTint(for: "Mystery casserole")
        #expect(DishIllustration.tints.contains(tint))
        #expect(DishIllustration.suggestTint(for: "Mystery casserole") == tint)
    }

    // MARK: Stats

    private func entry(_ title: String, day: String, source: MealSource = .home, rating: MealRating? = .again, slot: String = "Dinner") -> JournalEntry {
        JournalEntry(
            journalId: 1, day: day, slot: slot, source: source, title: title,
            emoji: nil, tint: nil, rating: rating,
            eatenAt: Date(timeIntervalSince1970: 0), createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Home-cooked, delivery, eating out and company food are counted")
    func split() {
        let week = [
            entry("Pho", day: "2026-11-05", source: .delivery), entry("Tacos", day: "2026-11-03"),
            entry("Pizza", day: "2026-11-05", source: .delivery), entry("Salad", day: "2026-11-04"),
            entry("Ramen", day: "2026-11-06", source: .dineOut), entry("Bento", day: "2026-11-06", source: .company),
        ]
        let stats = WeekStats.make(week: week, history: [])
        #expect(stats.homeCooked == 2)
        #expect(stats.delivery == 2)
        #expect(stats.dineOut == 1)
        #expect(stats.company == 1)
        #expect(stats.total == 6)
        #expect(!MealSource.company.hasPlace, "company food names no restaurant")
        #expect(MealSource.company.label == "Company")
    }

    @Test("A theme needs three dishes and lists them in order")
    func theme() {
        let week = [
            entry("Pesto pasta", day: "2026-11-01"),
            entry("Pho", day: "2026-11-05", source: .delivery),
            entry("Dan dan noodles", day: "2026-11-07"),
            entry("Taco night", day: "2026-11-03"),
        ]
        let stats = WeekStats.make(week: week, history: [])
        #expect(stats.theme?.name == "Noodle")
        #expect(stats.themeSentence == "Pesto pasta, pho and dan dan noodles")
        #expect(WeekStats.make(week: Array(week.prefix(2)), history: []).theme == nil)
    }

    @Test("New dishes are the ones never eaten before, best rated first")
    func newDishes() {
        let history = [entry("Pancakes", day: "2026-10-20"), entry("Pho", day: "2026-10-22")]
        let week = [
            entry("pancakes", day: "2026-11-01"),
            entry("Bento box", day: "2026-11-03", rating: .fine),
            entry("Miso salmon", day: "2026-11-04", rating: .favorite),
            entry("Pho!", day: "2026-11-05"),
        ]
        let stats = WeekStats.make(week: week, history: history)
        #expect(stats.newDishes.map(\.title) == ["Miso salmon", "Bento box"])
    }

    @Test("The streak counts back from today, or from yesterday while today is empty")
    func streak() {
        let today = DayKey(rawValue: "2026-11-07")
        let days: Set<DayKey> = Set(["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"].map(DayKey.init(rawValue:)))
        #expect(DiaryStreak.length(activeDays: days, today: today, calendar: calendar) == 4)
        #expect(DiaryStreak.length(activeDays: days.union([today]), today: today, calendar: calendar) == 5)
        let gap: Set<DayKey> = [today, DayKey(rawValue: "2026-11-05")]
        #expect(DiaryStreak.length(activeDays: gap, today: today, calendar: calendar) == 1)
        #expect(DiaryStreak.length(activeDays: [], today: today, calendar: calendar) == 0)
        // Across a month boundary.
        let edge: Set<DayKey> = Set(["2026-10-31", "2026-11-01"].map(DayKey.init(rawValue:)))
        #expect(DiaryStreak.length(activeDays: edge, today: DayKey(rawValue: "2026-11-01"), calendar: calendar) == 2)
    }

    @Test("Missed meals count only main slots of past days")
    func missed() {
        let days = ["2026-11-05", "2026-11-06", "2026-11-07"].map(DayKey.init(rawValue:))
        let entries = [
            entry("Oatmeal", day: "2026-11-05", slot: "Breakfast"),
            entry("Pho", day: "2026-11-05", slot: "Lunch"),
            entry("Pizza", day: "2026-11-05", slot: "Dinner"),
            entry("Falafel", day: "2026-11-06", slot: "Lunch"),
        ]
        let slots = ["Breakfast", "Lunch", "Dinner", "Snack"]
        #expect(DiaryStreak.missedSlots(entries: entries, days: days, today: DayKey(rawValue: "2026-11-07"), slots: slots) == 2)
    }

    // MARK: Memories

    @Test("On this day prefers a year ago, then the closest earlier month")
    func memory() {
        let today = DayKey(rawValue: "2026-11-07")
        let yearAgo = entry("Practice turkey", day: "2025-11-07", rating: .favorite)
        let monthAgo = entry("Ramen", day: "2026-10-07")
        let tenMonths = entry("Gumbo", day: "2026-01-07")
        #expect(FoodMemory.find(in: [monthAgo, yearAgo], today: today, calendar: calendar)?.entry.title == "Practice turkey")
        #expect(FoodMemory.find(in: [monthAgo, yearAgo], today: today, calendar: calendar)?.whenText == "A year ago")
        let fallback = FoodMemory.find(in: [monthAgo, tenMonths], today: today, calendar: calendar)
        #expect(fallback?.entry.title == "Gumbo")
        #expect(fallback?.whenText == "10 months ago")
        #expect(FoodMemory.find(in: [monthAgo], today: today, calendar: calendar)?.whenText == "A month ago")
        #expect(FoodMemory.find(in: [entry("Soup", day: "2026-10-08")], today: today, calendar: calendar) == nil)
        #expect(FoodMemory.find(in: [], today: today, calendar: calendar) == nil)
    }

    @Test("The most memorable meal of the day is chosen")
    func memorable() {
        let today = DayKey(rawValue: "2026-11-07")
        var plain = entry("Toast", day: "2025-11-07", rating: .favorite)
        plain.slot = "Breakfast"
        var photo = entry("Soup", day: "2025-11-07", rating: .fine)
        photo.id = 7
        #expect(FoodMemory.find(in: [plain, photo], withPhotos: [7], today: today, calendar: calendar)?.entry.title == "Soup")
        #expect(FoodMemory.find(in: [plain, photo], today: today, calendar: calendar)?.entry.title == "Toast", "without photos, the rating wins")
        #expect(FoodMemory.find(in: [plain, entry("Rice", day: "2025-11-07", rating: .fine)], today: today, calendar: calendar)?.entry.title == "Toast")
    }

    @Test("Lists read naturally")
    func lists() {
        #expect(ListFormat.join([]) == "")
        #expect(ListFormat.join(["James"]) == "James")
        #expect(ListFormat.join(["James", "Mia"]) == "James and Mia")
        #expect(ListFormat.join(["a", "b", "c"]) == "a, b and c")
    }

    @MainActor
    @Test("Restaurant addresses drop the household's own country")
    func addressCountry() {
        let us = Locale(identifier: "en_US")
        #expect(RestaurantSearch.withoutHomeCountry("744 Laurel St, San Carlos, CA 94070, United States", locale: us) == "744 Laurel St, San Carlos, CA 94070")
        #expect(RestaurantSearch.withoutHomeCountry("1 Rue de Rivoli, Paris, France", locale: us) == "1 Rue de Rivoli, Paris, France")
    }
}
