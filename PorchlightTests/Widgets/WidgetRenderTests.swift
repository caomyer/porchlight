import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// Every widget family drawn from summaries, in each look a widget can be seen in (light,
/// dark, the largest text, redacted on a locked phone, stale, no household). Widgets can't
/// be driven by UI tests, so these renders are how they are reviewed: with
/// `TEST_RUNNER_PORCHLIGHT_WIDGET_SHOTS=<folder>` each one is written there as a PNG.
@Suite("Widget renders")
@MainActor
struct WidgetRenderTests {
    enum Family: String, CaseIterable {
        case companionSmall, todayMedium, groceriesSmall, companionCircular, glowRectangular, choresCircular

        /// iPhone 15 sizes, in points.
        var size: CGSize {
            switch self {
            case .companionSmall, .groceriesSmall: CGSize(width: 158, height: 158)
            case .todayMedium: CGSize(width: 338, height: 158)
            case .companionCircular, .choresCircular: CGSize(width: 72, height: 72)
            case .glowRectangular: CGSize(width: 160, height: 72)
            }
        }

        var isLockScreen: Bool { [.companionCircular, .glowRectangular, .choresCircular].contains(self) }

        @ViewBuilder
        func view(_ moment: WidgetMoment, timeZone: TimeZone) -> some View {
            switch self {
            case .companionSmall: CompanionSmallView(moment: moment, timeZone: timeZone)
            case .todayMedium: TodayMediumView(moment: moment, timeZone: timeZone)
            case .groceriesSmall: GroceriesSmallView(moment: moment)
            case .companionCircular: CompanionCircularView(moment: moment)
            case .glowRectangular: GlowRectangularView(moment: moment)
            case .choresCircular: ChoresCircularView(moment: moment)
            }
        }
    }

    enum Look: String, CaseIterable {
        case light, dark, largestText, redacted, stale, noHousehold, notSetUp, sharedScreen, morning
    }

    private let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour, minute: minute))!
    }

    private func moment(_ look: Look) -> WidgetMoment {
        let summary = WidgetPreviewData.summary(at: at(18, 5), timeZone: timeZone)
        switch look {
        case .stale: return .at(at(23, 40).addingTimeInterval(0), summary: summary.written(at: at(17, 10)))
        case .noHousehold: return .at(at(18, 5), summary: WidgetSummary(writtenAt: at(18, 5)))
        case .notSetUp: return .at(at(18, 5), summary: nil)
        case .sharedScreen: return .at(at(18, 5), summary: WidgetSummary(writtenAt: at(18, 5), isSharedScreen: true))
        case .morning: return .at(at(12), summary: summary)
        default: return .at(at(18, 5), summary: summary)
        }
    }

    private func framed(_ family: Family, _ look: Look) -> some View {
        let content = family.view(moment(look), timeZone: timeZone)
            .frame(width: family.size.width - (family.isLockScreen ? 0 : 32), height: family.size.height - (family.isLockScreen ? 0 : 32))
        let tile = Group {
            if family.isLockScreen {
                content
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
            } else {
                content
                    .padding(16)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        return tile
            .padding(20)
            .background(
                family.isLockScreen
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x1D2B44), Color(hex: 0x3B2F4A)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x8FB3C9), Color(hex: 0xC9A98F)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .environment(\.colorScheme, look == .dark ? .dark : .light)
            .environment(\.dynamicTypeSize, look == .largestText ? .accessibility5 : .large)
            .redacted(reason: look == .redacted ? .privacy : [])
    }

    @Test("Every family renders in every look")
    func rendersEverything() throws {
        let folder = ProcessInfo.processInfo.environment["PORCHLIGHT_WIDGET_SHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let folder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for family in Family.allCases {
            for look in Look.allCases {
                let renderer = ImageRenderer(content: framed(family, look))
                renderer.scale = 3
                let image = try #require(renderer.uiImage, "\(family) \(look)")
                #expect(image.size.width >= family.size.width)
                if let folder, let png = image.pngData() {
                    try png.write(to: folder.appendingPathComponent("\(family.rawValue)-\(look.rawValue).png"))
                }
            }
        }
    }
}
