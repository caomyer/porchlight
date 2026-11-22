# iCloud sync: the M1 design

This is the technical design for milestone M1 of the phone companion (see `docs/proposals/companion-ux.html`, "Delivery plan").
M1 turns iCloud sync on for the household, on the wall only.
It builds on the M0 data shape in `sync-foundation.md`.

## What was proven first

A scratch project ran the app's kind of writes (plain GRDB SQL, GRDB's date format, lowercase UUID text ids) against SQLiteData 1.13.0 and its stand-in for iCloud.

- SQLiteData 1.13.0 builds with the Xcode on this Mac (26.6) for iOS 17.
  No Xcode upgrade is needed.
- Writes made through GRDB are picked up by the sync engine and sent.
  The engine watches the tables with triggers, so it does not matter who writes.
- A mirror type per table, with plain column types, reads what GRDB wrote.
- A plain id column that points across the tree (like `chore.ownerId`) syncs as ordinary data.
- A device-only table with a unique constraint can sit in the same database, as long as it is not handed to the engine.
- Sharing the household row produces a share.

## Shape

```
App code ── GRDB records ──▶ SQLite ◀── triggers ── SyncEngine ──▶ CloudKit
                               ▲                        │
                               └── mirror types describe each synced table
```

- The app keeps reading and writing through its GRDB records and stores.
  Nothing in the features knows about sync.
- `Porchlight/Sync/SyncMirrors.swift` holds one `@Table` mirror type per synced table (`SyncSchema` is the M0 table definitions).
  Mirrors use only plain column types: `UUID`, `String`, `Int`, `Double`, `Bool`, `Date`, `Data`, and their optionals.
  Enums and JSON columns are `String` in the mirror, so a value written by a newer app version never fails to decode on an older one.
- A test compares every mirror with `PRAGMA table_info` of its table, both ways, so a column added to one and not the other fails the build.
- `SyncController` (one per app) owns the `SyncEngine`, starts and stops it, and publishes a small `SyncStatus` for the UI.

## Turning it on

- Entitlements: iCloud with CloudKit and the container `iCloud.com.mingyucao.porchlight`, push notifications, and the remote-notification background mode.
  The container is named after the bundle id; `sync-foundation.md`, "The bundle id", says how that id came back to `com.mingyucao.porchlight` before anything synced.
  `CKSharingSupported` is set in Info.plist now, so M2 needs no further project change to share.
- The engine is created after migrations, with `startImmediately: false`.
  It starts when the device's sync switch is on and an iCloud account is available.
- The switch lives in Settings and is stored on the device.
  It defaults to on for new installs.
  On the wall's first M1 launch it is off until the owner turns it on, so the first upload is a deliberate act and the M1 gate can watch it.
- When the engine first starts on a database that already has rows, it uploads all of them.

### One iCloud for cable installs and TestFlight

CloudKit keeps a Development and a Production side, and they never see each other's data.
A build installed by cable normally uses Development, and a TestFlight build always uses Production.
The Release configuration sets `com.apple.developer.icloud-container-environment` to `Production`, so a Release build installed by cable and a TestFlight build meet in the same place.
Since November 21, 2026 the wall and the phones are all updated through TestFlight, and a cable install (`scripts/deploy-ipad.sh`) is a developer's option; this setting is what lets a wall installed either way share the household.
Debug builds, simulators and tests stay on Development.
This is experiment S4, and it is confirmed on real devices before M2 invites anyone.

Production only accepts record types and fields that were deployed to it.
See "Deploying the CloudKit schema" below for how they get there.

## Deploying the CloudKit schema

Production never learns anything by itself; its schema is whatever was last deployed to it from Development, and a table or column missing there fails on its first real value.
Development learns a schema either from records (a record type when one is first saved, a field when a non-nil value of it is first saved) or from a schema file imported with `cktool`.
Production keeps every field it is given forever, so what goes there must be exactly what the app writes.

The path, with no device involved:

1. **Test.** `SchemaFileTests` derives the schema from the app itself (`SyncMirror.all`, by the rules below) and compares it with `Config/cloudkit-schema.ckdb`, record type by record type and field by field; it names anything missing, extra or of the wrong type.
   It runs with every unit test run, so the file can't drift from the app.
2. **Import.** `scripts/cloud-schema.sh import` validates the file against Development, imports it, exports Development again and fails unless it matches.
3. **Deploy.** James clicks "Deploy Schema Changes..." in the CloudKit Console (Development to Production); `cktool` can't change Production.
4. **Check.** `scripts/cloud-schema.sh check` confirms Production has everything in the file.

A new table or column therefore goes in the file by hand, in the same change, and the test says when it is wrong.

### What CloudKit has to know

SQLiteData writes one record type per synced table, named like the table, in one zone of the private database (`co.pointfree.SQLiteData.defaultZone`).
Each record type has these fields (read from SQLiteData 1.13.0's `CKRecord.update(with:userModificationTime:)`, checked by `SchemaSeedTests` against its stand-in for iCloud, and the rules `SchemaFileTests` derives the file from):

- one field per column, named like the column: encrypted, and typed by the mirror (`String` and `UUID` as strings, `Int` and `Bool` as 64-bit integers, `Double` as a double, `Date` as a date and time);
- `BLOB` columns (the three photo tables' `image`, `journalPage.drawing`) as plain asset fields, each with an encrypted `<column>_hash` beside it;
- `sqlitedata_icloud_userModificationTime_<column>` for every column, an encrypted 64-bit integer SQLiteData compares to merge edits field by field;
- `sqlitedata_icloud_userModificationTime` for the whole record;
- the record's parent, a system field, for every table but `household`.

`SchemaFileTests` reads and leaves out only what no table describes: each record's system fields (`___recordID` and the like), the grants, CloudKit's own `Users` type and `cloudkit.share`.

Sharing adds the system record type `cloudkit.share`: SQLiteData saves a `CKShare` of the household record (`share-<recordName>`) in the household's zone, and the app (or the share sheet) may set its `title` and `thumbnailImageData`.
SQLiteData creates no other record types in iCloud: its own tables (`sqlitedata_icloud_metadata`, `_recordTypes`, `_stateSerialization`, `_unsyncedRecordIDs`, `_pendingRecordZoneChanges`) stay on the device.

Indexes: SQLiteData never queries CloudKit; it reads zone changes through `CKSyncEngine`, and the sharing code reads records by id.
So nothing needs a queryable or sortable index.
The CloudKit Console's record browser wants `recordName` queryable to list records, which is a convenience for looking, not something the app needs; it can be added in the Console at any time.

### The seed, an optional cross-check

The seed is no longer the path; it is a cross-check that a real build, writing to real iCloud, makes exactly the fields the file has.
It needs a signed build on a device or a simulator signed in to iCloud, and signing its own bundle id with the App Store Connect key is currently refused by Apple ("Authentication failed"), so it is optional.
A Debug build launched with `-seedCloudSchema` writes all of it to Development (`Porchlight/Sync/SchemaSeed.swift`):

1. It opens a throwaway database with its own sync metadata in the temporary folder; nothing of the household on the device is opened.
2. It writes one row to every synced table, parents first, with a value in every column (dates, ids pointing at the seeded rows, a few bytes for every BLOB), driven by `SyncMirror.all`, so a new table or column is seeded without anyone remembering to.
   `SchemaSeedTests` fails when a column has no value or a mirror column has a type the seed doesn't know.
3. It starts a sync engine on its own zone, `porchlight.schemaSeed`, never the household's, and sends until every row is saved.
4. It shares the seed household, with a title and a thumbnail, so `cloudkit.share` and its fields exist.
5. It reads back every saved record from the engine's metadata and checks that every column is a field.
6. It deletes its zone from iCloud (the records and the share go with it) and the throwaway files, then shows "Schema seeded: 24 record types, 23 records sent, household shared." or what failed.
   The record types stay in Development's schema, which is the point; no seed data remains in anyone's iCloud.

It runs from its own app, "Porchlight Seed" (`com.mingyucao.porchlight.schemaseed`), a Debug build of Porchlight with another bundle id and name, signed for the same iCloud container.
An iCloud container can be used by several app ids of a team when each lists it in its entitlements, and Xcode's automatic signing registers the new id with the container on the first build.
Installing it never replaces the Porchlight app beside it, so that app's data, its Release build, its sync switch and its Production environment are untouched.
Installing a Debug build over Porchlight itself would keep its data but switch it to Development until the next Release install, which is why the seed doesn't.

### `scripts/cloud-schema.sh`

- `import` validates `Config/cloudkit-schema.ckdb` against Development (`cktool validate-schema`), imports it (`cktool import-schema`), exports Development again and fails unless the two say the same, field for field; when they differ only in layout, it writes the export's layout back to the file to commit.
- `seed` (optional) builds Porchlight Seed, installs it on the first paired iPhone (or `PORCHLIGHT_SEED_DEVICE`), launches it with `-seedCloudSchema` and says what to watch for; `seed --simulator <id>` does the same on a simulator signed in to iCloud.
- `uninstall-seed` removes Porchlight Seed afterwards.
- `export` writes Development's schema to `Config/cloudkit-schema.ckdb` with `xcrun cktool export-schema`.
- `diff` compares the checked-in file with Development, ignoring layout.
- `check` exports Production's schema and compares it with the checked-in file, and when they differ prints the deployment steps below.
  (`cktool validate-schema` refuses Production: "endpoint not applicable in the environment 'production'".)

`cktool` can export schemas from both environments, but validates and imports only in Development; deploying to Production is a button in the CloudKit Console.
`cktool` needs a management token, made once:

1. Open https://icloud.developer.apple.com, sign in with the developer account, and pick the team.
2. Open Settings, then Tokens & Keys, and add a Management Token; give it a name like "cktool on James's Mac".
3. Copy the token and run `xcrun cktool save-token --type management`, pasting it at the prompt; it is kept in the Mac's keychain.

### Deploying to Production

1. In the CloudKit Console, open CloudKit Database and pick the container `iCloud.com.mingyucao.porchlight`.
2. With Development selected at the top, click "Deploy Schema Changes...", check that the list matches `Config/cloudkit-schema.ckdb`, and click Deploy.
3. `scripts/cloud-schema.sh check` then says Production has everything.

Deploying only adds; CloudKit never removes a deployed record type or field, which matches the rule that columns are only ever added.

### The first rollout

The first schema came from the seed on James's iPhone (`seed`, `export`, review, Deploy, `check`), before the wall's sync switch was turned on.

### Every release that adds a table or a column

1. The change adds the column or table to its mirror (`SyncMirrors.swift`) and to `Config/cloudkit-schema.ckdb`; `SchemaFileTests` passes.
2. `scripts/cloud-schema.sh import`, from the change's branch, before anyone installs the build.
3. James deploys in the CloudKit Console.
4. `scripts/cloud-schema.sh check`, before the build reaches TestFlight.

### Fields waiting for Production

- `careLog.slot` and `sqlitedata_icloud_userModificationTime_slot` (encrypted 64-bit integers), with the build that remembers which slot a log was made for.
  Every care log that build writes carries them; older builds ignore the field, keep it when they edit a log, and place the log by its time.
- `journalEntry.otherSources` (encrypted string) and `sqlitedata_icloud_userModificationTime_otherSources` (encrypted 64-bit integer), with the build whose meals can come from several places ("Where, one kind or several").
- The record types `dish`, `mealDish` and `mealDishRating`, with the build whose meals name their dishes (dishes.md).

### When iCloud turns changes down

If sync is turned on before Production has the schema, CloudKit refuses each record ("Cannot create new type ... in production schema").
SQLiteData 1.13.0 keeps the row on the device but drops it from what it sends, and tells the app nothing; it queues such rows again only when the account signs in.
So `SyncController` looks for rows iCloud never took (`SyncUnsent`) 30 seconds after each round of syncing ends.
While there are any, the status is `notAccepted`: Settings says "iCloud isn't taking N changes yet. They are safe on this iPad and Porchlight offers them again by itself.", the phone's banner says the same, and it counts as stuck, so the gear's dot appears after an hour.
Every ten minutes, and at every launch, it queues them again (touching their metadata, as SQLiteData does after signing in) and sends.
Once the schema is deployed the next offer goes through, the count drops to zero, and the status is up to date, with nothing lost and nothing to do.

## Photos

Photo files become rows, so they can sync as iCloud assets.

| New table | Key | Holds |
|---|---|---|
| `journalEntryPhotoThumb` | `photoId`, also its foreign key to `journalEntryPhoto` | the thumbnail JPEG |
| `journalEntryPhotoImage` | `photoId`, also its foreign key to `journalEntryPhoto` | the full JPEG, 2048 px on the long side |
| `companionPhoto` | `companionId`, also its foreign key to `companion` | the companion's photo |

- Each has a `byteCount` column, which is what the storage meter sums.
- Thumbnails and full images are separate tables so grids never load full images.
- One size syncs.
  There is no separate "original kept on the device": the 2048 px image is the photo.
  This is simpler than the proposal's two-copy idea, and a phone that wants the original can save it to Photos at capture time.
- The rows are the source of truth.
  Views read through a small image cache keyed by photo id.
- A migration imports every existing file into its row, then removes the file only after the row is written and read back.
- Pencil pages already live in `journalPage.drawing`.
- The photo frame's own library (`ambientPhoto`) stays on the device.

Every device downloads every photo of the household.
At roughly half a megabyte each that is fine for years, and the storage page says so.
Fetching full images on demand is a later improvement if it is ever needed.

## Account changes

SQLiteData's default on sign-out is to erase the local data.
That is wrong for a wall that must keep working, so `SyncController` is the engine's delegate and decides:

| Event | What happens |
|---|---|
| Signed out of iCloud | Sync stops. The data stays and the app keeps working on this device. Settings explains how to turn sync back on. |
| Signed back in to the same account | Sync resumes and sends what queued up. |
| A different account signs in | The data on the device belongs to the earlier account's household. Sync stays off and Settings asks what to do: keep using it here without sync, or remove it from this device. Nothing is uploaded to the new account without that choice. |
| The owner's iCloud is full | Changes keep saving locally. Status becomes "paused: iCloud is full" until the engine reports room again. |

### When iCloud isn't there

CloudKit's account status has five answers, and only "available" lets sync run.
Each of the other four has its own state (`ICloudAccountProblem`) and its own words, because each asks something different of the person:

| CloudKit says | State | What the phone's banner and the wall's Settings say |
|---|---|---|
| `noAccount` | signed out | "iCloud is off for Porchlight": sign in to iCloud, or turn it on for Porchlight, in Settings. |
| `restricted` | restricted | "iCloud isn't allowed on this iPhone": Screen Time, or whoever manages the device, has turned it off. |
| `temporarilyUnavailable` | needs sign-in | "iCloud needs you to sign in again": sign in to your Apple Account in Settings. |
| `couldNotDetermine`, or the check fails | couldn't check | Nothing at first, as for being offline; after an hour, "Can't check iCloud". |

CloudKit gives the same `noAccount` for a device signed out of iCloud and for iCloud switched off for Porchlight in Settings, so the words name both rather than guess which; that the per-app switch really answers `noAccount` is still to be checked on a device (docs/design/release-checklist.md).
CloudKit doesn't use iCloud Drive, so iCloud Drive off changes nothing.
"Couldn't check" assumes nothing about the account: the household isn't said to be on this device only, and inviting isn't blocked, since the next check may well pass.
Every one of them keeps the data and the app working on the device, and sync starts by itself once the account answers "available".

## Status the UI can show

`SyncStatus` is one of: off, iCloud not there (with why, above), up to date (with the last time iCloud answered), syncing, waiting (offline, or checks keep failing, with the last time iCloud answered), paused because iCloud is full, not accepted (changes iCloud turned down), or needs a decision (account changed).
The wall shows it only in Settings, plus a dot on the gear when it has been stuck for an hour (journey D3).
"Up to date" means iCloud answered recently: Settings says "Up to date, checked at 10:41 PM", and three failed checks in a row turn it into "Can't reach iCloud right now, last reached at 10:41 PM".

## Staying current

The first two-device test showed a wall that never heard of a phone's log: the phone's change reached iCloud, and the wall, open the whole time, didn't fetch it.
The engine only fetches by itself when a push arrives, at launch, or when asked, so a wall that waits for pushes is only as current as its pushes.

### Pushes, the fast path

SQLiteData adds no push handling of its own: its guide asks only for the "Remote notifications" background mode (SQLiteData 1.13.0, `Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md`, lines 41 to 43), and nothing in its sources registers for or receives remote notifications.
`CKSyncEngine` subscribes to the databases and takes CloudKit's pushes itself, then fetches; creating an engine makes CloudKit register the app for remote notifications (Apple's answer in the developer forums, thread 807047).
The app also calls `registerForRemoteNotifications()` once an engine exists: UIKit hands back the same token, so it changes nothing for the engine, and it makes the app delegate hear whether a token arrived.
On the first two devices the phone (iOS 27) got the wall's changes in seconds, by push as far as anyone could tell, and the wall (iPadOS 17) got the phone's never, so cable-installed Release builds do get pushes at least on one side; why the wall doesn't is still open (see "Seeing what sync does" for what to look at).
Even where pushes arrive, iOS delivers silent pushes at its discretion and throttles them, so they can't be the only thing that keeps the wall current.

### Asking on a schedule

So `SyncController` asks for changes itself (`SyncPoller`):

- at once when the app comes to the front, when the network comes back, and right after sync is turned on (starting the engine fetches by itself, so a launch in the background asks nothing more);
- then, while the app stays in front, every 15 seconds on a shared screen and every 30 seconds on someone's own phone;
- never in the background, never offline, and never two at a time.

Each check is one `fetchChanges`, which asks iCloud for database changes and, only when there are some, the changed zones' records.
A check that finds nothing is one small request per database (private and shared); four a minute from one wall is far below CloudKit's per-user request limits (tens per second), and on the 2017 iPad it is a network request every 15 seconds that does no database work, which the idle-CPU budget doesn't notice.
Fifteen seconds is about how long someone walks from the door to the hallway after logging on their phone; shorter buys little and costs requests, longer starts to feel like the wall missed it.

A check that fails waits twice as long before the next one, up to five minutes, and the network coming back starts again at once.
A check never shows as "Syncing", writes nothing to the app's tables (at most the engine saves its own state, which no screen observes), and moves the last-synced time at most every five minutes when nothing else happened, so a quiet poll redraws nothing.

### Sending

A change made in the app is recorded by the engine's triggers in the same transaction, and `CKSyncEngine` sends it on its own schedule, usually within seconds while the app is in front.
Changes made offline wait in the engine's saved state and go when it is back online.
When the app leaves the front (the phone locked right after a log), `SyncController` sends what is pending inside a background task, so iOS gives the send time to finish rather than suspending it.
Whatever still didn't go goes at the next launch; nothing is lost.

### What to expect

On the cable-installed builds, a log on the phone reaches the wall within about 20 seconds while the wall is open: the phone sends within a few seconds, and the wall's next check is at most 15 seconds away.
Where pushes reach the device it is usually faster, a few seconds.

## Seeing what sync does

A wall that silently stops hearing the phone is the worst kind of bug: nothing on screen says so.
So sync tells the truth, and says what it is doing to whoever asks.

### The status

"Up to date" needs a check iCloud answered in the last three minutes (a poll, a push's fetch, or a round the engine ran itself).
Without one, sync is on but says "Checking with iCloud, last checked at 10:41 PM…", a stuck state, so the gear's dot comes after an hour.
Checks that fail three times in a row say "Can't reach iCloud right now".

### Sync details

Under the switch, on the wall's iCloud Sync section and on the phone's sync row, "Sync details" folds open to:

- the role (shared screen or personal), whether the app is in front and what said so (a notification, or the state read at launch), online, the engine running, the iCloud account;
- the last check: when, how it ended, and what started it (launch, came to front, timer, network back, sync turned on, push, check now); checks so far and failures in a row; the last error as its CloudKit code; when the next check is due;
- pushes received and the last one's time, whether a push token arrived (its length, never the token) or registration failed with which error, whether the app is registered for remote notifications, Background App Refresh, Low Power Mode;
- rows iCloud has no record of yet, and changes queued while the engine was stopped;
- "Check now", which runs one check at once.

It reads its own observable object (`SyncTrace`), so nothing else redraws when a check ends.

### The log

The same events go to `os.Logger` (subsystem `com.mingyucao.porchlight`, category `sync`) and to a rolling file, `sync-log.txt` in the data folder, which keeps about the last 400 lines.
Lines carry states, counts, record types and CloudKit error codes, never anything the family wrote.
Copy it off a device with:

```
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier com.mingyucao.porchlight \
  --source "Library/Application Support/Porchlight/sync-log.txt" --destination wall-sync-log.txt
```

### Pushes, made visible

`AppDelegate` implements the three push callbacks (`PushReceipt.swift`): a token arriving (its length is logged), registration failing (its error), and a remote notification arriving (whether it is CloudKit's, database or zone, which database, which subscription).
SQLiteData implements none of them and has no way to be handed a notification, and the engine takes its pushes through CloudKit itself, so implementing them only watches; a push also starts one check of our own, so a push the engine somehow ignored still brings the change in.

When pushes don't reach a device, Sync details tells the causes apart:

- No push token, or "failed: …": the device never registered with APNs (no network to Apple, an entitlement problem).
- A token, but "Pushes 0" while the other device changes things: APNs isn't delivering. On Wi-Fi that blocks Apple's push port (TCP 5223, falling back to 443), pushes stall; try the same device on cellular or another network. The CloudKit subscription for this device may also be missing, which only a fresh engine (sign out and in, or a reinstall) recreates.
- Pushes counted, but the change still missing: the push's own check failed; its error is under "Last error".
- Background App Refresh off, or Low Power Mode on: silent pushes are held back while the app is in the background; in front they still come.
- No pushes and no checks either, with "In front: no": the app doesn't think it is in front, so it isn't polling; the source says what last told it so.

### Fetching both databases

SQLiteData's `fetchChanges` asks the private and the shared database together and throws if either throws, and the throw cancels the other's fetch.
An owner's household lives in the private database and a member's in the shared one; the other database holds nothing of it and may fail for reasons of its own.
So when asking for everything fails, the check asks again for the household's own zone alone (`FetchChangesOptions(scope: .zoneIDs(...))`, the zone read from the engine's metadata), and counts as answered when that does.
The failure of "everything" stays visible under "Last error", and never backs off the household's own checks.
SQLiteData doesn't expose its two engines, so the two databases can't be asked separately without changing the library.

### When fetching brings nothing

On the wall (iPadOS 17.7) every check was answered, yet four checks after the phone's change brought neither its new row nor its deletions, while a relaunch, which starts a fresh engine, brought them at once.
Nothing on our side swallows the fetch: SQLiteData's `fetchChanges` calls `CKSyncEngine.fetchChanges` on the running private and shared engines and returns after the engine has handed every fetched change to its delegate (the header's note: the completion runs "only after your sync delegate finishes processing all related fetch events"); the poller's timeout only answers early and never cancels a fetch that finished; the household-zone retry only runs after an error; and ignoring fetch activity while a check runs only keeps "Syncing" off the screen, the engine's events are applied regardless.
Why the explicit fetch of a long-running engine brings nothing there isn't documented; it may be iOS 17's `CKSyncEngine`, and it can't be reproduced without iCloud on a simulator.
So a check no longer trusts it:

1. It asks iCloud itself which zones changed since the last check, with its own change tokens apart from the engine's (`CKDatabase.databaseChanges(since:)`, one small request per database), each database on its own, so one failing never hides the other.
   The first probe of a launch is only a baseline: the engine's start fetches everything older.
2. Nothing changed: the check is answered and nothing else is asked, which is also the cheapest check there can be.
3. Something changed (or the check came from a push or "Check now"): the engine fetches; when rows arrive, done.
4. iCloud said something changed and the fetch brought nothing: the engine is stopped and started, as a relaunch does, and fetches.
   It waits for a send in progress, and its saved state keeps pending sends; rows iCloud has no record of are queued again after it starts.
   The wall's own sends also show as a changed zone, so a tap on the wall can cost one quiet restart, a few small reads of the schema and two requests: nothing the 2017 iPad notices at the rate people tap it.

Each check's log line says what it brought and how: "nothing new (timer)", "received changes via timer, engine fetch: 149 to 150 rows", "received changes via timer, engine restart: …", or "iCloud reported private 1 zone changed; nothing new arrived" (most often this device's own send).
Sync details shows the same under "Brought in", "iCloud says" and "Engine restarts", so the next device test is conclusive from the log alone.

### A device that gets no push token

The app asks for a token when the engine is created, again 30 seconds, 2 minutes and 10 minutes after coming to the front while none came, and whenever the network comes back; each ask is logged with "registered for pushes: yes/no".
iOS answers an ask with either a token or an error; it answers with neither while the device's push daemon has no connection to Apple's push service for the app's environment (a development-signed build uses the sandbox service), and keeps the ask open until it has one.
So no token and no error over minutes, on more than one network, points at the device: its push daemon stuck (a restart of the iPad is the usual cure), or the device not reaching the sandbox push service, which a development-signed build needs and a TestFlight build doesn't.
A token that arrives with no pushes after it points at delivery instead (the subscription, or the network), and "Pushes" counts what arrives.
SwiftUI forwards the push callbacks to the app delegate through `UIApplicationDelegateAdaptor` on iOS 17 as on later versions; the phone, running the same code, gets its token and its pushes.

### Checks that hang

A check that takes more than a minute counts as failed; the fetch is cancelled and left to finish on its own, so it can never stop the checks that follow.

## A fresh install looks for a household first

A new or wiped device signed in to an account that already has a household must not walk through "create a household".
On first launch the app starts the engine and waits briefly for the first fetch.
If a household arrives, it opens it.
If none arrives, it shows the usual welcome.
This is also what makes the M1 gate, "a wiped device gets the whole household back", a real user journey.

## Data changes after sync is on

SQLiteData records a write only while its engine exists on the connection: the engine installs temporary triggers when it is created, and they are gone when the app quits.
A write made before the engine exists is never recorded, and once a table is known to the engine nothing looks for unrecorded rows, so the write never uploads.

The rule: any migration that inserts or rewrites rows of synced tables, once sync has been on anywhere, must run after the engine is created.

The app opens the database and runs every migration before it creates the engine, so ordinary migrations do not satisfy the rule.
Schema migrations stay there, since the engine needs the final schema to start, and they must not write synced rows from now on.
Row changes go into a second migrator, `AppDatabase.dataMigrator()` in `DataMigration.swift`, which the app runs right after creating the engine (`migrateData()` in `PorchlightApp`).
It shares `grdb_migrations` with the schema migrations and has no migrations yet.
A unit test checks that a data migration run after the engine exists is recorded and uploaded.

"sync v2" (photos as rows) is a schema migration that writes rows, and that is safe only because sync had never been on anywhere: on the engine's first start every table is new to it, so it uploads every row.

## A new column, and older builds

A household can have devices on different builds for a while (TestFlight updates each device in its own time, and a wall may be on a cable install), so a new column must leave older builds reading and editing every row safely.
What SQLiteData 1.13.0 does, read from its source and checked by tests:

- **A field an older build doesn't know:** it reads only the columns it has, so the row arrives whole minus that field.
  When it saves the row, it starts from the last record iCloud gave it (`_lastKnownServerRecordAllFields`) and writes only its own columns, so the newer field goes back up as it was (`MealSourcesSyncTests.unknownFieldSurvives`).
  When that device updates, the engine fills the new column from the records it kept, so nothing is lost there either.
- **A value an older build doesn't know in a column it does know** (a new case of an enum): decoding the row fails, so the older build can't show it at all.
  New meanings therefore go in new columns, never as new values in old ones.
- **Every save of a row carries every column, and each column's modification time,** even a nil one: `sqlitedata_icloud_userModificationTime_<column>` is written for every column.
  So once a build with a new column ships, every save of that table sends the new field, and Production must have it first.
- **New tables, on the device that updates:** 1.13.0 puts the records it kept into the new tables in no set order, so a child table could come before its parent and stop there.
  The app builds SQLiteData from our fork, which sorts them parents first (`project.yml`; docs/design/dishes.md, "Why a card photo hangs off the dish").

### Where, one kind or several

A meal's Where became a set of kinds.
`journalEntry.source` stays the primary kind, a value every build knows: the first kind picked that names a restaurant, else the first in the pills' order.
The new nullable `journalEntry.otherSources` holds the rest, comma-separated in the pills' order ("company"), and is nil for a meal of one kind; kinds it names that a build doesn't know are skipped.
The meal's kinds are the two together (`MealSources(primary:others:)`).

- An older build shows a two-kind meal as its primary kind alone: a delivery dinner at the office reads as Delivery, with its restaurant.
- An older build that edits the meal keeps `otherSources` as iCloud had it; if it changes the kind it can see, the meal becomes that kind and the others (Delivery and Company changed to Dine out is Dine out and Company).
- The migration ("food v6: a meal from several places") is a plain `ALTER TABLE ... ADD COLUMN`, writes no rows, and every meal so far reads as its one kind.

Before this ships, Production needs two new fields on `journalEntry`, both already in `Config/cloudkit-schema.ckdb`: `otherSources` (encrypted string) and `sqlitedata_icloud_userModificationTime_otherSources` (encrypted 64-bit integer).
They go there the usual way: `scripts/cloud-schema.sh seed` from a device on the new build, `export` and review, Deploy Schema Changes in the CloudKit Console, then `scripts/cloud-schema.sh check`.
If a new build reaches Production before they are deployed, every meal it adds or edits is turned down; it stays on the device, the status says "iCloud isn't taking N changes yet", and it goes up by itself once the fields are deployed ("When iCloud turns changes down"), with nothing lost.

## Backups and restore

`scripts/backup-ipad.sh` copies the whole data folder, `Library/Application Support/Porchlight`.
SQLiteData keeps its metadata in a database beside the app's own: `attachMetadatabase(containerIdentifier:)` names it after the database and the container, so it is `.porchlight.metadata-iCloud.com.mingyucao.porchlight.sqlite` (a hidden file, with its own `-wal` and `-shm`), in the same folder.
It holds what the engine knows about every row (the last record iCloud confirmed, and when each field last changed), the engine's change tokens, the changes still waiting to be sent, and the tables it has seen.
So a backup carries an older pair: the data and the metadata that describes it.
Each file is consistent on its own; with the database in WAL mode, SQLite does not keep two attached databases in step, so the pair is as consistent as a crash would leave it, which the library has to recover from anyway.
`scripts/restore-ipad.sh` folds the app database's write-ahead log into it and copies the rest of the folder, metadata included, as it is.

After a restore the engine resumes from the older change token and fetches everything changed in iCloud since, including deletions, and resends the changes it had not sent at the time of the backup.
Conflicts are settled field by field by the time of the edit, so the newer values in iCloud win.
A restore therefore repairs one device, which iCloud then brings forward again; it does not roll the household back for everyone.
To roll the household back, the data would have to change in iCloud itself.

Two cases need care, and neither has been tried on a device yet:

- A backup made before the iPad ever synced has no metadata.
  Restored onto an iPad whose switch is on, the engine would meet every table as new and offer every old row as a fresh change, which could overwrite newer values in iCloud.
- The sync switch, the account name and the last-synced time live in the app's preferences, outside the data folder, so a backup neither saves nor restores them.

### A restored database never syncs on its own

Since M2 the app notices when its database was replaced underneath it, and sync then waits for the owner (`DatabaseIdentity`).

- Every launch puts a fresh random token in the database's device-only `deviceState` table and in UserDefaults.
  A backup never holds UserDefaults, so a restored backup brings back an older token, or none, and the two disagree at the next launch.
  The token is rotated so a crash halfway never looks like a restore: UserDefaults first holds the old and the new token, then the database gets the new one, then UserDefaults keeps only the new one.
- A database token with nothing in UserDefaults means the data folder was copied into a fresh install, for example when the wall's data moves to a new bundle id.
  That install has never synced, and a device that already has a household starts with the sync switch off, so nothing is sent until the owner turns it on; it is not treated as a replaced database, which would otherwise leave no way to sync it short of dropping it.
- The engine's metadata database missing at launch, on an install that has synced before (it knows its iCloud account), is the same hazard: every row would look new.
  The check runs before the database opens, because opening it creates the metadata database.
- A database with no household, and the very first launch (no token anywhere), are never taken for a restore.

When it is replaced, sync stays off and Settings shows the "needs a decision" card, with two choices in plain words:

- "Use what is in iCloud" drops this device's copy with the engine's `deleteLocalData()`, then starts sync and looks for the household, which comes back as everyone last left it.
- "Keep this copy on this iPad, without sync" turns the switch off; turning it on later asks again.

Sending the restored copy up over everyone's data is deliberately not offered.
The decision is kept in UserDefaults, so it survives relaunches, and it comes before a changed account, since it is the one that could overwrite newer data.
Sample data never syncs, so sample launches skip the check; `-debugSyncStatus restoredCopy` shows the card.
The one restore this cannot see is a backup put back before the app ever launched again, which holds the token of the running app: such a backup and its metadata are a consistent pair, which the engine resumes from as described above.

## Tests

- Mirror types match their tables.
- A database filled through the app's own write functions, with the engine attached, ends with every row known to the engine and none left pending.
- Rows written before the engine first starts are uploaded.
- Each account event leads to the state in the table above, with the data intact.
- Photo import: every file becomes a row with the same bytes, and files are removed only afterwards.
- SQLiteData's iCloud stand-in is internal to its package, so two devices cannot be simulated in our unit tests.
  Two-device and sharing behavior is verified on real devices with a written checklist, starting with the M1 gate.

## Not in M1

- Inviting and joining (M2).
- Choosing between several households (M2 for the model, M5 for the switcher).
- Any phone UI.

## Implementation notes

Choices made while building M1, where the design above left room or did not fit the library.

### The engine

- The mirrors are `SyncMirror.Household`, `SyncMirror.Person` and so on, and `SyncMirror.engine(for:delegate:)` hands all twenty-two to `SyncEngine`, in `SyncSchema.synced` order.
- The engine is created on every launch that can sync, even with the switch off, and is only started when the switch is on.
  Its triggers are temporary: they record writes only while an engine exists, so a write made while no engine existed would never be uploaded once the tables are known to it.
  It is created right after migrations and the DEBUG launch arguments, before any store, so no write slips past it.
- No engine is created for sample data (`AppFiles.isSandboxed`) or in a build without the iCloud entitlement.
  The entitlement is read through SwiftData's `ModelConfiguration`, the same way SQLiteData reads it, because `CKContainer` traps without one.
  Status is then "off" with the reason, which Settings shows in Debug builds.
- Every connection to the database on disk attaches the engine's metadatabase in `prepareDatabase`, naming the container rather than reading it from entitlements, so unsigned builds open the database as before.
  In-memory databases do not attach it: SQLiteData's in-memory metadatabase is shared by every connection in the process, which would couple tests running in parallel.

### Accounts

- Before starting, `SyncController` reads the iCloud account's user record name and keeps it on the device.
  If a different name turns up, sync stays off and status becomes "needs a decision", before anything is sent.
  The engine's own `switchAccounts` event leads to the same state, for a switch while the app runs or while the name can't be read offline.
- The decision survives relaunches.
- "Keep it here without sync" turns the switch off and keeps the earlier account's name, so turning sync on again while the other account is signed in asks again.
  Moving the household into the new account is not offered; signing back in to the earlier account resumes as before.
- "Remove it from this iPad" calls the engine's `deleteLocalData()`, which clears every synced table (the household cascades to the device-only tables) and resets the engine's metadata, then removes the photo folders and syncs with the account signed in now.
- Signing out stops the engine and keeps everything.
  The controller listens for `CKAccountChanged` itself, since a stopped engine sends no events, and resumes when the same account is back.
- A full iCloud only counts for the household's own (private) database; shared databases arrive with M2.

### Status

- "Syncing" follows the engine's `isSynchronizing`.
  The end of a round of syncing while online is the last-synced time, kept in UserDefaults.
- "Waiting" covers both being offline (from `NWPathMonitor`) and the moment at launch before the account has been checked.
- Stuck means waiting, iCloud not there, iCloud full or needs a decision (`SyncStatus.isStuck`).
  The controller starts a clock when the status becomes stuck and stops it when it no longer is; going from one stuck state to another keeps the clock.
  After an hour the gear on the rail shows a small ochre dot (`Theme.warn`), which VoiceOver reads as "Sync needs a look".
  The clock is kept in memory, so a relaunch starts it again.
- A full iCloud also shows a paused banner in Settings, like the `d3pause` frame, without the owner's name, which M1 doesn't know.
- `-debugSyncStatus off|upToDate|syncing|waiting|noAccount|restricted|needsSignIn|couldNotCheck|iCloudFull|needsDecision|lookingForHousehold` runs a controller with no engine in that state, with its own throwaway preferences, for screenshots and UI tests.
  It works only on sample data: on real data a launch without the engine would leave its writes unrecorded.
  A stuck one shows the gear's dot at once.

### Project

- The Release configuration sets the container environment to Production and Debug to Development through a build setting in the entitlements.
- `aps-environment` is `development` in both: cable installs are development-signed, and an App Store or TestFlight export rewrites it to production.
- Command-line builds need `-skipMacroValidation` for SQLiteData's macros; the scripts pass it.

### Photos

- `companionPhoto`, `journalEntryPhotoThumb` and `journalEntryPhotoImage` are keyed by their parent's id, which is their one foreign key (`ON DELETE CASCADE`), as SQLiteData's guide does for cover images.
  Their columns are the key, `byteCount` and `image`, in that order, so reading the byte count never walks the image's overflow pages.
- The migration is "sync v2: photos become rows", registered after "sync v1".
  It creates the tables, reads every file a row names, and drops `journalEntryPhoto.photoFile`, `journalEntryPhoto.thumbnailFile` and `companion.photoFile` with `ALTER TABLE ... DROP COLUMN`, the last removal of a synced column.
  It needs the data folder, so `AppDatabase.migrator(files:)` and `AppDatabase(_:files:)` take it; in-memory databases pass none and import nothing.
- Files are removed by `PhotoFileCleanup` after the migration's transaction has committed.
  The migration lists each imported file, with the SHA-256 of the bytes it stored, in a device-only table, `photoFileImport`, in the same transaction.
  The cleanup runs each time the database on disk opens: it removes a file only when its row reads back with that digest, then drops the table and any emptied folder.
  A crash in between leaves both the files and the rows, and the next launch finishes the job.
  The table exists only while files wait, so an upgraded wall ends with the schema of a new one.
- The odd cases on real walls: a missing file never fails the migration.
  A photo whose whole shot is gone keeps its thumbnail as its only picture; it shows on the wall, can't be reframed, and isn't offered to the photo frame.
  A photo whose thumbnail is gone gets one made again from the whole shot and its crop; so does one whose thumbnail file was its whole shot, which "food v4" did for single photos.
  A photo with neither file keeps its row without pictures, and shows its plate as before.
  A file that isn't a readable image is stored byte for byte.
  A file no row names, or one whose row doesn't read back the same, stays in its folder and is never removed automatically: nothing reads it, and a photo is worth more than its space.
- Whole shots larger than 2048 pixels on their long side are re-encoded at 2048 on import, with ImageIO; smaller ones keep their bytes.
  Capture already stored 2048 pixels, so in practice every file is imported byte for byte.
  Companion photos keep their 800-pixel size.
- New photos never touch the disk: a shot is made into a `NewMealPhoto` (whole shot and thumbnail, in memory) and written as rows when the meal saves.
  Discarding a capture, removing a photo before saving, and reframing in an edit that is cancelled leave nothing behind, so the old file sweeps and "unused file" bookkeeping are gone.
  A reframe keeps its new thumbnail in the edit and writes it on Save.
- A companion draft carries its photo's bytes.
  Saving writes the photo row only when the bytes differ from the saved ones, so onboarding's save-as-you-type never rewrites (or re-uploads) it.
- `PhotoImages` replaces the file stores and `MealImages`.
  Views name a picture by `PhotoSource` (the row, with its byte count) and an optional crop; it reads the row and decodes off the main thread, once per request however many views ask, into an `NSCache` limited to 96 MB of decoded pixels.
  The byte count is the version: a reframed thumbnail, a new companion photo or a picture that arrives by sync has a new count, so a cached image is never shown for a picture that changed.
  Snapshots read only the byte counts, never the bytes.
- `PhotoView` draws a cached image in the first frame; otherwise it shows a quiet placeholder (the tablecloth tint, or the coat's color) while loading, so the plate or drawn face never flashes up before a photo, and falls back to them only when there is no picture.
- Grids and lists load thumbnails only; the whole shot loads where one photo fills the view (the saved polaroid, the whole-photo view, reframing) and in the photo frame, which downsamples it for the screen and never puts it in the cache.
- `AppFiles` only knows the photo frame's `Ambient` folder now, and "Remove it from this iPad" removes only that: the photo rows go with the household.

### A fresh install looks for a household first

- `SyncController` starts the search at launch when there is no household, the engine exists and the switch is on (always so for a new install).
  It waits for the account check and the engine's start, then `fetchChanges()`, at most 30 seconds.
  The search screen shows only while there is no household, so a household that arrives ends it at once; the fetch ends it otherwise, as does the time limit.
- `HouseholdSearchView` uses the onboarding's logo, fonts and secondary button, and offers "Start fresh instead" after four seconds.
  Starting fresh only ends the search: sync keeps running, so the household it sets up uploads.
- `RootScreen.pick` decides the screen: the search, onboarding or the wall.
  A household that is set up opens the wall wherever it came from, so a household that arrives while onboarding shows its first two steps opens too, not only on the first screen.
  Holding onboarding there instead would let it create a second household next to the one that arrived.
  Once onboarding has created its household, a household from iCloud that arrives later is older, so `Household.current` would pick it; choosing between households is M2's.
- Sample data and builds without the entitlement have no engine, so they never search, and simulators and UI tests behave as before.

### Tests

- SQLiteData's stand-in for iCloud refuses more than 200 records in one request, where the real `CKSyncEngine` splits them into batches itself, so the sync tests fill each table with a few rows rather than the sample household.
- Account events are given to `SyncController` directly, as the engine's delegate would, since the stand-in's controls are internal to its package.
- A household arriving from iCloud is written to the database directly, as the engine would, for the same reason; the search's time limit and the gear's hour are shortened through `SyncController.Timing`.
- The "sync v1" comparisons migrate only up to "sync v1", since "sync v2" removes columns they compare.
- `PORCHLIGHT_REAL_DATA_DIR`, like `PORCHLIGHT_REAL_DB`, runs a test on a copy of the wall's data folder: it migrates a further copy and checks that every photo file a row named is in a row with its bytes.
