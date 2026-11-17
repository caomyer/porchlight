import Foundation
import GRDB
import Testing
import UIKit
@testable import Porchlight

/// What widgets, Siri and Shortcuts do, on a test database: each logs once, through the
/// same write as one tap on Today (rule 10), stamped with this device and credited to "me".
@Suite("Widget and Siri actions")
@MainActor
struct IntentWorkTests {
    private let db: AppDatabase
    private let household: Household
    private let james: Person.ID
    private let mia: Person.ID
    private let companionId: Companion.ID
    private let walk: CareRoutine
    private let calendar: Calendar
    private let defaults: UserDefaults
    private let settings: DeviceSettings
    /// Saturday, November 7 2026 at 6:05 pm: the evening walk is open.
    private let now: Date
    private var today: DayKey { DayKey(now, calendar: calendar) }

    init() throws {
        db = try AppDatabase.inMemory()
        household = try db.createHousehold(
            name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)],
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        calendar = household.calendar
        let people = try db.snapshot().people
        james = people[0].id
        mia = people[1].id
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        companionId = try db.saveCompanion(draft, householdId: household.id)
        // New routines start today; these tests run on a fixed day before it.
        try db.writer.write { try $0.execute(sql: "UPDATE careRoutine SET anchorDay = ''") }
        walk = try #require(try db.writer.read(CompanionSnapshot.fetch).routines(of: companionId).first { $0.kind == .walk })
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 18, minute: 5))!
        defaults = UserDefaults(suiteName: "intent-work-\(UUID().uuidString)")!
        settings = DeviceSettings(defaults: defaults, idiom: .phone, model: "iPhone")
        settings.setMe(james, in: household.id)
    }

    private func walks() throws -> [CareEntry] {
        try db.writer.read(CompanionSnapshot.fetch).entries(of: walk.id)
    }

    private func answer(_ outcome: IntentWork.Outcome) -> IntentWork.Answer? {
        if case let .answer(answer) = outcome { return answer }
        return nil
    }

    // MARK: Logging one slot (the widget's button)

    @Test("The widget's button logs the slot once, for me, stamped with this device")
    func logsSlotOnce() async throws {
        let outcome = await IntentWork.logSlot(routineId: walk.id, slot: 1, day: today, database: db, settings: settings, now: now)
        let logged = try #require(answer(outcome))
        #expect(logged.wrote)
        #expect(logged.text == "Logged Yo-Yo's evening walk")
        #expect(logged.detail?.hasPrefix("For James at 6:05") == true)
        let stored = try walks()
        #expect(stored.count == 1)
        #expect(stored[0].people == [james])
        #expect(stored[0].log.deviceId == db.thisDeviceId(in: household.id))

        // A second tap, from a widget that hasn't redrawn yet: nothing is added.
        let again = try #require(answer(await IntentWork.logSlot(routineId: walk.id, slot: 1, day: today, database: db, settings: settings, now: now)))
        #expect(!again.wrote)
        #expect(again.text == "You walked Yo-Yo at 6:05pm")
        #expect(try walks().count == 1)
    }

    @Test("When someone got there first, it says who and adds nothing")
    func someoneGotThereFirst() async throws {
        let draft = CareLogDraft(people: [mia], occurredAt: now.addingTimeInterval(-25 * 60), durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        _ = try db.logCare(routineId: walk.id, draft, now: now)
        let outcome = try #require(answer(await IntentWork.logSlot(routineId: walk.id, slot: 1, day: today, database: db, settings: settings, now: now)))
        #expect(!outcome.wrote)
        #expect(outcome.text == "Mia walked Yo-Yo at 5:40pm")
        #expect(outcome.detail == "Already logged, so nothing was added.")
        #expect(try walks().count == 1)
    }

    @Test("Without me, without a household, or on a shared screen, nothing is logged")
    func refusals() async throws {
        let nobody = DeviceSettings(defaults: UserDefaults(suiteName: "intent-nobody-\(UUID().uuidString)")!, idiom: .phone, model: "iPhone")
        #expect(await IntentWork.logSlot(routineId: walk.id, slot: 1, day: today, database: db, settings: nobody, now: now) == .refused(.noMe))

        let shared = DeviceSettings(defaults: UserDefaults(suiteName: "intent-shared-\(UUID().uuidString)")!, idiom: .pad, model: "iPad")
        shared.setMe(james, in: household.id)
        #expect(await IntentWork.logSlot(routineId: walk.id, slot: 1, day: today, database: db, settings: shared, now: now) == .refused(.sharedScreen))

        let empty = try AppDatabase.inMemory()
        #expect(await IntentWork.logCare(companionId: companionId, routineId: nil, database: empty, settings: settings, now: now) == .refused(.noHousehold))
        #expect(try walks().isEmpty)

        #expect(IntentWork.Refusal.noMe.opensApp)
        #expect(IntentWork.Refusal.noHousehold.opensApp)
        #expect(!IntentWork.Refusal.sharedScreen.opensApp)
    }

    @Test("Someone removed from the household is nobody's phone")
    func removedMe() async throws {
        try db.archivePerson(id: james)
        #expect(await IntentWork.logSlot(routineId: walk.id, slot: 1, day: today, database: db, settings: settings, now: now) == .refused(.noMe))
    }

    // MARK: "I walked Yo-Yo"

    @Test("\"I walked Yo-Yo\" logs the walk a log now belongs to, once")
    func logsCareNow() async throws {
        let first = try #require(answer(await IntentWork.logCare(companionId: companionId, routineId: nil, kind: .walk, database: db, settings: settings, now: now)))
        #expect(first.wrote)
        #expect(first.text == "Logged Yo-Yo's evening walk")
        let second = try #require(answer(await IntentWork.logCare(companionId: companionId, routineId: nil, kind: .walk, database: db, settings: settings, now: now)))
        #expect(!second.wrote)
        #expect(try walks().count == 1)
    }

    @Test("A kind the companion has no routine for says so")
    func noSuchRoutine() async throws {
        let outcome = try #require(answer(await IntentWork.logCare(companionId: companionId, routineId: nil, kind: .meds, database: db, settings: settings, now: now)))
        #expect(!outcome.wrote)
        #expect(outcome.text.contains("Yo-Yo has no"))
    }

    // MARK: Chores

    @Test("A chore is checked off once, for me; someone else's check-off is said")
    func checksChore() async throws {
        let chore = try db.saveChore(
            ChoreDraft(title: "Recycling", emoji: "♻️", ownerId: nil, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 2),
            householdId: household.id
        )
        let done = try #require(answer(await IntentWork.checkChore(choreId: chore.id, day: today, database: db, settings: settings, now: now)))
        #expect(done.wrote)
        #expect(done.text == "Checked off Recycling")
        #expect(done.detail == "+2 stars for you")
        let completion = try #require(try await db.writer.read { try ChoreCompletion.fetchOne($0) })
        #expect(completion.personId == james)
        #expect(completion.deviceId == db.thisDeviceId(in: household.id))

        let again = try #require(answer(await IntentWork.checkChore(choreId: chore.id, day: today, database: db, settings: settings, now: now)))
        #expect(!again.wrote)
        #expect(again.text == "You already did Recycling at 6:05pm")
        #expect(try await db.writer.read { try ChoreCompletion.fetchCount($0) } == 1)
    }

    // MARK: Lists

    @Test("An item is added to the groceries once, by me")
    func addsItem() async throws {
        let list = try db.createList(title: "Groceries", kind: .grocery, householdId: household.id)
        let added = try #require(answer(await IntentWork.addItem("Oat milk", listId: nil, database: db, settings: settings, now: now)))
        #expect(added.wrote)
        #expect(added.text == "Added Oat milk to Groceries")
        let item = try #require(try await db.writer.read { try ListItem.fetchOne($0) })
        #expect(item.listId == list.id)
        #expect(item.addedById == james)
        #expect(item.deviceId == db.thisDeviceId(in: household.id))

        let again = try #require(answer(await IntentWork.addItem("oat milk", listId: nil, database: db, settings: settings, now: now)))
        #expect(!again.wrote)
        #expect(again.text == "Oat milk is already on Groceries.")
        #expect(try await db.writer.read { try ListItem.fetchCount($0) } == 1)
    }

    // MARK: What's next

    @Test("What's next says the open care and my chores left")
    func whatsNext() async throws {
        _ = try db.saveChore(
            ChoreDraft(title: "Dishes", emoji: nil, ownerId: james, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1),
            householdId: household.id
        )
        let next = try #require(answer(await IntentWork.whatsNext(database: db, settings: settings, now: now)))
        #expect(!next.wrote)
        #expect(next.text.contains("Yo-Yo's evening walk is open until 8pm."))
        #expect(next.text.contains("You have 1 chore left: Dishes."))

        // A shared screen answers too, about care only: it has no "me".
        let shared = DeviceSettings(defaults: UserDefaults(suiteName: "intent-shared-\(UUID().uuidString)")!, idiom: .pad, model: "iPad")
        let wall = try #require(answer(await IntentWork.whatsNext(database: db, settings: shared, now: now)))
        #expect(wall.text.contains("evening walk"))
        #expect(!wall.text.contains("chore"))
    }
}
