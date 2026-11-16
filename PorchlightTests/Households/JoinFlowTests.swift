import Foundation
import GRDB
import Testing
import UIKit
@testable import Porchlight

/// Joining from an invite with the fake sharing (journey A4): the preview, accepting,
/// picking a person, "I'm new here", an account the household already knows, and a join
/// that fails and is tried again.
@Suite("Joining a household")
@MainActor
struct JoinFlowTests {
    private let db: AppDatabase
    private let defaults: UserDefaults
    private let invitation = HouseholdInvitation(householdId: nil, householdName: "The Lake House", ownerName: "James")

    init() throws {
        db = try AppDatabase.inMemory(installId: "mias-phone")
        let suite = "porchlight.join.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    /// The owner's household, as it arrives when the invite is accepted: James and Mia, and
    /// James's phone. `miasOldPhone` puts a phone of this iCloud user's in it too.
    private func sharing(miasOldPhone: Bool = false, failures: Int = 0) -> FakeHouseholdSharing {
        let fake = FakeHouseholdSharing(userName: "_mia") { [db] _ in
            let household = try db.createHousehold(
                name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
            )
            try db.markSetupCompleted(householdId: household.id)
            let people = try db.snapshot().people
            let james = try AppDatabase(db.writer, installId: "james-phone")
            try james.saveThisDevice(ThisDevice(name: "James's iPhone", role: .personal, model: "iPhone", personId: people[0].id, userName: "_james"), in: household.id)
            if miasOldPhone {
                let old = try AppDatabase(db.writer, installId: "mias-old-phone")
                try old.saveThisDevice(ThisDevice(name: "Mia's old iPhone", role: .personal, model: "iPhone", personId: people[1].id, userName: "_mia"), in: household.id)
            }
        }
        fake.acceptFailures = failures
        return fake
    }

    /// What this device remembers about itself (`deviceState`).
    private func stored(_ key: String) throws -> String? {
        try db.writer.read { try DeviceState.value(key, $0) }
    }

    private func flow(_ sharing: FakeHouseholdSharing, idiom: UIUserInterfaceIdiom = .phone) -> (JoinFlow, DeviceSettings) {
        let device = DeviceSettings(defaults: defaults, idiom: idiom, model: idiom == .pad ? "iPad" : "iPhone")
        return (JoinFlow(invitation: invitation, database: db, sharing: sharing, device: device, arrivalTimeout: .seconds(2)), device)
    }

    @Test("Nothing is accepted until Join; then the household arrives, becomes current, and asks who you are")
    func joinThenWho() async throws {
        let fake = sharing()
        let (flow, device) = flow(fake)
        #expect(flow.step == .preview)
        #expect(fake.calls.isEmpty)
        #expect(try db.snapshot().household == nil)

        await flow.join()
        let household = try #require(try db.snapshot().household)
        #expect(fake.calls == ["accept"])
        #expect(flow.step == .who(household.id))
        #expect(try stored(DeviceState.Key.currentHouseholdId.rawValue) == household.id.description)
        #expect(try stored(DeviceState.ownerKey(household.id)) == "James")

        let mia = try #require(try db.snapshot().people.first { $0.name == "Mia" })
        flow.pick(mia.id)
        #expect(flow.step == .bringingIn(household.id))
        #expect(device.me(in: household.id) == mia.id)
    }

    @Test("\"I'm new here\" adds a person and continues as them")
    func newHere() async throws {
        let (flow, device) = flow(sharing())
        await flow.join()
        try flow.addMe(PersonDraft(name: "Ava", color: .ochre))
        let snapshot = try db.snapshot()
        let ava = try #require(snapshot.people.first { $0.name == "Ava" })
        #expect(flow.step == .bringingIn(try #require(snapshot.household).id))
        #expect(device.me(in: ava.householdId) == ava.id)
    }

    @Test("An iCloud user who already has a phone in the household keeps the same person")
    func knownAccount() async throws {
        let (flow, device) = flow(sharing(miasOldPhone: true))
        await flow.join()
        let snapshot = try db.snapshot()
        let household = try #require(snapshot.household)
        #expect(flow.step == .bringingIn(household.id), "Which one is you? is skipped")
        #expect(device.me(in: household.id) == snapshot.people.first { $0.name == "Mia" }?.id)
    }

    @Test("A shared screen never asks who it is")
    func sharedScreen() async throws {
        let (flow, device) = flow(sharing(), idiom: .pad)
        await flow.join()
        let household = try #require(try db.snapshot().household)
        #expect(flow.step == .bringingIn(household.id))
        #expect(device.me(in: household.id) == nil)
    }

    @Test("A join that fails offline leaves nothing half joined, and trying again works")
    func failsThenRetries() async throws {
        let fake = sharing(failures: 1)
        let (flow, _) = flow(fake)
        await flow.join()
        #expect(flow.step == .preview)
        #expect(flow.failure?.contains("online") == true)
        #expect(try db.snapshot().household == nil)
        #expect(try stored(DeviceState.Key.currentHouseholdId.rawValue) == nil)

        await flow.join()
        #expect(fake.calls == ["accept", "accept"])
        #expect(flow.failure == nil)
        if case .who = flow.step {} else { Issue.record("The second try should join, got \(flow.step)") }
    }

    @Test("An invite that is accepted but whose household never arrives can be tried again")
    func neverArrives() async throws {
        let fake = FakeHouseholdSharing(userName: "_mia")
        let named = HouseholdInvitation(householdId: .new(), householdName: "The Lake House", ownerName: "James")
        let device = DeviceSettings(defaults: defaults, idiom: .phone, model: "iPhone")
        let flow = JoinFlow(invitation: named, database: db, sharing: fake, device: device, arrivalTimeout: .milliseconds(200))
        await flow.join()
        #expect(flow.step == .preview)
        #expect(flow.failure?.contains("hasn't arrived") == true)
    }
}
