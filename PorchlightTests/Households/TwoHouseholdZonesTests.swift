import Foundation
import GRDB
import SQLiteData
import Testing
@testable import Porchlight

/// Where rows of each household go in iCloud: ours to our zone, the joined household's to
/// its owner's, with SQLiteData's stand-in for iCloud.
@Suite("Two households: zones")
@MainActor
struct TwoHouseholdZonesTests {
    @Test("A row written into the joined household goes to its zone, and one into ours to ours")
    func writesLandInTheirZone() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        let lake = try harness.database.createHousehold(name: "The Lake House", people: [PersonDraft(name: "James", color: .blue)])
        let rosas = try harness.database.createHousehold(name: "Grandma Rosa's", people: [PersonDraft(name: "Rosa", color: .plum)])
        try await engine.syncChanges()
        // As if Grandma Rosa's came through a share: its rows live in Rosa's zone.
        try await harness.database.writer.write { db in
            try db.execute(sql: """
                UPDATE sqlitedata_icloud_metadata SET zoneName = 'rosas-household', ownerName = '_rosa'
                WHERE recordType = 'household' AND recordPrimaryKey = ?
                """, arguments: [rosas.id.description])
        }
        let rosaPeople: [Person] = try await harness.database.writer.read { db in try Person.active(in: rosas.id).fetchAll(db) }
        let rosa = rosaPeople[0]
        let theirs = try harness.database.saveChore(
            ChoreDraft(title: "Water the tomatoes", emoji: nil, ownerId: rosa.id, recurrence: .daily, anchorDay: DayKey(.now, calendar: rosas.calendar), timeHint: nil, stars: 1),
            householdId: rosas.id
        )
        let ours = try harness.database.saveChore(
            ChoreDraft(title: "Dishes", emoji: nil, ownerId: nil, recurrence: .daily, anchorDay: DayKey(.now, calendar: lake.calendar), timeHint: nil, stars: 1),
            householdId: lake.id
        )
        let rows: [[String]] = try await harness.database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT recordPrimaryKey, zoneName, ownerName FROM sqlitedata_icloud_metadata WHERE recordType = 'chore'")
                .map { [$0["recordPrimaryKey"], $0["zoneName"], $0["ownerName"]] }
        }
        var zones: [String: (String, String)] = [:]
        for row in rows { zones[row[0]] = (row[1], row[2]) }
        #expect(zones[theirs.id.description]?.0 == "rosas-household")
        #expect(zones[theirs.id.description]?.1 == "_rosa")
        #expect(zones[ours.id.description]?.0 == SyncMirror.householdZone.zoneID.zoneName)
    }
}
