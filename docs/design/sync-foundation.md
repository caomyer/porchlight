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
- The database stays in the app's own container.
  Widgets will read a small summary the app writes for them (M4), so no shared container is needed.

## The bundle id

The bundle id, and the iCloud container named after it, can never change once data syncs.

- The app started as `com.mingyucao.porchlight`.
- At M0 it moved to `com.porchlight.porchlight`, meant to be permanent.
  Cable installs were signed with a wildcard profile, which hid that the id had never been registered to the team.
- On 2026-11-16 registering it explicitly, which iCloud and push need, failed: Apple reported the id as not available.
  The app went back to `com.mingyucao.porchlight`, with the container `iCloud.com.mingyucao.porchlight`, before any data had synced.

To an iPad a new bundle id is a new app with an empty container, so the wall's household moves by backup and restore, from the Mac:

1. `scripts/backup-ipad.sh --bundle com.porchlight.porchlight` copies the running app's data.
2. `scripts/deploy-ipad.sh --no-backup` installs the app under its id.
3. With the new app closed, `scripts/restore-ipad.sh <backup>` puts the data into its container.
4. The new app opens and runs any migrations it hasn't yet.

The old app stays installed, untouched, until the new one has been checked.
Settings kept in the app's preferences (UserDefaults), rather than in the data folder, don't move with it.

## Implementation notes

Choices made while building M0, where the design above left room or did not fit the code.

### Ids

- `ID` stores a `UUID` and writes it as lowercase text; it reads either case, but every id written is lowercase.
- `ID.derived` folds the SHA-256 by XOR-ing its two halves, then marks the result as a version 8 (custom) UUID.
- Fixed inputs therefore give a fixed id forever: changing `derived` once sync is on would split rows that should merge.
- `uuid()` is registered through `AppDatabase.configuration` on every connection, and the migration registers it again, so it never depends on how its connection was opened.
- Records are now plain `PersistableRecord`s: with the id set at creation, nothing is written back after an insert.

### Cash-ins are named by the cash-in before them

The design derives `rewardRedemption`'s id from the reward and its `startDay` at cash-in.
That does not fit how cash-ins work: a reward can be cashed in more than once on the same day (stars earned after a cash-in count toward the next round, split by `redeemedAt`), so the second and third cash-ins of a day would share an id, and the upsert would quietly replace a real cash-in.
Instead the id is derived from the reward and the id of the cash-in before it (`"first"` for the first one).
That is exactly what "one round" means: two devices that cash in the same round offline both saw the same previous cash-in, so they write the same row, while every later round gets a new one.
It is also the token the board already passed to guard against double taps (`after:`), so `cashInReward` still refuses a second cash-in of the same round.
The migration builds the same chain from the old rows, in the order they were written.
"The latest cash-in" is now the newest by `redeemedAt`, not the highest id.

### The migration

- Map tables exist only for tables whose ids are referenced or random; tables with derived ids compute them in Swift from their translated parents, as the design says.
- Every copied reference goes through its map with a subquery, so a reference to a missing row becomes NULL, which a `NOT NULL` column refuses: an orphan fails the migration instead of vanishing.
- Every old index is recreated except the autoindexes behind dropped unique constraints; the parent columns of the old composite keys already had their own indexes.
- `calendarSource` and `ambientPhoto` are device-local but are rebuilt the same way (STRICT, the same id column), keeping their unique constraints and, for `calendarSource`, its second foreign key to `person`.
- `sqlite_sequence` stays, as SQLite does not allow dropping it; nothing uses it any more.
- "companions v3" now reads the household's time zone and first weekday from a raw row and builds the calendar with `Calendar.household(timeZoneIdentifier:firstWeekday:)`, the same function `Household.calendar` uses.
- Older migrations stay exactly as they were otherwise, so fresh installs still build the old schema and then rebuild it; a test checks that fresh and upgraded databases end with identical schemas.

### The safety copy

- The copy is made only when `porchlight.sqlite` already exists and has applied at least one migration but not "sync v1".
- A copy left by an earlier launch whose migration failed is replaced, since the database it came from is still unmigrated.

### People

- `HouseholdSnapshot`, `CompanionSnapshot`, `FoodSnapshot` and `HomeSnapshot` have `people` (active, for pickers, columns and lists) and `everyone` (archived included, for naming who did something).
- Lookups for past things (`AppModel.person`, `OwnerAvatar`, care log names, meal eaters, chore credit on Today) use `everyone`; an id that points at nobody gives no name and the household's heart avatar.
- New credit, chore and reward owners, and "added by" must be active people; editing an old meal or walk keeps any archived person already on it.
- Archived people keep their `sortOrder`; the active ones are renumbered, and a new person goes after them.
- Completions whose person was deleted before this change keep their `NULL` person.
- `foodPlace` has no delete path in the app (only the household cascade), so nothing needed to change there.

### Ordering

- The household is the oldest by `createdAt`; `careRoutine` has no creation time, so routines order by `sortOrder`, then `id`, which only keeps ties stable.
- Captions are picked by a seed taken from the log's id, so existing logs get new (still stable) captions once.

### Debug launches

- `-startScreen companion-N` now opens the N-th companion on the rail, since ids are no longer small numbers; `companion-1` works as before.
