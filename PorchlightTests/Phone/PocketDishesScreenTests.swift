#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's dishes, hosted in the unit bundle (`HostedScreen`) with the sample diary: the
/// list, a dish's page and a restaurant's page, each in light, dark, at the largest text and
/// both together. These are the pages `PhoneDishesTests.testNightAndLargestText` launched
/// the app five times to photograph; here they are drawn and checked in seconds, and
/// `PhoneDishesTests`' journeys stay for what only the real screens show (search, the star,
/// renaming into a merge, removing with Undo).
///
/// The sample diary is built around the real day, so nothing here asserts a date or a
/// count: only what is on the page and that it fits.
@Suite("The phone's dishes, the whole pages")
@MainActor
struct PocketDishesScreenTests {
    private func page(_ kind: String, _ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "dishes")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        try FoodSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        let store = FoodStore(database: db)
        let toasts = ToastCenter()
        let photos = PhotoImages(database: db)
        let me = snapshot.people[0]
        let hosted: HostedScreen
        switch kind {
        case "dish":
            let pho = try #require(store.snapshot.dishes.first { $0.name == "Pho tai" })
            hosted = try await HostedScreen.host(
                PocketDishDetail(dishId: pho.id).environment(store).environment(photos).environment(toasts).environment(\.me, me), look: look
            )
        case "place":
            let saigon = try #require(store.snapshot.places.first { $0.name == "Pho Saigon House" })
            hosted = try await HostedScreen.host(PocketPlaceDetail(placeId: saigon.id).environment(store).environment(photos).environment(\.me, me), look: look)
        default:
            hosted = try await HostedScreen.host(
                ScrollView { PocketDishesView().padding(.horizontal, 16) }.background(Theme.background).environment(store).environment(photos).environment(\.me, me),
                look: look
            )
        }
        try hosted.saveShot("dishes-\(kind)-\(look.name)")
        return hosted
    }

    @Test(
        "The list, a dish and a restaurant each fit across the screen and say what they are about, in each look",
        arguments: ["list", "dish", "place"], ["light", "dark", "largest", "largest-dark"]
    )
    func fits(kind: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await page(kind, look)
        #expect(page.elements.count >= 6, "the page was read (\(kind), \(look)):\n\(page.listing)")
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(kind), \(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        for element in page.elements {
            #expect(element.frame.width > 0 && element.frame.height > 0, "\(element.label.prefix(40)) has a size (\(kind), \(look))")
        }
        switch kind {
        case "dish":
            #expect(page.elements.contains { $0.label.hasPrefix("Pho tai") }, "the dish's name:\n\(page.listing)")
            #expect(page.elements.contains { $0.label.localizedCaseInsensitiveContains("How we like it") }, "how we like it:\n\(page.listing)")
            #expect(page.elements.contains { $0.isButton && $0.label.contains("Pho Saigon House") }, "where it is from, to open:\n\(page.listing)")
        case "place":
            #expect(page.elements.contains { $0.label.hasPrefix("Pho Saigon House") }, "the restaurant's name:\n\(page.listing)")
            #expect(page.elements.contains { $0.isButton && $0.label.contains("Pho tai") }, "what we had there:\n\(page.listing)")
        default:
            #expect(page.elements.contains { $0.isButton && $0.label.contains("Pho tai") }, "a dish's row:\n\(page.listing)")
            #expect(page.elements.contains { $0.label.contains("Pho Saigon House") }, "its restaurant:\n\(page.listing)")
        }
    }
}
#endif
