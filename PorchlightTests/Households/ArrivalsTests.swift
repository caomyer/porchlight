import Foundation
import GRDB
import Testing
@testable import Porchlight

/// What the wall says when rows arrive from people's phones (journey D1), and the phone's
/// sync banner (journey E5).
@Suite("Arrivals and sync banners")
@MainActor
struct ArrivalsTests {
    private let db: AppDatabase
    private let household: Household
    private let james: Person
    private let mia: Person
    private let jamesPhone: AppDatabase
    private let miaPhone: AppDatabase
    private let kitchen: AppDatabase
    private let groceries: HomeList

    init() throws {
        db = try AppDatabase.inMemory(installId: "wall")
        household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        let people = try db.snapshot().people
        (james, mia) = (people[0], people[1])
        jamesPhone = try AppDatabase(db.writer, installId: "james")
        miaPhone = try AppDatabase(db.writer, installId: "mia")
        kitchen = try AppDatabase(db.writer, installId: "kitchen")
        try jamesPhone.saveThisDevice(ThisDevice(name: "James's iPhone", role: .personal, model: "iPhone", personId: james.id, userName: "_james"), in: household.id)
        try miaPhone.saveThisDevice(ThisDevice(name: "Mia's iPhone", role: .personal, model: "iPhone", personId: mia.id, userName: "_mia"), in: household.id)
        try kitchen.saveThisDevice(ThisDevice(name: "Kitchen iPad", role: .sharedScreen, model: "iPad", personId: nil, userName: "_james"), in: household.id)
        groceries = try db.createList(title: "Groceries", kind: .grocery, householdId: household.id)
    }

    private func rows() throws -> [ArrivedRow] {
        try db.writer.read { try ArrivedRow.fetch($0, excluding: db.thisDeviceId(in: household.id), since: .now.addingTimeInterval(-3600)) }
    }

    @Test("What was there at launch only sets the baseline; a new row from a phone glows and names who")
    func oneArrival() throws {
        let arrivals = WallArrivals()
        _ = try miaPhone.addListItem(title: "Basil", to: groceries.id, addedBy: mia.id)
        arrivals.update(try rows(), snapshot: try db.snapshot())
        #expect(arrivals.toast == nil && arrivals.fresh.isEmpty)

        var yoyo = CompanionDraft.new(species: .dog)
        yoyo.name = "Yo-Yo"
        let companionId = try db.saveCompanion(yoyo, householdId: household.id)
        let walk = try #require(try db.writer.read(CompanionSnapshot.fetch).routines(of: companionId).first { $0.kind == .walk })
        let log = try jamesPhone.logCare(routineId: walk.id, CareLogDraft(people: [james.id], occurredAt: .now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil))
        arrivals.update(try rows(), snapshot: try db.snapshot())
        #expect(arrivals.toast?.text == "James walked Yo-Yo · from their phone")
        #expect(arrivals.toast?.person?.id == james.id)
        #expect(arrivals.fresh == [log.id.description])
    }

    @Test("A burst after being offline gives one toast that sums it up")
    func burst() throws {
        let arrivals = WallArrivals()
        arrivals.update(try rows(), snapshot: try db.snapshot())
        _ = try miaPhone.addListItem(title: "Basil", to: groceries.id, addedBy: mia.id, now: .now.addingTimeInterval(-30))
        _ = try miaPhone.addListItem(title: "Limes", to: groceries.id, addedBy: mia.id, now: .now.addingTimeInterval(-20))
        _ = try jamesPhone.addListItem(title: "Rice", to: groceries.id, addedBy: james.id, now: .now.addingTimeInterval(-10))
        arrivals.update(try rows(), snapshot: try db.snapshot())
        #expect(arrivals.toast?.text == "3 updates from James's and Mia's phones", "newest first")
        #expect(arrivals.toast?.person == nil)
        #expect(arrivals.fresh.count == 3)
    }

    @Test("Rows from this wall, another shared screen, or while resting say nothing")
    func quiet() throws {
        let arrivals = WallArrivals()
        arrivals.update(try rows(), snapshot: try db.snapshot())
        _ = try db.addListItem(title: "Basil", to: groceries.id, addedBy: mia.id)
        _ = try kitchen.addListItem(title: "Limes", to: groceries.id, addedBy: mia.id)
        arrivals.update(try rows(), snapshot: try db.snapshot())
        #expect(arrivals.toast == nil && arrivals.fresh.isEmpty)

        arrivals.isResting = true
        _ = try miaPhone.addListItem(title: "Rice", to: groceries.id, addedBy: mia.id)
        arrivals.update(try rows(), snapshot: try db.snapshot())
        #expect(arrivals.toast == nil, "the photo frame stays calm")
        arrivals.isResting = false
        arrivals.update(try rows(), snapshot: try db.snapshot())
        #expect(arrivals.toast == nil, "and what arrived meanwhile isn't announced later")
    }

    @Test("Each kind of row reads as a sentence")
    func sentences() {
        func row(_ kind: ArrivedRow.Kind, _ subject: String, detail: String? = nil, title: String? = nil) -> ArrivedRow {
            ArrivedRow(kind: kind, rowId: "1", deviceId: .new(), subject: subject, detail: detail, title: title)
        }
        #expect(row(.care, "Yo-Yo", detail: "feed", title: "Dinner").sentence(who: "Mia") == "Mia fed Yo-Yo")
        #expect(row(.meal, "Pho", detail: "Lunch").sentence(who: "Mia") == "Mia added lunch: Pho")
        #expect(row(.chore, "Fix the leaky faucet").sentence(who: "James") == "James did Fix the leaky faucet")
        #expect(row(.reward, "Pizza night").sentence(who: "Ava") == "Ava cashed in Pizza night")
        #expect(row(.list, "Basil", detail: "Groceries").sentence(who: "Mia") == "Mia added Basil to Groceries")
    }

    // MARK: The phone's banner

    @Test("One banner, most urgent first; offline only once stuck an hour")
    func banners() {
        func pick(_ status: SyncStatus, stuck: Bool = false, owner: String? = "James") -> PocketSyncNotice? {
            PocketSyncNotice.pick(status, stuckLong: stuck, householdName: "The Lake House", ownerName: owner, device: "iPhone")
        }
        #expect(pick(.upToDate(lastSynced: .now)) == nil)
        #expect(pick(.syncing) == nil)
        #expect(pick(.off(.switchedOff)) == nil)
        #expect(pick(.waiting(lastSynced: .now)) == nil, "a short wait says nothing")
        #expect(pick(.waiting(lastSynced: nil), stuck: true)?.title == "Offline")
        #expect(pick(.iCloudFull)?.title == "Sync paused: James's iCloud is full")
        #expect(pick(.iCloudFull, owner: nil)?.title == "Sync paused: your iCloud is full")
        let signedOut = pick(.account(.signedOut))
        #expect(signedOut?.title == "iCloud is off for Porchlight" && signedOut?.fix == .openSettings)
        #expect(signedOut?.detail == "Sign in to iCloud, or turn it on for Porchlight, in Settings. The Lake House stays on this iPhone meanwhile.")
        let restricted = pick(.account(.restricted))
        #expect(restricted?.title == "iCloud isn't allowed on this iPhone" && restricted?.fix == .openSettings)
        #expect(restricted?.detail == "Screen Time, or whoever manages this iPhone, has turned it off. The Lake House stays here but can't sync.")
        let signIn = pick(.account(.needsSignIn))
        #expect(signIn?.title == "iCloud needs you to sign in again" && signIn?.fix == .openSettings)
        #expect(pick(.account(.couldNotCheck)) == nil, "not knowing says nothing at first")
        #expect(pick(.account(.couldNotCheck), stuck: true)?.title == "Can't check iCloud")
        #expect(pick(.account(.couldNotCheck), stuck: true)?.fix == nil, "and has nothing to fix in Settings")
        #expect(pick(.needsDecision(.restoredCopy))?.fix == .openYou)
    }
}
