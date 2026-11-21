import Foundation
import Testing
@testable import Porchlight

@Suite("Dishes: the editor's lines")
struct DishLinesEditTests {
    @Test("Adding a dish: blank, the same name twice, the same dish twice and a thirteenth add nothing")
    func adding() {
        var edit = DishLinesEdit()
        do { let result = edit.add("Pho tai"); #expect(result) }
        do { let result = edit.add("  "); #expect(!result) }
        do { let result = edit.add("phở TÁI"); #expect(!result, "the same dish, whatever its case or accents") }
        let rolls = Dish.ID.new()
        do { let result = edit.add("Spring rolls", dishId: rolls); #expect(result) }
        do { let result = edit.add("Imperial rolls", dishId: rolls); #expect(!result, "the same dish picked twice") }
        for n in 3...12 { do { let result = edit.add("Dish \(n)"); #expect(result) } }
        #expect(edit.isFull)
        do { let result = edit.add("Thirteen"); #expect(!result) }
        #expect(edit.lines.count == 12)
    }

    @Test("What is typed when the meal saves is its last dish")
    func typedTextSaves() {
        var edit = DishLinesEdit()
        #expect(edit.isEmpty)
        edit.text = "Bun cha"
        #expect(!edit.isEmpty)
        #expect(edit.drafts.map(\.name) == ["Bun cha"])
        edit.add("Pho tai")
        #expect(edit.drafts.map(\.name) == ["Pho tai", "Bun cha"])
        edit.text = "pho tai"
        #expect(edit.drafts.map(\.name) == ["Pho tai"], "typing a dish already on the meal adds nothing")
    }

    @Test("Committing the field adds its dish and clears it; a duplicate clears it too")
    func commit() {
        var edit = DishLinesEdit()
        edit.text = "  Spring   rolls "
        do { let result = edit.commitText(); #expect(result) }
        #expect(edit.text.isEmpty)
        #expect(edit.lines.map(\.name) == ["Spring rolls"])
        edit.text = "spring rolls"
        do { let result = edit.commitText(); #expect(!result) }
        #expect(edit.text.isEmpty)
    }

    @Test("Lines move, take a face, and come off")
    func editing() {
        var edit = DishLinesEdit()
        edit.add("A")
        edit.add("B")
        edit.add("C")
        let c = edit.lines[2].id
        edit.move(c, by: -2)
        #expect(edit.lines.map(\.name) == ["C", "A", "B"])
        edit.move(c, by: -1)
        #expect(edit.lines.map(\.name) == ["C", "A", "B"], "the first stays first")
        edit.move(edit.lines[1].id, by: 5)
        #expect(edit.lines.map(\.name) == ["C", "B", "A"])
        edit.setRating(c, .favorite)
        edit.remove(edit.lines[1].id)
        #expect(edit.drafts == [DishLineDraft(name: "C", rating: .favorite), DishLineDraft(name: "A")])
    }

    @Test("The form's kitchen: a named restaurant wins, then home, else elsewhere")
    func kitchen() {
        let known = FoodPlace(householdId: .new(), name: "Pho Saigon House", createdAt: .now)
        let pho = PlaceDraft(name: "Pho Saigon House")
        #expect(DishFormKitchen.of(sources: MealSources([.dineOut]), place: pho, known: known) == DishFormKitchen(kitchen: .place(known.id), words: "from Pho Saigon House"))
        #expect(DishFormKitchen.of(sources: MealSources([.home, .delivery]), place: pho, known: known).kitchen == .place(known.id))
        #expect(DishFormKitchen.of(sources: MealSources([.home, .delivery]), place: nil, known: nil) == DishFormKitchen(kitchen: .home, words: "home-cooked"))
        #expect(DishFormKitchen.of(sources: MealSources([.company]), place: nil, known: nil) == DishFormKitchen(kitchen: .elsewhere, words: "from elsewhere"))
        // A restaurant new to the diary has a kitchen of its own, with nothing in it yet.
        let new = DishFormKitchen.of(sources: MealSources([.dineOut]), place: PlaceDraft(name: "Bun Bo Hue 21"), known: nil)
        #expect(new.words == "from Bun Bo Hue 21")
        #expect(new.kitchen != .elsewhere && new.kitchen != .home)
        // It agrees with where the saved meal's dishes go.
        #expect(DishKitchen.of(sources: [.home, .delivery], placeId: known.id) == .place(known.id))
        #expect(DishKitchen.of(sources: [.home, .delivery], placeId: nil) == .home)
    }
}
