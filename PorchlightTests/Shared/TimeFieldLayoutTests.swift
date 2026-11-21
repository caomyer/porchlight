import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The time pill and its row, laid out in a hosting controller and measured: no app launch,
/// no simulator screen, every Dynamic Type size in milliseconds. This is the working example
/// of a layout fact checked in the unit bundle (docs/design/testing.md, "The middle options").
///
/// The facts are the ones `PhoneTabsTests.testFixingAWalkLooks` checks on the real sheet at
/// the largest size: the pill grows with the text, sits under "Started" instead of
/// squeezing or covering it, and never runs off the screen. Here they hold at every size.
/// The UI test keeps one look at the real sheet, where the row sits among everything else.
@Suite("The time pill's layout")
@MainActor
struct TimeFieldLayoutTests {
    /// An iPhone 15's sheet, inside its 16 point margins.
    private let width: CGFloat = 393 - 2 * 16
    private let clock = ClockStyle(uses24Hours: false)
    private let tenPastSeven = 7 * 60 + 10

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    /// The size a view takes in the sheet's width at a text size, in a phone's compact width.
    private func size(of view: some View, at type: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(
            rootView: view
                .environment(\.dynamicTypeSize, type)
                .environment(\.horizontalSizeClass, .compact)
        )
        return host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    }

    private var pill: some View {
        TimeFieldPill(minute: tenPastSeven, clock: clock, accessibilityLabel: "Started", identifier: "exact-time") {}
    }

    /// The care sheet's label, in its own type.
    private var label: some View {
        Text("Started").phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
    }

    /// The row as the care sheet builds it: the label, then the time.
    private var row: some View {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        let now = midnight.addingTimeInterval(17 * 3600 + 20 * 60)
        return LogTimeField(
            time: .constant(.at(midnight.addingTimeInterval(Double(tenPastSeven) * 60))), range: midnight...now, now: now,
            accessibilityLabel: "Started", identifier: "exact-time", calendar: calendar, clock: clock
        ) { label }
    }

    @Test("The pill grows with the text, and is taller than 60 points at the largest size")
    func pillGrows() {
        let usual = size(of: pill, at: .large)
        let largest = size(of: pill, at: .accessibility5)
        #expect(usual.height < 60, "\(usual)")
        #expect(largest.height > 60, "\(largest)")
        #expect(largest.width > usual.width)
    }

    @Test("Beside its label where both fit, under it where they don't, and never wider than the sheet", arguments: DynamicTypeSize.allCases)
    func rowFits(type: DynamicTypeSize) {
        let pill = size(of: pill, at: type)
        let label = size(of: label, at: type)
        let row = size(of: row, at: type)
        #expect(pill.width <= width, "the pill is whole on screen at \(type): \(pill)")
        #expect(row.width <= width, "the row is whole on screen at \(type): \(row)")
        // Measured sizes are rounded up to whole points, so heights are compared within two.
        let beside = abs(row.height - max(label.height, pill.height)) < 2
        // Stacked: the label, 8 points, then the pill, so neither covers the other.
        let stacked = abs(row.height - (label.height + 8 + pill.height)) < 2
        #expect(beside || stacked, "one layout or the other at \(type): \(row) for \(label) and \(pill)")
        if label.width + 8 + pill.width > width + 2 {
            #expect(stacked, "too wide to sit beside the label at \(type), so under it: \(row) for \(label) and \(pill)")
        }
    }

    @Test("At the usual size the time sits beside its label; at the largest it goes under it")
    func whichLayout() {
        #expect(size(of: row, at: .large).height < size(of: label, at: .large).height + size(of: pill, at: .large).height)
        #expect(size(of: row, at: .accessibility5).height > size(of: label, at: .accessibility5).height + size(of: pill, at: .accessibility5).height)
    }
}
