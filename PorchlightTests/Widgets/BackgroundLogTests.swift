import Foundation
import GRDB
import Testing
@testable import Porchlight

/// A log from a widget's button, Siri or a reminder's action, as a background launch does
/// it (journey C3, the M4 gate): no window, no stores on screen, just the launch's
/// database, the widgets' keeper and sync, through `IntentRunner`.
@Suite("A log from a background launch")
@MainActor
struct BackgroundLogTests {
    /// The household of `SyncHarness.fill`, everything in iCloud, plus a cat whose feed
    /// nobody has logged, and this phone's person as James.
    private func ready() async throws -> (SyncHarness, SyncController, routine: CareRoutine, settings: DeviceSettings, james: Person.ID) {
        let harness = try SyncHarness()
        // The engine first, as at launch: it records every write from the moment it exists.
        let controller = await harness.controller()
        try harness.fill()
        let household = try #require(try harness.database.snapshot().household)
        var miso = CompanionDraft.new(species: .cat)
        miso.name = "Miso"
        let misoId = try harness.database.saveCompanion(miso, householdId: household.id)
        let routine = try #require(try await harness.database.writer.read { db in
            try CareRoutine.filter(Column("companionId") == misoId).fetchOne(db)
        })
        try await #require(controller.engine).syncChanges()
        #expect(try harness.unsynced() == [], "everything starts in iCloud")
        let james = try #require(try harness.database.snapshot().people.first { $0.name == "James" }).id
        let settings = DeviceSettings(defaults: harness.defaults, idiom: .phone, model: "iPhone")
        settings.setRole(.personal)
        settings.setMe(james, in: household.id)
        return (harness, controller, routine, settings, james)
    }

    @Test("A widget's log is written, credited, in the widgets' summary and sent to iCloud, with no window open")
    func widgetLog() async throws {
        let (harness, controller, routine, settings, james) = try await ready()
        let summaryFile = harness.folder.appendingPathComponent("widget-summary.json")
        let keeper = WidgetSummaryKeeper(
            database: harness.database, companions: CompanionStore(database: harness.database), home: HomeStore(database: harness.database),
            device: settings, file: summaryFile, didWrite: { _ in }
        )
        var retries: [SyncController.SendOutcome] = []
        let launch = IntentLaunch(database: harness.database, settings: settings, keeper: keeper, sync: controller) { retries.append($0) }
        let household = try #require(try harness.database.snapshot().household)
        let today = DayKey(CompanionClock.now(), calendar: household.calendar)

        let outcome = await IntentRunner.logSlot(routineId: routine.id.description, slot: 0, day: today.rawValue, in: launch)
        #expect(outcome?.wrote == true, "\(String(describing: outcome))")

        let logs = try await harness.database.writer.read(CompanionSnapshot.fetch).entries(of: routine.id)
        #expect(logs.count == 1)
        #expect(logs.first?.people == [james], "credited to this phone's person")

        let summary = try #require(WidgetSummaryFile.read(from: summaryFile))
        let slots = summary.companions.first { $0.name == "Miso" }?.routines.flatMap(\.slots) ?? []
        #expect(slots.contains { $0.day == today.rawValue && $0.index == 0 && $0.isDone }, "the widgets show it done")

        #expect(try harness.unsynced() == [], "and it reached iCloud before the intent returned")
        #expect(retries == [.sent], "so nothing is tried again")
    }

    @Test("A send that runs out of time says so, and the log waits in the engine for the retry")
    func outOfTime() async throws {
        let (harness, controller, routine, settings, _) = try await ready()
        let household = try #require(try harness.database.snapshot().household)
        let today = DayKey(CompanionClock.now(), calendar: household.calendar)
        _ = await IntentWork.logSlot(routineId: routine.id, slot: 0, day: today, database: harness.database, settings: settings, now: CompanionClock.now())
        // A slow network: the launch's account check takes longer than the send may wait.
        await harness.device.answer(after: .seconds(3))
        controller.refresh()
        #expect(await controller.sendSoon(timeout: .milliseconds(300)) == .waiting, "out of time, it says so, and a retry is asked for")
        // The log is pending in the engine, which may still send it on its own while the
        // process lives; either way nothing is lost, and the next try confirms it.

        await harness.device.answer(after: .zero)
        controller.refresh()
        #expect(await controller.sendSoon() == .sent, "the next try sends it")
        #expect(try harness.unsynced() == [])
    }

    @Test("Signed out, sync has nothing to try again: it sends by itself once signed back in")
    func signedOut() async throws {
        let (harness, controller, _, _, _) = try await ready()
        await harness.device.signOut()
        controller.refresh()
        #expect(await controller.sendSoon() == .off)
    }

    @Test("Retries wait longer each time, stop after the last, and start over after a send")
    func retryBackoff() {
        let defaults = UserDefaults(suiteName: "retry-\(UUID().uuidString)")!
        var asked: [TimeInterval] = []
        for _ in 0..<6 { SyncSendRetry.after(.waiting, defaults: defaults) { asked.append($0) } }
        #expect(asked == SyncSendRetry.waits, "one ask per wait, then no more")
        SyncSendRetry.after(.sent, defaults: defaults) { asked.append($0) }
        SyncSendRetry.after(.waiting, defaults: defaults) { asked.append($0) }
        #expect(asked.last == SyncSendRetry.waits.first, "a send that got everything up starts over")
    }
}
