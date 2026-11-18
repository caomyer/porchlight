import Foundation
import Testing
@testable import Porchlight

/// What the photo row does, the same on the wall and the phone (`MealPhotoOrder`).
@Suite("The photo row")
struct MealPhotoOrderTests {
    private func photo() -> NewMealPhoto {
        NewMealPhoto(id: .new(), image: Data([1]), thumbnail: Data([2]), crop: nil)
    }

    @Test("Make cover moves one photo to the front and keeps the others in order")
    func makeCover() {
        let (a, b, c) = (photo(), photo(), photo())
        let items: [MealPhotoItem] = [.added(a), .added(b), .added(c)]
        #expect(MealPhotoOrder.makeCover(2, in: items).map(\.id) == [c.id, a.id, b.id])
        #expect(MealPhotoOrder.makeCover(0, in: items) == items, "the cover is already the cover")
        #expect(MealPhotoOrder.makeCover(5, in: items) == items, "a photo that is gone changes nothing")
    }

    @Test("Removing the cover makes the next photo the cover")
    func remove() {
        let (a, b) = (photo(), photo())
        let items: [MealPhotoItem] = [.added(a), .added(b)]
        #expect(MealPhotoOrder.remove(0, from: items).map(\.id) == [b.id])
        #expect(MealPhotoOrder.remove(3, from: items) == items)
    }

    @Test("A reframe lands on its photo, unless the row changed under it")
    func reframe() {
        let (a, b) = (photo(), photo())
        let items: [MealPhotoItem] = [.added(a), .added(b)]
        let crop = PhotoCrop.centeredSquare(in: CGSize(width: 400, height: 300))
        let framed = MealPhotoOrder.reframe(b.id, at: 1, in: items, crop: crop, thumbnail: Data([9]))
        #expect(framed[1].crop == crop)
        #expect(framed[0] == items[0])
        if case let .added(new) = framed[1] { #expect(new.thumbnail == Data([9]), "with the thumbnail made for the new square") }
        // The photo moved (made cover, or another taken off) while the reframe was open.
        #expect(MealPhotoOrder.reframe(b.id, at: 0, in: items, crop: crop, thumbnail: Data([9])) == items)
    }

    @Test("The row's words")
    func words() {
        #expect(MealPhotoOrder.hint(count: 1) == "Tap the photo to reframe it")
        #expect(MealPhotoOrder.hint(count: 3) == "Tap a photo to make it the cover or reframe it")
        #expect(MealPhotoOrder.heading(count: 2) == "Photos · 2 of \(AppDatabase.photoLimit)")
    }
}
