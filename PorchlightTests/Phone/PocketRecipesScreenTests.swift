#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's recipes, hosted in the unit bundle (`HostedScreen`) with the sample diary and
/// its recipes: the bank, an empty bank, a recipe's page, and a home dish's page with and
/// without its recipe, in light, dark, at the largest
/// text and both together. `PhoneRecipesTests` keeps the journeys only the real app shows
/// (adding one to a dish we cook, cooking from the bank, planning a dinner, ingredients to
/// the grocery list).
///
/// The sample is built around the real day, so nothing here asserts a date or a count.
@Suite("The phone's recipes, the whole pages")
@MainActor
struct PocketRecipesScreenTests {
    static let longName = "Grandma Lin's slow-braised pork belly with mustard greens"

    private func page(_ kind: String, _ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "recipes")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        try FoodSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        if kind == "empty" {
            try await db.writer.write { try $0.execute(sql: "DELETE FROM recipePhoto; DELETE FROM recipe") }
        }
        if kind == "bank" {
            // A name and a line as long as they come, to wrap beside the picture.
            _ = try db.saveRecipe(
                RecipeDraft(name: Self.longName, ingredients: ["1 lb pork belly"], link: "example.com/pork-belly"),
                householdId: household.id, addedBy: nil
            )
        }
        let store = FoodStore(database: db)
        let home = HomeStore(database: db)
        let me = snapshot.people[0]
        let screen: AnyView
        if kind == "dish" || kind == "dish-none" {
            let name = kind == "dish" ? "Chicken curry" : "Oatmeal"
            let dish = try #require(store.book.liveDishes.first { $0.name == name })
            screen = AnyView(PocketDishDetail(dishId: dish.id))
        } else if kind == "page" {
            let curry = try #require(store.book.liveDishes.first { $0.name == "Chicken curry" })
            screen = AnyView(PocketRecipePage(dishId: curry.id, onCook: { _ in }, onPlan: { _ in }, onEdit: { _ in }))
        } else {
            screen = AnyView(ScrollView { PocketRecipesView(onAdd: { _ in }, onPlan: { _ in }).padding(.horizontal, 16) }.background(Theme.background))
        }
        let hosted = try await HostedScreen.host(
            NavigationStack { screen.navigationBarTitleDisplayMode(.inline) }
                .environment(store).environment(home).environment(ToastCenter()).environment(PhotoImages(database: db)).environment(\.me, me),
            look: look
        )
        try hosted.saveShot("recipes-\(kind)-\(look.name)")
        return hosted
    }

    @Test(
        "The bank, an empty bank, a recipe's page and a home dish's way to its recipe fit across the screen and say what they are, in each look",
        arguments: ["bank", "empty", "page", "dish", "dish-none"], ["light", "dark", "largest", "largest-dark"]
    )
    func fits(kind: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await page(kind, look)
        #expect(page.elements.count >= 4, "the page was read (\(kind), \(look)):\n\(page.listing)")
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(kind), \(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        for element in page.elements {
            #expect(element.frame.width > 0 && element.frame.height > 0, "\(element.label.prefix(40)) has a size (\(kind), \(look))")
        }
        switch kind {
        case "bank":
            let curry = try #require(page.elements.first { $0.isButton && $0.label.hasPrefix("Chicken curry") }, "the curry's row:\n\(page.listing)")
            #expect(curry.label.contains("Mia's"), "whose it is: \(curry.label)")
            #expect(page.elements.contains { $0.isButton && $0.label.hasPrefix("Grandma Lin's dumplings") }, "a recipe not cooked yet is in the bank")
            #expect(page.elements.contains { $0.isButton && $0.label.contains("New recipe") }, "a way to add one:\n\(page.listing)")
            // One row layout for the whole list: the words beside the picture, wrapping, at
            // the standard sizes; below it at the accessibility sizes, for every row.
            let names = ["Chicken curry", "Pesto pasta", "Miso salmon", "Grandma Lin's dumplings", Self.longName]
            let expected: HostedRowLayout.Layout = look.textSize.isAccessibilityCategory ? .below : .beside
            let picture: CGFloat = look.textSize.isAccessibilityCategory ? 52 * 1.4 : 52
            for name in names {
                let row = try #require(page.elements.first { $0.isButton && $0.label.hasPrefix(name + ",") }, "\(name)'s row:\n\(page.listing)")
                #expect(HostedRowLayout.layout(of: row.frame, picture: picture, in: page) == expected, "\(name)'s words are \(expected) its picture (\(look))")
            }
        case "empty":
            #expect(page.element(beginningWith: "📖") != nil || page.elements.contains { $0.label.contains("Keep the recipes you actually cook") }, "why it is empty:\n\(page.listing)")
            #expect(page.elements.contains { $0.isButton && $0.label.contains("Add a recipe") }, "the way to start:\n\(page.listing)")
        case "dish":
            let link = try #require(page.elements.first { $0.isButton && $0.label.contains("The recipe") }, "the way to its recipe:\n\(page.listing)")
            #expect(link.frame.height >= 44, "a whole target: \(link.frame)")
        case "dish-none":
            let add = try #require(page.elements.first { $0.isButton && $0.label.contains("Add a recipe") }, "the way to add one:\n\(page.listing)")
            #expect(add.frame.height >= 44, "a whole target: \(add.frame)")
        default:
            #expect(page.elements.contains { $0.label == "Chicken curry" }, "the title:\n\(page.listing)")
            let cook = try #require(page.elements.first { $0.isButton && $0.label.contains("We made this") }, "We made this:\n\(page.listing)")
            #expect(cook.frame.height >= 44, "a whole target: \(cook.frame)")
            #expect(page.elements.contains { $0.label.contains("2 lb chicken thighs") }, "the ingredients:\n\(page.listing)")
            #expect(page.elements.contains { $0.label.contains("Brown the chicken") }, "the steps")
        }
    }
}
#endif
