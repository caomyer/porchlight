# Sync foundation: the M0 data design

This is the technical design for milestone M0 of the phone companion (see `docs/proposals/companion-ux.html`, "Delivery plan").
M0 reshapes the local database so it can sync through iCloud later.
iCloud stays off in M0, and nothing changes on screen.

## Why the data has to change

Sync will be built on Point-Free's SQLiteData, which syncs SQLite tables to CloudKit and shares them between iCloud users.
It only accepts tables that follow these rules, so M0 makes every table follow them:

1. Every table has one primary key, and it is a globally unique id (a UUID stored as text), never an auto-increment integer.
2. No `UNIQUE` constraints other than the primary key.
3. A table is shared with other people only if it has exactly one foreign key, pointing at its parent, in a chain that ends at the shared root (the household).
   A table with two foreign keys is silently left out of the share.
4. Foreign keys may only use `ON DELETE CASCADE`, `SET NULL` or `SET DEFAULT`.
5. Columns are never renamed or removed once sync is on, and new columns must be nullable or have a default.

The app keeps using GRDB records for all of its own reads and writes.
SQLiteData is not added to the app in M0.
In M1 it is added next to GRDB, with a small set of mirror types that describe each table to the sync engine.

## Ids

### The `ID` type

All ids become `ID<Entity>`, a small generic struct that wraps a `UUID`.

```swift
struct ID<Entity>: Hashable, Sendable, Codable, DatabaseValueConvertible, CustomStringConvertible, Comparable
```

- It is stored as lowercase UUID text, for example `3f2b8c1e-...`, which is what SQLiteData and CloudKit record names expect.
- `ID.new()` makes a random one.
- `ID.derived(_ parts: String...)` makes a deterministic one: the SHA-256 of the parts joined with `|`, folded into a UUID.
  The same inputs give the same id on every device.
- It decodes from text only.
  A record's `id` is no longer optional and is set when the value is created, so `didInsert` and `id!` go away.
- The phantom `Entity` parameter stops a person id being passed where a chore id is expected.
  Records get a typealias, for example `Person.ID`.

Using a dedicated type rather than a bare `UUID` matters because GRDB stores a bare `UUID` as a 16-byte blob when it is passed as a query argument.
That would never match the text ids in the tables, and the query would quietly return nothing.

A `uuid()` SQL function is registered on every connection so the column default in the schema works.
SQLiteData registers the same function in M1.

### Derived ids replace unique constraints

Where the old schema said "one row per X and Y", the row's id is now derived from X and Y.
Two devices that write the same thing offline produce the same id, so the rows merge instead of duplicating.

| Table | Id is derived from |
|---|---|
| `choreCompletion` | chore id, day |
| `journalPage` | journal id, day |
| `mealPlan` | household id, day |
| `careLogPerson` | care log id, person id |
| `journalEntryEater` | entry id, person id |
| `rewardRedemption` | reward id, the reward's `startDay` when cashed in (one cash-in per cycle) |

Writes to these tables use an upsert on the primary key.

## The tree

Every synced table hangs off the household through exactly one foreign key.

```
household
├─ person
├─ companion ─ careRoutine ─ careLog ─ careLogPerson
├─ journal ─┬─ journalEntry ─┬─ journalEntryEater
│           │                └─ journalEntryPhoto
│           └─ journalPage
├─ foodPlace
├─ chore ─ choreCompletion
├─ reward ─ rewardRedemption
├─ homeList ─ listItem
└─ mealPlan
```

All of these foreign keys use `ON DELETE CASCADE`.

### References across the tree are plain ids

These columns stay, but lose their `REFERENCES` clause, because a second foreign key would drop the table from the share:

- `careLogPerson.personId`, `journalEntryEater.personId`
- `chore.ownerId`, `choreCompletion.personId`
- `reward.ownerId`, `rewardRedemption.personId`
- `listItem.addedById`
- `journalEntry.placeId`

The app resolves them itself and must cope with an id that points at nothing: show no avatar or name, never crash.
A sync can deliver a row before the row it refers to.

### People and places are archived, never deleted

Since the database no longer cascades from a person, and history should keep its names, removing a person archives them.

- `person` gains `archivedAt` (nullable date).
- "Remove" in the people editor archives.
  In one transaction it also sets `ownerId` to null on that person's chores (they become "Anyone"), archives rewards they own, and clears them as a calendar's owner.
  Past logs, meals, completions and cash-ins keep pointing at them.
- Stores expose active people for pickers and lists, and all people (including archived) for showing who did something in the past.
- The last active person still cannot be removed.
- `foodPlace` rows are likewise never deleted while any entry refers to them.

Companions, chores, rewards, lists, meals and logs can still be deleted, and the cascade follows the single parent chain.

## Tables that stay on the device

`calendarSource` and `ambientPhoto` are device-local and will not sync.
Their ids and references still move to `ID`, but they keep their unique constraints.
Calendar ids differ per device, so the shared "this calendar is Mia's" mapping is a later, separate table (M3).

## Table definitions

All synced tables are created as `STRICT` tables with this id column:

```sql
"id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
```

Column types become the STRICT ones: dates and day keys are `TEXT` (GRDB's `YYYY-MM-DD HH:MM:SS.SSS` format, which SQLiteData also uses), booleans are `INTEGER`, JSON is `TEXT`.
Every other column, default and check constraint is kept exactly as it is today.
Indexes are recreated, except the ones that only existed to back a dropped unique constraint.

## Ordering

Several queries order by `id` to mean "oldest first" or to break ties.
A random id has no order, so each of those becomes `createdAt` (or the table's natural date) with `id` only as a final tie-break for stability.

## The migration

One new migration, registered after all existing ones: `"sync v1: sync-ready ids"`.

1. For each table with integer ids, build a temporary map from the old integer to a fresh random UUID.
   Random, not derived from the integer: two households that each migrated from an old install must never share an id.
2. For each table, parents before children: create `new_<table>` with the final definition, copy every row across while translating its id and references through the maps, drop the old table and rename.
   Tables whose id is derived compute it from their already-translated parent ids, in Swift.
3. Recreate indexes.
4. Run `PRAGMA foreign_key_check` and fail the migration if it reports anything.

GRDB runs each migration in a transaction with foreign key enforcement deferred, so a failure leaves the database untouched.

Photo files are named independently of row ids, so no file is renamed.

### Existing migrations must not use app models

`"companions v3"` reads the household through the `Household` record type.
Once `Household.id` is an `ID`, that would fail to decode the integer id of a database that has not reached the new migration yet.
It is rewritten to read raw rows, with the same behavior.
The rule from now on: migrations use raw SQL and rows only, never record types.

### Safety on the wall

- Before migrating a database on disk, the app copies `porchlight.sqlite` (after a WAL checkpoint) to `porchlight-before-sync-v1.sqlite` next to it.
  It is removed in a later milestone once M1 has passed its gate.
- `scripts/backup-ipad.sh` copies the wall's data to the Mac before every install.

## Tests

- **Migration, row by row.** Build a database with the old schema through the old migrations, fill every table (including nulls, join rows, archived and odd cases), migrate, and check that every row survives with the same values and that every reference still points at the same row.
- **Migration on real data.** A test that runs only when `PORCHLIGHT_REAL_DB` points at a copy of the wall's database: it migrates the copy and compares row counts and a checksum of every non-id column per table, before and after.
- **Schema rules.** A test reads `sqlite_master` and `PRAGMA foreign_key_list` and fails if any synced table has an integer primary key, a unique index, more than one foreign key, a foreign key action other than cascade, or is missing from the tree above.
  This keeps later changes honest.
- **Derived ids.** Same inputs give the same id; writing the same completion twice leaves one row.
- **Archiving.** Removing a person keeps their history and frees their chores.
- All existing unit and UI tests pass.

## Not in M0

- Photo and thumbnail data stay as files.
  They move into their own synced tables in M1, when there is something to sync them to.
  Until sync is on, schema changes are still free.
- The current household is still "the only one".
  Choosing between several arrives with joining (M2) and switching (M5).
- The bundle id and shared container move is its own step, described separately once S1 (widgets reaching the database) is settled.
