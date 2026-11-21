import Foundation
import Testing
@testable import Porchlight

/// The recipe bank (docs/design/dishes.md, "Recipes"): which recipes it lists and in what
/// order, "Haven't made in a while" with the clock pinned and swept, the dishes we cook
/// often without a recipe, search by name and ingredient, and what a new recipe joins.
@Suite("The recipe bank")
struct RecipeBankTests {
    let db: AppDatabase
    let householdId: Household.ID
    let people: [Person]
    let journal: Journal

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private static func date(_ month: Int, _ day: Int, hour: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    init() throws {
        db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)])
        householdId = household.id
        people = try db.snapshot().people
        journal = try db.ensureFoodJournal(householdId: householdId)
    }

    private func cooked(_ name: String, on date: Date, face: MealRating = .again) throws {
        var draft = MealDraft(day: DayKey(date, calendar: Self.calendar), slot: "Dinner", eaterIds: people.map(\.id), eatenAt: date)
        draft.dishes = [DishLineDraft(name: name, rating: face)]
        _ = try db.addMeal(draft, journalId: journal.id, now: date)
    }

    @discardableResult
    private func recipe(_ name: String, ingredients: [String] = [], at date: Date = date(11, 1)) throws -> Dish {
        try db.saveRecipe(RecipeDraft(name: name, ingredients: ingredients), householdId: householdId, addedBy: people[1].id, now: date).dish
    }

    private func bank() throws -> RecipeBank { RecipeBank(DishBook(try db.foodSnapshot())) }

    @Test("Most cooked first, then most recently cooked; not cooked yet last, newest first")
    func order() throws {
        for day in [2, 9, 16] { try cooked("Pesto pasta", on: Self.date(10, day)) }
        try cooked("Chicken curry", on: Self.date(11, 2))
        try cooked("Fish tacos", on: Self.date(10, 26))
        try recipe("Pesto pasta")
        try recipe("Chicken curry")
        try recipe("Fish tacos")
        try recipe("Dumplings", at: Self.date(11, 3))
        try recipe("Banh xeo", at: Self.date(11, 10))
        #expect(try bank().entries.map(\.dish.name) == ["Pesto pasta", "Chicken curry", "Fish tacos", "Banh xeo", "Dumplings"])
        #expect(try bank().entries.map(\.times) == [3, 1, 1, 0, 0])
    }

    @Test("Haven't made in a while: a liked recipe untouched for three weeks, best liked first, then longest ago")
    func notMadeInAWhile() throws {
        try cooked("Miso salmon", on: Self.date(10, 12), face: .favorite)
        try cooked("Fish tacos", on: Self.date(10, 5), face: .again)
        try cooked("Liver", on: Self.date(9, 1), face: .meh)
        try cooked("Chicken curry", on: Self.date(11, 18))
        for name in ["Miso salmon", "Fish tacos", "Liver", "Chicken curry"] { try recipe(name) }
        let bank = try bank()
        #expect(bank.notMadeInAWhile(now: Self.date(11, 21), calendar: Self.calendar)?.dish.name == "Miso salmon", "the favourite, though tacos waited longer")
        #expect(bank.notMadeInAWhile(now: Self.date(10, 20), calendar: Self.calendar) == nil, "nothing has waited three weeks yet")
    }

    /// The three-week line falls at the start of a day in the household's time zone, so a
    /// recipe last cooked 21 days ago counts all day, every hour of it, in two time zones.
    @Test("The three weeks are whole days, at every hour and in more than one time zone", arguments: ["America/Los_Angeles", "Asia/Tokyo"])
    func sweep(zone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let cookedAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 19)))
        var draft = MealDraft(day: DayKey(cookedAt, calendar: calendar), slot: "Dinner", eaterIds: people.map(\.id), eatenAt: cookedAt)
        draft.dishes = [DishLineDraft(name: "Miso salmon", rating: .favorite)]
        _ = try db.addMeal(draft, journalId: journal.id, now: cookedAt)
        try recipe("Miso salmon")
        let bank = try bank()
        for halfHour in 0..<48 {
            let twenty = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))).addingTimeInterval(TimeInterval(halfHour) * 1_800)
            let twentyOne = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21))).addingTimeInterval(TimeInterval(halfHour) * 1_800)
            #expect(bank.notMadeInAWhile(now: twenty, calendar: calendar) == nil, "20 days on, \(zone), \(halfHour)")
            #expect(bank.notMadeInAWhile(now: twentyOne, calendar: calendar)?.dish.name == "Miso salmon", "21 days on, \(zone), \(halfHour)")
        }
    }

    @Test("You cook these often: home dishes had twice or more with no recipe, most first")
    func cookedOften() throws {
        for day in 1...3 { try cooked("Pesto pasta", on: Self.date(10, day)) }
        for day in 4...5 { try cooked("Chicken curry", on: Self.date(10, day)) }
        try cooked("Toast", on: Self.date(10, 6))
        for day in 7...10 { try cooked("Miso salmon", on: Self.date(10, day)) }
        try recipe("Miso salmon")
        #expect(try bank().cookedOftenWithoutRecipe().map(\.dish.name) == ["Pesto pasta", "Chicken curry"])
        #expect(try bank().cookedOftenWithoutRecipe().map(\.times) == [3, 2])
    }

    @Test("Search finds a recipe by its name or by an ingredient")
    func search() throws {
        try recipe("Chicken curry", ingredients: ["2 lb chicken thighs", "3 tbsp curry powder"])
        try recipe("Pesto pasta", ingredients: ["1 cup basil", "Parmesan"])
        #expect(try bank().search("curry powder").map(\.dish.name) == ["Chicken curry"])
        #expect(try bank().search("pes").map(\.dish.name) == ["Pesto pasta"])
        #expect(try bank().search("parm").map(\.dish.name) == ["Pesto pasta"])
        #expect(try bank().search("").count == 2)
        #expect(try bank().search("tofu").isEmpty)
    }

    @Test("A new recipe joins the home dish of its name, which says how often it was cooked")
    func joins() throws {
        for day in 1...6 { try cooked("Chicken curry", on: Self.date(10, day)) }
        let joined = try #require(try bank().joins("chicken  CURRY"))
        #expect(joined.dish.name == "Chicken curry")
        #expect(joined.times == 6)
        #expect(try bank().joins("Green curry") == nil)
    }
}
