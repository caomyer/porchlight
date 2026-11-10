#if DEBUG
import SwiftUI
import UIKit

/// `-debugInjectMealPhoto`: in a sample launch, saves a generated photo as today's lunch
/// through the path the capture sheet uses (`savePhoto`, then `addMeal`), so photo
/// storage, thumbnails and polaroids can be checked on a device without the camera.
enum FoodDebugPhoto {
    @MainActor
    static func injectIfRequested(into store: FoodStore) async {
        guard AppFiles.isSandboxed, UserDefaults.standard.bool(forKey: "debugInjectMealPhoto") else { return }
        // Wait for the store to load the sample journal.
        for _ in 0..<40 where store.journal == nil { try? await Task.sleep(for: .milliseconds(250)) }
        let now = Date.now
        let draft = MealDraft(
            day: store.today(now),
            slot: "Lunch",
            source: .home,
            title: "Test photo",
            eaterIds: store.people.compactMap(\.id),
            eatenAt: now
        )
        guard let photo = try? await store.savePhoto(image()) else { return }
        do { _ = try store.addMeal(draft, photos: [photo]) } catch { store.discard([photo]) }
    }

    /// A 1600 x 1200 "photo": warm tablecloth, a plate and a bowl.
    private static func image() -> UIImage {
        let size = CGSize(width: 1600, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1).cgColor, UIColor(red: 0.98, green: 0.80, blue: 0.55, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.white.setFill()
            cg.fillEllipse(in: CGRect(x: 400, y: 200, width: 800, height: 800))
            UIColor(red: 0.95, green: 0.62, blue: 0.20, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 560, y: 360, width: 480, height: 480))
            UIColor(red: 0.35, green: 0.62, blue: 0.40, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 700, y: 480, width: 120, height: 120))
        }
    }
}
#endif
