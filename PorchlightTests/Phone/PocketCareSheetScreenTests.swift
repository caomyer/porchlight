#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's care sheet, whole, hosted in the unit bundle (`HostedScreen`): a new walk, a
/// logged walk opened to fix, and a slot being caught up on, each in light, dark, at the
/// largest text and both together.
///
/// These are the looks the UI suite used to launch the app for
/// (`PhoneCatchUpTests.testCatchingUpLooks`, and two of the three launches of
/// `PhoneTabsTests.testFixingAWalkLooks`): nothing off either side, the time pill under
/// "Started" instead of over it at the largest size, the save button whole, and the page
/// drawn for review. What only the real sheet can show stays a UI test: that Save can be
/// reached and tapped at the largest size (`testFixingAWalkLooks`), and that the sheet
/// opens, saves and closes (`PhoneCatchUpTests`, `PhoneTabsTests`).
///
/// With `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder>` each sheet in each look is written
/// there as a PNG. The sample is built around the real "now", so nothing here asserts a
/// time or a day's name: only what is on the sheet and where it sits.
@Suite("The phone's care sheet, the whole sheet")
@MainActor
struct PocketCareSheetScreenTests {
    private func sheet(_ kind: String, _ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "sheet")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        try CompanionSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        let model = AppModel(database: db)
        let store = CompanionStore(database: db)
        let toasts = ToastCenter()
        let me = snapshot.people[0]
        let companion = try #require(store.companions.first)
        let report = try #require(store.report(for: companion.id))
        let walk = try #require(report.routines.first { $0.kind == .walk })
        let request: PocketCareSheet.Request
        switch kind {
        case "fix":
            request = .edit(try #require(store.snapshot.entries(of: walk.id).last), companionId: companion.id)
        case "catchUp":
            request = PocketCareSheet.Request(
                companionId: companion.id, routineId: walk.id, people: [me.id],
                catchUp: CareLogRequest.CatchUp(day: report.today, slot: 0)
            )
        default:
            request = PocketCareSheet.Request(companionId: companion.id, routineId: walk.id, people: [me.id])
        }
        let screen = PocketCareSheet(
            request: request, logging: PocketLogging(companions: store, home: HomeStore(database: db), toasts: toasts, me: me.id)
        )
        .environment(model)
        .environment(store)
        .environment(toasts)
        .environment(\.me, me)
        let hosted = try await HostedScreen.host(screen, look: look)
        if let folder = ProcessInfo.processInfo.environment["PORCHLIGHT_SCREEN_SHOTS"].map({ URL(fileURLWithPath: $0, isDirectory: true) }) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try hosted.image.pngData()?.write(to: folder.appendingPathComponent("care-sheet-\(kind)-\(look.name).png"))
        }
        return hosted
    }

    @Test(
        "Nothing runs off either side, the time is clear of its label, and Save is whole, for each sheet in each look",
        arguments: ["new", "fix", "catchUp"], ["light", "dark", "largest", "largest-dark"]
    )
    func fits(kind: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let sheet = try await sheet(kind, look)
        let width = HostedScreen.size.width
        #expect(sheet.elements.count >= 8, "the sheet was read:\n\(sheet.listing)")
        for element in sheet.elements {
            #expect(element.frame.minX >= 0 && element.frame.maxX <= width, "\(element.label.prefix(40)) is whole across the sheet (\(kind), \(look)): \(element.frame)")
        }

        // The pill is a button called "Started"; its label is the text beside or above it.
        let pill = try #require(sheet.elements.first { $0.isButton && $0.label.hasPrefix("Started") }, "the time pill:\n\(sheet.listing)")
        let label = try #require(sheet.elements.first { !$0.isButton && $0.label.hasPrefix("Started") }, "the pill's label:\n\(sheet.listing)")
        #expect(!pill.frame.intersects(label.frame), "the pill never covers \"Started\" (\(kind), \(look)): \(pill.frame), \(label.frame)")
        if look.textSize.isAccessibilityCategory {
            #expect(pill.frame.height > 60, "the pill grows with the text: \(pill.frame)")
            #expect(pill.frame.minY >= label.frame.maxY, "and goes under its label: \(pill.frame), \(label.frame)")
        } else {
            #expect(pill.frame.minX >= label.frame.maxX, "beside its label at the usual size: \(pill.frame), \(label.frame)")
        }

        let save = try #require(
            sheet.elements.first { $0.isButton && ($0.label.hasPrefix("Log walk") || $0.label == "Save changes") }, "the save button:\n\(sheet.listing)"
        )
        #expect(save.frame.width > width / 2, "Save is a full button, not squeezed: \(save.frame)")
        #expect(save.frame.minY >= pill.frame.maxY, "under the fields")
        switch kind {
        case "fix":
            #expect(sheet.element(beginningWith: "Edit walk") != nil, "the fix sheet's title:\n\(sheet.listing)")
            #expect(sheet.elements.contains { $0.isButton && $0.label.hasPrefix("Remove") }, "a fix can remove the log")
        case "catchUp":
            #expect(sheet.elements.contains { $0.label.contains("For today's morning walk") }, "it says which slot it is for:\n\(sheet.listing)")
        default:
            #expect(sheet.elements.contains { $0.label.contains("Log a walk") }, "the new log's title:\n\(sheet.listing)")
        }
    }
}
#endif
