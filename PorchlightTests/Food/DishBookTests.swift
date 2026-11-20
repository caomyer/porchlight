import Foundation
import GRDB
import Testing
@testable import Porchlight

@Suite("Dishes: memory, places and suggestions")
struct DishBookTests {
    let db: AppDatabase
    let people: [Person]
    let journal: Journal

    init() throws {
        db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "The Lake House", people: [
            PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral), PersonDraft(name: "Ava", color: .ochre),
        ])
        people = try db.snapshot().people
        journal = try db.ensureFoodJournal(householdId: household.id)
    }

    @discardableResult
    private func meal(_ dishes: [(String, MealRating?)], at place: String? = "Pho Saigon House", day: Int, eaters: [Int] = [0, 1, 2]) throws -> JournalEntry {
        var draft = MealDraft(
            day: DayKey(rawValue: String(format: "2026-10-%02d", day)), slot: "Dinner", sources: MealSources(place == nil ? .home : .dineOut),
            eaterIds: eaters.map { people[$0].id }, eatenAt: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
            place: place.map { PlaceDraft(name: $0) }
        )
        draft.dishes = dishes.map { DishLineDraft(name: $0.0, rating: $0.1) }
        return try db.addMeal(draft, journalId: journal.id)
    }

    private var book: DishBook { get throws { DishBook(try db.foodSnapshot()) } }

    private func dish(_ name: String, home: Bool = false) throws -> Dish {
        try #require(try book.liveDishes.first { $0.name == name && ($0.kitchen == .home) == home })
    }

    @Test("A dish remembers every time, first and last, and each person's usual face (M4)")
    func memory() throws {
        try meal([("Pho tai", .favorite)], day: 1)
        try meal([("Pho tai", .again)], day: 8)
        let last = try meal([("Pho tai", .favorite), ("Spring rolls", .again)], day: 15, eaters: [0, 1])
        let pho = try dish("Pho tai")
        try db.setPersonFace(lineId: try #require(try book.dishes(of: last).first?.line.id), personId: people[1].id, .again)

        let summary = try book.summary(of: pho.id)
        #expect(summary.count == 3)
        #expect(summary.first?.day == "2026-10-01")
        #expect(summary.last?.id == last.id)
        let times = try book.times(of: pho.id)
        #expect(times.map(\.entry.day) == ["2026-10-15", "2026-10-08", "2026-10-01"])
        #expect(times[0].faces == [people[0].id: .favorite, people[1].id: .again])

        let usual = try book.usualFaces(of: pho.id)
        #expect(usual.map(\.person.name) == ["James", "Mia", "Ava"])
        #expect(usual[0].face == UsualFace(rating: .favorite, count: 2, of: 3))
        #expect(usual[1].face == UsualFace(rating: .again, count: 2, of: 3))
        #expect(usual[2].face == UsualFace(rating: .again, count: 1, of: 2))
        #expect(try book.ordinal(of: try book.dishes(of: last)[0].line) == 3)
    }

    @Test("A restaurant's page: visits, last time's dishes, and its dishes best face first (M5)")
    func place() throws {
        try meal([("Banh xeo", .meh)], day: 1)
        try meal([("Pho tai", .favorite), ("Spring rolls", .again)], day: 8)
        try meal([("Bun bo Hue", .fine)], day: 10)
        try meal([("Pho tai", .favorite), ("Spring rolls", .again), ("Bun cha", .fine)], day: 15)
        try meal([("Pho tai", .fine)], at: "Pho 2000", day: 16)
        let place = try #require(try db.foodSnapshot().places.first { $0.name == "Pho Saigon House" })
        let summary = try book.summary(of: place.id)
        #expect(summary.visits == 4)
        #expect(summary.lastDishes.map(\.name) == ["Pho tai", "Spring rolls", "Bun cha"])
        #expect(summary.dishes.map(\.name) == ["Pho tai", "Spring rolls", "Bun cha", "Bun bo Hue", "Banh xeo"])
        // "Last time here", leaving out the meal being logged.
        let latest = try #require(summary.last)
        #expect(try book.lastTime(at: place.id, excluding: latest.id)?.dishes.map(\.name) == ["Bun bo Hue"])
    }

    @Test("Suggestions: this restaurant's dishes first, most had first, then the same words elsewhere (M1)")
    func restaurantSuggestions() throws {
        try meal([("Bun bo Hue", .fine)], day: 1)
        try meal([("Bun bo Hue", .fine)], day: 2)
        try meal([("Bun cha", .again)], day: 3)
        try meal([("Bun rieu", .again)], at: "Pho 2000", day: 4)
        try meal([("Bun cha", .again)], at: "Pho 2000", day: 5)
        try meal([("Banh mi", .again)], at: nil, day: 6)
        let place = try #require(try db.foodSnapshot().places.first { $0.name == "Pho Saigon House" })
        let found = try book.suggestions(for: "bun", kitchen: .place(place.id))
        #expect(found.map(\.dish.name) == ["Bun bo Hue", "Bun cha", "Bun rieu"])
        #expect(found.map(\.isHere) == [true, true, false])
        #expect(found[0].count == 2)
        // Several words, each starting a word; what's already on the meal is left out.
        #expect(try book.suggestions(for: "bun c", kitchen: .place(place.id)).map(\.dish.name) == ["Bun cha"])
        let bunCha = try #require(found.first { $0.dish.name == "Bun cha" })
        #expect(try book.suggestions(for: "bun", kitchen: .place(place.id), excluding: [bunCha.id]).map(\.dish.name) == ["Bun bo Hue", "Bun rieu"])
        #expect(try book.suggestions(for: "  ", kitchen: .home).isEmpty)
    }

    @Test("At home, suggestions are what we cook, most cooked first (M2)")
    func homeSuggestions() throws {
        try meal([("Chicken curry", .again)], at: nil, day: 1)
        try meal([("Chicken curry", .favorite)], at: nil, day: 2)
        try meal([("Chicken noodle soup", .fine)], at: nil, day: 3)
        try meal([("Chicken tikka", .again)], at: "Curry Up Now", day: 4)
        let found = try book.suggestions(for: "chi", kitchen: .home)
        #expect(found.map(\.dish.name) == ["Chicken curry", "Chicken noodle soup", "Chicken tikka"])
        #expect(found.map(\.isHere) == [true, true, false])
    }

    @Test("Favourites, home, places and search (M6, M7)")
    func lists() throws {
        try meal([("Pho tai", .favorite)], day: 1)
        try meal([("Pho tai", .favorite)], day: 2)
        try meal([("Pesto pasta", .favorite)], at: nil, day: 3)
        try meal([("Katsu curry", .fine)], at: "Sakura Sushi Bar", day: 4)
        try meal([("Chicken curry", .again)], at: nil, day: 5)
        try db.setFavorite(dishId: try dish("Pesto pasta", home: true).id, true)
        #expect(try book.favorites.map(\.name) == ["Pesto pasta"])
        #expect(try book.homeDishes.map(\.name) == ["Chicken curry", "Pesto pasta"])
        #expect(try book.placesWithDishes.map(\.place.name) == ["Pho Saigon House", "Sakura Sushi Bar"])
        let found = try book.search("curry")
        #expect(Set(found.dishes.map(\.name)) == ["Katsu curry", "Chicken curry"])
        #expect(try book.search("saigon").places.map(\.name) == ["Pho Saigon House"])
        #expect(try book.alsoHad(try dish("Pho tai")).isEmpty)
    }

    @Test("The same name in another kitchen is linked as \"also had at\"")
    func alsoHad() throws {
        try meal([("Pho tai", .favorite)], day: 1)
        try meal([("Pho tai", .fine)], at: nil, day: 2)
        let names = try book.alsoHad(try dish("Pho tai")).map(\.kitchen)
        #expect(names == [.home])
    }

    @Test("A merged dish is never listed, and its lines count for the one it joined")
    func merged() throws {
        try meal([("Spring rolls", .again)], day: 1)
        try meal([("Imperial rolls", .fine)], day: 2)
        try db.mergeDish(id: try dish("Spring rolls").id, into: try dish("Imperial rolls").id)
        #expect(try book.liveDishes.map(\.name) == ["Imperial rolls"])
        #expect(try book.summary(of: try dish("Imperial rolls").id).count == 2)
    }
}
