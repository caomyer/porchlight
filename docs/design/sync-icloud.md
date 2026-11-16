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

- Entitlements: iCloud with CloudKit and the container `iCloud.com.porchlight.porchlight`, push notifications, and the remote-notification background mode.
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
The Release configuration sets `com.apple.developer.icloud-container-environment` to `Production`, so the wall (Release, by cable) and family phones (TestFlight) meet in the same place.
Debug builds, simulators and tests stay on Development.
This is experiment S4, and it is confirmed on real devices before M2 invites anyone.

Production only accepts record types that were deployed to it.
Before a release that adds tables or columns, a Debug build writes one row to every table on Development, and the schema is promoted to Production with `cktool`.
A script does both, so a release cannot forget it.

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

## Status the UI can show

`SyncStatus` is one of: off, no iCloud account, up to date (with the last time), syncing, waiting (offline, with the last time), paused because iCloud is full, or needs a decision (account changed).
The wall shows it only in Settings, plus a dot on the gear when it has been stuck for an hour (journey D3).

## A fresh install looks for a household first

A new or wiped device signed in to an account that already has a household must not walk through "create a household".
On first launch the app starts the engine and waits briefly for the first fetch.
If a household arrives, it opens it.
If none arrives, it shows the usual welcome.
This is also what makes the M1 gate, "a wiped device gets the whole household back", a real user journey.

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
Photos and "a fresh install looks for a household first" come in a later step.

### The engine

- The mirrors are `SyncMirror.Household`, `SyncMirror.Person` and so on, and `SyncMirror.engine(for:delegate:)` hands all nineteen to `SyncEngine`.
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
- The dot on the gear for sync stuck an hour (journey D3) is not built yet; nothing about sync appears anywhere on the wall but Settings.

### Project

- The Release configuration sets the container environment to Production and Debug to Development through a build setting in the entitlements.
- `aps-environment` is `development` in both: cable installs are development-signed, and an App Store or TestFlight export rewrites it to production.
- Command-line builds need `-skipMacroValidation` for SQLiteData's macros; the scripts pass it.

### Tests

- SQLiteData's stand-in for iCloud refuses more than 200 records in one request, where the real `CKSyncEngine` splits them into batches itself, so the sync tests fill each table with a few rows rather than the sample household.
- Account events are given to `SyncController` directly, as the engine's delegate would, since the stand-in's controls are internal to its package.
