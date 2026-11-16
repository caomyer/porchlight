import Foundation
import SQLiteData
import Testing
@testable import Porchlight

@Suite("Sync mirrors")
struct SyncMirrorTests {
    /// Every mirror, as the engine is given them in `SyncMirror.engine`.
    static let mirrors: [any PrimaryKeyedTable.Type] = [
        SyncMirror.Household.self, SyncMirror.Person.self,
        SyncMirror.Companion.self, SyncMirror.CareRoutine.self, SyncMirror.CareLog.self, SyncMirror.CareLogPerson.self,
        SyncMirror.Journal.self, SyncMirror.FoodPlace.self, SyncMirror.JournalEntry.self,
        SyncMirror.JournalEntryEater.self, SyncMirror.JournalEntryPhoto.self, SyncMirror.JournalPage.self,
        SyncMirror.Chore.self, SyncMirror.ChoreCompletion.self, SyncMirror.Reward.self, SyncMirror.RewardRedemption.self,
        SyncMirror.HomeList.self, SyncMirror.ListItem.self, SyncMirror.MealPlan.self,
    ]

    /// The SQLite column each plain Swift type stands for, and whether it may be NULL.
    private static let columnTypes: [ObjectIdentifier: String] = [
        ObjectIdentifier(UUID.self): "TEXT NOT NULL", ObjectIdentifier(UUID?.self): "TEXT",
        ObjectIdentifier(String.self): "TEXT NOT NULL", ObjectIdentifier(String?.self): "TEXT",
        ObjectIdentifier(Date.self): "TEXT NOT NULL", ObjectIdentifier(Date?.self): "TEXT",
        ObjectIdentifier(Int.self): "INTEGER NOT NULL", ObjectIdentifier(Int?.self): "INTEGER",
        ObjectIdentifier(Bool.self): "INTEGER NOT NULL", ObjectIdentifier(Bool?.self): "INTEGER",
        ObjectIdentifier(Double.self): "REAL NOT NULL", ObjectIdentifier(Double?.self): "REAL",
        ObjectIdentifier(Data.self): "BLOB NOT NULL", ObjectIdentifier(Data?.self): "BLOB",
    ]

    @Test("There is one mirror per synced table, and none for device-only tables")
    func oneMirrorPerSyncedTable() {
        let synced = SyncSchema.tables.filter(\.synced).map(\.name)
        #expect(Self.mirrors.map { $0.tableName } == synced)
    }

    @Test("Every mirror has its table's columns, types and nullability, and nothing else")
    func mirrorsMatchTables() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            for mirror in Self.mirrors {
                let table = try Set(db.columns(in: mirror.tableName).map { column in
                    "\(column.name) \(column.type)\(column.isNotNull ? " NOT NULL" : "")"
                })
                #expect(table == Self.columns(of: mirror), "\(mirror.tableName)")
            }
        }
    }

    @Test("Every mirror reads the rows the app writes")
    @MainActor
    func mirrorsDecodeAppRows() throws {
        let harness = try SyncHarness()
        try harness.fill()
        let counts = try harness.counts()
        let decoded = try harness.database.writer.read { db in
            try Self.mirrors.map { mirror in (mirror.tableName, try Self.decodedCount(mirror, db)) }
        }
        for (table, count) in decoded {
            #expect(count == counts[table], "\(table)")
        }
    }

    private static func columns(of mirror: any PrimaryKeyedTable.Type) -> Set<String> {
        func open<T: PrimaryKeyedTable>(_: T.Type) -> Set<String> {
            Set(T.TableColumns.allColumns.map { column in
                "\(column.name) \(columnTypes[valueType(column)] ?? "unsupported \(valueType(column))")"
            })
        }
        return open(mirror)
    }

    private static func valueType<Column: TableColumnExpression>(_: Column) -> ObjectIdentifier {
        ObjectIdentifier(Column.Value.self)
    }

    private static func decodedCount(_ mirror: any PrimaryKeyedTable.Type, _ db: Database) throws -> Int {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws -> Int {
            try T.all.fetchAll(db).count
        }
        return try open(mirror)
    }
}
