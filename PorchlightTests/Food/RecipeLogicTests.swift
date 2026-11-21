import Foundation
import Testing
@testable import Porchlight

/// Recipe text and words (docs/design/dishes.md, "Recipes"): pasted lines lose their
/// bullets and numbers but not their amounts, links get "https://", an ingredient becomes
/// a grocery item, and every line a recipe is shown with.
@Suite("Recipe text and words")
struct RecipeLogicTests {
    @Test("Pasted text loses bullets, numbering and blank lines, never an amount")
    func pasted() {
        let text = """
            • 2 lb chicken thighs
            - 1 onion, diced

            * 1.5 cups rice
            1. Brown the chicken
            12) Simmer 30 min
            Step 3: Serve
            step 4 - Eat
            2 potatoes
            ½ tsp salt
            """
        #expect(RecipeText.pasted(text) == [
            "2 lb chicken thighs", "1 onion, diced", "1.5 cups rice", "Brown the chicken", "Simmer 30 min", "Serve", "Eat",
            "2 potatoes", "½ tsp salt",
        ])
        #expect(RecipeText.lines("  a \n\n b ") == ["a", "b"])
        #expect(RecipeText.stored([" a ", "", "b"]) == "a\nb")
    }

    @Test("A link is a web address, with https added when it was left off")
    func links() throws {
        #expect(try RecipeText.link("").get() == nil)
        #expect(try RecipeText.link(" example.com/curry ").get() == "https://example.com/curry")
        #expect(try RecipeText.link("http://cooking.example.org/r/1").get() == "http://cooking.example.org/r/1")
        #expect(RecipeText.link("curry") == .failure(.invalidLink))
        #expect(RecipeText.link("two words.com") == .failure(.invalidLink))
        #expect(RecipeText.link("ftp://example.com") == .failure(.invalidLink))
    }

    @Test("An ingredient becomes what to buy: no amount, no unit, no way of cutting it", arguments: [
        ("2 lb chicken thighs", "Chicken thighs"), ("1 onion", "Onion"), ("4 cloves garlic", "Garlic"),
        ("1 thumb of ginger", "Ginger"), ("3 tbsp curry powder", "Curry powder"), ("1 can coconut milk", "Coconut milk"),
        ("2 potatoes", "Potatoes"), ("½ tsp salt", "Salt"), ("1/2 cup rice", "Rice"), ("2-3 large tomatoes, chopped", "Tomatoes"),
        ("a pinch of sugar", "Sugar"), ("Parmesan", "Parmesan"), ("salt and pepper", "Salt and pepper"), ("3", "3"),
    ])
    func groceryName(line: String, name: String) {
        #expect(Ingredient.groceryName(line) == name)
    }

    /// November 21, 2026 at noon in Los Angeles.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 19))!
    }

    @Test("How often, and when last, in the bank and on the dish page")
    func words() {
        let now = Self.date(2026, 11, 21)
        #expect(RecipeWords.cooked(0) == "not cooked yet")
        #expect(RecipeWords.cooked(1) == "cooked once")
        #expect(RecipeWords.cooked(2) == "cooked twice")
        #expect(RecipeWords.cooked(6) == "cooked 6 times")
        #expect(RecipeWords.count(0) == "No recipes yet")
        #expect(RecipeWords.count(1) == "1 recipe")
        #expect(RecipeWords.count(4) == "4 recipes")
        #expect(RecipeWords.last(Self.date(2026, 11, 2), now: now, calendar: Self.calendar) == "last Nov 2")
        #expect(RecipeWords.last(Self.date(2025, 12, 24), now: now, calendar: Self.calendar) == "last Dec 24, 2025")
        #expect(RecipeWords.cookedLine(times: 6, last: Self.date(2026, 11, 2), now: now, calendar: Self.calendar) == "Cooked 6 times, last on Nov 2")
        #expect(RecipeWords.cookedLine(times: 1, last: Self.date(2025, 3, 9), now: now, calendar: Self.calendar) == "Cooked once, last on Mar 9, 2025")
        #expect(RecipeWords.cookedLine(times: 0, last: nil, now: now, calendar: Self.calendar) == "Not cooked yet")
        #expect(RecipeWords.bankLine(addedBy: "Mia", hasLink: true, hasCard: false, times: 6, last: Self.date(2026, 11, 2), now: now, calendar: Self.calendar)
            == "Mia's · cooked 6 times · last Nov 2")
        #expect(RecipeWords.bankLine(addedBy: nil, hasLink: true, hasCard: true, times: 2, last: Self.date(2026, 10, 26), now: now, calendar: Self.calendar)
            == "From a link · cooked twice · last Oct 26")
        #expect(RecipeWords.bankLine(addedBy: nil, hasLink: false, hasCard: true, times: 0, last: nil, now: now, calendar: Self.calendar)
            == "📷 Card photo · not cooked yet")
        #expect(RecipeWords.serves(4) == "serves 4")
        #expect(RecipeWords.serves(nil) == nil)
    }

    @Test("A night's dinner at the edge of the day is the day it was eaten, in the household's time zone")
    func lastAcrossMidnight() {
        // 11:30 pm on Nov 2 in Los Angeles is Nov 3 in UTC: the words follow the household.
        let late = Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 23, minute: 30))!
        for hour in stride(from: 0, to: 24, by: 1) {
            let now = Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: hour))!
            #expect(RecipeWords.last(late, now: now, calendar: Self.calendar) == "last Nov 2", "at \(hour):00")
        }
    }

    @Test("Groceries and removing say what happens")
    func sheets() {
        let added = RecipeWords.addedToGroceries(["Ginger", "Coconut milk", "Potatoes"])
        #expect(added.title == "3 items added to groceries")
        #expect(added.detail == "Ginger, coconut milk and potatoes")
        #expect(RecipeWords.addedToGroceries(["Rice"]).title == "1 item added to groceries")
        #expect(RecipeWords.removeSheet(dishName: "Chicken curry", meals: 6, plannedDinners: 1)
            == "Its ingredients, steps, notes and card photos go from every device. Chicken curry stays a dish, with its 6 meals and faces, and its planned dinner stays.")
        #expect(RecipeWords.removeSheet(dishName: "Dumplings", meals: 0, plannedDinners: 0)
            == "Its ingredients, steps, notes and card photos go from every device. Dumplings stays a dish.")
    }
}
