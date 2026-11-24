#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The time card as it comes up (`TimeCardPresentation`), hosted in the unit bundle
/// (`HostedScreen`): on a phone, laid out as its own sheet, on the smallest phone and on an
/// iPhone 15, in light, dark and at the largest text; on the wall, as its popover. Each
/// with suggestions and without, on a 12-hour and a 24-hour clock.
///
/// The phone's sheet doesn't depend on where the pill sits, so there is no top, middle or
/// bottom to try here: what matters is that the card is whole across the screen, every
/// key and Done is there, and it fits the screen's height, or else scrolls in its sheet.
/// That the sheet opens over the care sheet with every key in reach, and that a key types,
/// is `PhoneWeekTests.testTheTimeCardIsWhole`.
///
/// With `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder>` each card is written there as a PNG.
@Suite("The time card, whole")
@MainActor
struct TimeCardScreenTests {
    private static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Delete", "Done"]

    private struct Card: View {
        let clock: ClockStyle
        let suggests: Bool
        let fillsWidth: Bool
        @State private var typing = TimeTyping()

        var body: some View {
            let suggestions = suggests ? ["Just got back", "30 min ago", "1 hr ago", "2 hr ago"].map { title in
                TimeSuggestion(title: title, detail: title.hasSuffix("ago") ? clock.text(16 * 60 + 20) : nil, isSelected: title.hasPrefix("Just")) { nil }
            } : []
            VStack(spacing: 0) {
                TimeKeypadCard(
                    minute: 16 * 60 + 50, clock: clock, suggestions: suggestions, note: nil, typing: $typing,
                    title: fillsWidth ? "Started" : nil, fillsWidth: fillsWidth,
                    onChange: { _ in }, onSuggestion: { _ in }, onClose: {}
                )
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Theme.background)
        }
    }

    @Test(
        "On a phone the card is whole across the screen, has every key and Done, and fits the screen's height",
        arguments: ["smallest", "iPhone 15"], ["light", "dark", "largest", "largest-dark"]
    )
    func phone(phone: String, lookName: String) async throws {
        let size = phone == "smallest" ? HostedScreen.smallest : HostedScreen.size
        let look = HostedScreen.Look.named(lookName)
        for (clockName, clock) in [("12h", ClockStyle(uses24Hours: false)), ("24h", ClockStyle(uses24Hours: true))] {
            for suggests in [true, false] {
                let card = try await HostedScreen.host(Card(clock: clock, suggests: suggests, fillsWidth: true), look: look, size: size)
                let name = "time-card-\(phone == "smallest" ? "smallest" : "iphone15")-\(lookName)-\(clockName)\(suggests ? "" : "-bare")"
                try card.saveShot(name)
                for key in Self.keys {
                    let element = try #require(card.elements.first { $0.label == key }, "\(key) is on the card (\(name)):\n\(card.listing)")
                    #expect(element.frame.minX >= 0 && element.frame.maxX <= size.width, "\(key) is whole across the screen (\(name)): \(element.frame)")
                }
                // The sheet is as tall as the card, under the status bar; taller, it scrolls.
                let bottom = card.elements.map(\.frame.maxY).max() ?? 0
                #expect(bottom <= size.height - 54, "the card fits the screen (\(name)): \(bottom) of \(size.height)")
                if suggests {
                    let chip = try #require(card.element(beginningWith: "Just got back"))
                    let hour = try #require(card.element(beginningWith: "Hour"))
                    #expect(chip.frame.maxY < hour.frame.minY, "the suggestions sit whole above the time (\(name))")
                }
            }
        }
    }

    @Test("On the wall the card keeps its popover width, whole, with every key and Done", arguments: ["light", "dark"])
    func wall(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let card = try await HostedScreen.host(Card(clock: ClockStyle(uses24Hours: false), suggests: true, fillsWidth: false), look: look)
        try card.saveShot("time-card-wall-\(lookName)")
        let one = try #require(card.elements.first { $0.label == "1" }, "\(card.listing)")
        let three = try #require(card.elements.first { $0.label == "3" })
        #expect(three.frame.maxX - one.frame.minX < 272, "the popover's own width, not the screen's")
        for key in Self.keys {
            #expect(card.elements.contains { $0.label == key }, "\(key) is on the card:\n\(card.listing)")
        }
    }
}
#endif
