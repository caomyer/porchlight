#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The chore and reward editors as the phone shows them (`PhoneEditorSheet`), hosted in the
/// unit bundle (`HostedScreen`) in the light and the night look: a chosen chip is a dark tint
/// at night, with light words on it, and the light look's pale wash by day. In build
/// 20261125.034137 the chosen chips were near white at night (`Color.wash` mixed in the light
/// look unless told otherwise).
///
/// Hosted, the look is the window's own, so this holds wherever the unit tests run; the UI
/// suite's night look comes from the simulator's appearance, which the hosted CI runners
/// don't change (`PhoneNightEditorsTests`).
@Suite("The phone's chore and reward editors, the chosen chips in each look")
@MainActor
struct PocketEditorsScreenTests {
    private func editor(_ kind: String, _ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "editors")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        let seeded = try #require(snapshot.household)
        try HomeSamples.seed(db, household: seeded, people: snapshot.people)
        let model = AppModel(database: db)
        let home = HomeStore(database: db)
        let screen: AnyView = switch kind {
        case "reward":
            AnyView(PhoneEditorSheet { RewardEditor(reward: home.snapshot.rewards.first) })
        default:
            AnyView(PhoneEditorSheet { ChoreEditor(chore: home.snapshot.chores.first { $0.title == "Make breakfast" }) })
        }
        let hosted = try await HostedScreen.host(screen.background(Theme.surface).environment(model).environment(home), look: look)
        try hosted.saveShot("editor-\(kind)-\(look.name)")
        return hosted
    }

    /// How light the picture is just inside an element's trailing edge, 0 black to 1 white.
    private func lightness(_ hosted: HostedScreen, inside element: HostedScreen.Element) throws -> Double {
        let cg = try #require(hosted.image.cgImage)
        let scale = CGFloat(cg.width) / hosted.image.size.width
        let point = CGPoint(x: (element.frame.maxX - 8) * scale, y: element.frame.midY * scale)
        let pixel = try #require(cg.cropping(to: CGRect(x: point.x.rounded(), y: point.y.rounded(), width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (0.2126 * Double(bytes[0]) + 0.7152 * Double(bytes[1]) + 0.0722 * Double(bytes[2])) / 255
    }

    @Test("A chosen chip is a dark tint at night and the pale wash by day", arguments: ["chore", "reward"], ["light", "dark"])
    func chosenChips(kind: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let hosted = try await editor(kind, look)
        // James is chosen on both; the chore repeats every day.
        let chosen = ["James"] + (kind == "chore" ? ["Every day"] : [])
        for title in chosen {
            let chip = try #require(hosted.elements.first { $0.isButton && $0.label.hasPrefix(title) }, "\(title):\n\(hosted.listing)")
            let value = try lightness(hosted, inside: chip)
            if look.style == .dark {
                #expect(value < 0.4, "\(kind), \(title), at night: \(value)")
            } else {
                #expect(value > 0.75, "\(kind), \(title), by day: \(value)")
            }
        }
    }
}
#endif
