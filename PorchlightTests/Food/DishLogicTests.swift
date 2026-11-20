import Foundation
import Testing
@testable import Porchlight

@Suite("Dishes: names, kitchens and a meal's copies")
struct DishLogicTests {
    @Test("Case, accents, punctuation and spacing don't make another dish (M3)")
    func sameName() {
        #expect(DishName.key("Phở tái") == "pho tai")
        #expect(DishName.key("  pho   TAI! ") == "pho tai")
        #expect(DishName.key("Bánh xèo") == DishName.key("banh xeo"))
        #expect(DishName.key("Đậu hũ") == "dau hu")
        #expect(DishName.key("Pho") != DishName.key("Pho tai"))
        #expect(DishName.key("7-layer dip") == "7 layer dip")
        #expect(DishName.cleaned("  Bun   cha ") == "Bun cha")
    }

    @Test("A meal's dishes belong to its restaurant, else home, else elsewhere")
    func kitchens() {
        let place = FoodPlace.ID.new()
        #expect(DishKitchen.of(sources: [.dineOut], placeId: place) == .place(place))
        #expect(DishKitchen.of(sources: [.delivery], placeId: place) == .place(place))
        #expect(DishKitchen.of(sources: [.delivery], placeId: nil) == .elsewhere)
        #expect(DishKitchen.of(sources: [.home], placeId: nil) == .home)
        #expect(DishKitchen.of(sources: [.company], placeId: nil) == .elsewhere)
        // Several at once (multi-select Where): a named restaurant wins, then home.
        #expect(DishKitchen.of(sources: [.home, .delivery], placeId: place) == .place(place))
        #expect(DishKitchen.of(sources: [.home, .company], placeId: nil) == .home)
    }

    @Test("A kitchen reads back from its stored form, and an unknown one is elsewhere")
    func kitchenStorage() {
        let place = FoodPlace.ID.new()
        for kitchen in [DishKitchen.home, .place(place), .elsewhere] {
            #expect(DishKitchen(kind: kitchen.kind, placeId: kitchen.placeId) == kitchen)
        }
        #expect(DishKitchen(kind: "garden", placeId: nil) == .elsewhere)
        #expect(DishKitchen(kind: "place", placeId: nil) == .elsewhere)
    }

    @Test("A meal's title is its dishes, the first as written, cut to the limit; none is the slot")
    func titles() {
        #expect(MealCopies.title(dishes: [], slot: "Dinner") == "Dinner")
        #expect(MealCopies.title(dishes: ["Pho tai"], slot: "Dinner") == "Pho tai")
        #expect(MealCopies.title(dishes: ["Pho tai", "Spring rolls", "Bun cha"], slot: "Dinner") == "Pho tai, spring rolls, bun cha")
        #expect(MealCopies.title(dishes: ["Pizza", "BBQ wings"], slot: "Dinner") == "Pizza, BBQ wings")
        let long = MealCopies.title(dishes: ["Salmon nigiri", "Spicy tuna roll", "Miso soup", "Edamame", "Green tea ice cream"], slot: "Dinner")
        #expect(long.count <= AppDatabase.dishTitleLimit)
        #expect(long.hasPrefix("Salmon nigiri, spicy tuna roll, miso soup, edamame"))
        #expect(long.hasSuffix("…"))
    }

    @Test("A meal's face is the best its dishes got, from the table or anyone (F4)")
    func mealFace() {
        #expect(MealCopies.face(tableFaces: [], personFaces: []) == nil)
        #expect(MealCopies.face(tableFaces: [nil, nil], personFaces: []) == nil)
        #expect(MealCopies.face(tableFaces: [.fine, .again], personFaces: []) == .again)
        #expect(MealCopies.face(tableFaces: [.fine, nil], personFaces: [.meh, .favorite]) == .favorite)
    }

    @Test("A person's usual face is the one they gave most, the latest winning a tie")
    func usualFace() {
        #expect(UsualFace.of([]) == nil)
        #expect(UsualFace.of([.favorite, .again, .favorite]) == UsualFace(rating: .favorite, count: 2, of: 3))
        #expect(UsualFace.of([.favorite, .again]) == UsualFace(rating: .again, count: 1, of: 2))
    }
}
