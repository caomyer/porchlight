import CloudKit
import Foundation
import Testing
@testable import Porchlight

/// Checks that ask iCloud first, and restart the engine when its fetch brings nothing iCloud
/// said was there (docs/design/sync-icloud.md, "When fetching brings nothing"). SQLiteData's
/// stand-in for iCloud has nothing new to bring, which is exactly the wall's case: iCloud
/// (the probe) says a zone changed, the engine's fetch applies nothing.
@Suite("Checks that ask iCloud first")
@MainActor
struct SyncProbeTests {
    private func probe(private changed: Int, error: String? = nil, baseline: Bool = false) -> SyncProbe {
        SyncProbe(databases: [
            .init(scope: "private", changedZones: changed, error: error, isBaseline: baseline),
            .init(scope: "shared", changedZones: 0, error: error, isBaseline: baseline),
        ])
    }

    @Test("Nothing changed in iCloud: the check is answered and nothing else is asked")
    func nothingNew() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        await harness.device.willProbe([probe(private: 0)])
        await controller.checkNow(.timer)
        #expect(controller.trace.lastCheck?.outcome == "answered")
        #expect(controller.trace.received == "nothing new (timer)")
        #expect(controller.trace.restarts == 0)
        #expect(controller.trace.lastProbe == "private 0 zones changed, shared 0 zones changed")
    }

    @Test("The first probe of a launch is only a baseline")
    func baseline() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        await harness.device.willProbe([probe(private: 3, baseline: true)])
        await controller.checkNow(.timer)
        #expect(controller.trace.restarts == 0)
        #expect(controller.trace.lastProbe == "private baseline, shared baseline")
    }

    @Test("iCloud has changes the engine's fetch doesn't bring: the engine restarts, and nothing pending is lost")
    func restartsWhenFetchBringsNothing() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try harness.fill()
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])
        // A row added here just before, still to send.
        let household = try #require(try harness.database.snapshot().household)
        _ = try harness.database.createList(title: "Hardware", kind: .todo, householdId: household.id)
        #expect(try harness.unsynced().contains { $0.hasPrefix("homeList ") })
        await harness.device.willProbe([probe(private: 1)])
        await controller.checkNow(.timer)
        #expect(controller.trace.restarts == 1)
        #expect(engine.isRunning)
        #expect(controller.trace.lastCheck?.outcome == "answered")
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [], "the change made before the restart still went up")
    }

    @Test("A probe that fails in both databases is a failed check; one failing database alone isn't")
    func probeFailures() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        await harness.device.willProbe([probe(private: 0, error: "CKError 4")])
        await controller.checkNow(.timer)
        #expect(controller.trace.lastCheck?.outcome == "failed")

        await harness.device.willProbe([SyncProbe(databases: [
            .init(scope: "private", changedZones: 0, error: nil, isBaseline: false),
            .init(scope: "shared", changedZones: 0, error: "CKError 4", isBaseline: false),
        ])])
        await controller.checkNow(.timer)
        #expect(controller.trace.lastCheck?.outcome == "answered", "an owner's shared database failing never blocks the private one")
        #expect(controller.trace.lastProbe == "private 0 zones changed, shared CKError 4")
    }

    @Test("A push fetches even when the probe saw nothing yet")
    func pushFetchesAnyway() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        await harness.device.willProbe([probe(private: 0)])
        await controller.checkNow(.push)
        #expect(controller.trace.lastCheck?.outcome == "answered")
        #expect(controller.trace.lastTrigger == "push")
        #expect(controller.trace.restarts == 0)
    }
}
