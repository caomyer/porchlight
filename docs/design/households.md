# Households, devices and joining: the M2 design

This is the technical design for the sharing half of milestone M2 (see `docs/proposals/companion-ux.html`, journeys A1, A3, A4, D1, D2, E5).
It builds on `sync-foundation.md` (the data shape), `sync-icloud.md` (the engine) and `phone-shell.md` (the phone).

## What exists already

- Every synced table hangs off `household`, the one shareable root.
- `SyncController` owns the engine and publishes `SyncStatus`.
- `DeviceSettings` keeps this device's role (shared screen or personal) and "me" per household, on the device.
- SQLiteData can create a share for the household row (`engine.share(record:)`) and accept one (`engine.acceptShare(metadata:)`).

## The model

| Thing | Where it lives | Notes |
|---|---|---|
| Household | synced root | Shared as a whole. A device can hold several. |
| Person | synced | Someone in the household, with or without a device. |
| Device | synced, new table `device` | One row per install that has opened the household. |
| Owner | read from the share | Never stored (sync-foundation rule 9). |
| Current household | on the device | Which household this device is showing. |
| Role, "me" | on the device | As today, and mirrored into this device's `device` row so others can see it. |

### The `device` table

`device` is a child of `household`.

| Column | Meaning |
|---|---|
| `id` | Derived from the household id and this install's own random id, so one install has one row per household. |
| `householdId` | Its one foreign key. |
| `name` | "James's iPhone", "Hallway iPad". Starts as the system's device name and can be edited. |
| `role` | `shared` or `personal`. |
| `personId` | For a personal device, who it belongs to. A plain id. |
| `userName` | The iCloud user's record name, so a device can be matched to a participant of the share. |
| `createdAt`, `seenAt` | When it first opened the household, and the last day it was used (written at most once a day). |

The install's random id is created once and kept in UserDefaults.
A device writes its own row when it opens a household and whenever its name, role or person changes.
It never edits another device's row, except that the owner can delete one when removing someone.

"Members" are not a table.
A person is shown as having joined when a personal device row points at them.
A person shown as invited but not joined comes from the share's pending participants.

### Where a row came from

`careLog`, `journalEntry`, `choreCompletion`, `rewardRedemption` and `listItem` gain a nullable `deviceId`, a plain id.
Every write stamps it with this device's row id.
The wall shows "from Mia's phone" on a row whose device is personal and belongs to someone, and nothing otherwise.
Rows from before this change have no device and show no tag.

### The current household

A small device-only table, `deviceState(key, value)`, holds `currentHouseholdId`.
It is a table, not UserDefaults, so every read that asks "which household?" sees it inside its own transaction and observations update when it changes.
`Household.current` returns that household when it exists, else the oldest, as today.
When a household arrives on a device that has none, it becomes current.
The switcher for people in several households is M5; until then the newest accepted invite becomes current.

## Sharing

`HouseholdSharing` is a small protocol with a live implementation over the engine and CloudKit, and a fake for tests.

- `participants()` reads the household's share: owner, accepted and pending participants, with names.
- `invite()` returns what the system share sheet needs.
  The standard `UICloudSharingController` (SQLiteData's `CloudSharingView`) sends the invite by Messages, Mail or a copied link, and manages who has access.
  It is Apple's own UI for this, it handles every edge of the sharing rules, and people have seen it in Notes and Reminders.
- `joinCode()` returns the share's link for a QR code, after making the share joinable by anyone with the link.
  `endJoinCode()` turns that off again when the QR screen closes.
- `accept(_:)` accepts an invite that opened the app.
- `remove(_:)` removes a participant, for the owner.

Participants get read and write access.

### What still needs real devices (experiment S2)

Two things cannot be proven without two Apple IDs on two devices, and the code is written so either answer fits:

1. Whether someone who joined through the QR link keeps access after link-joining is turned off again.
   If they do not, the QR screen leaves link-joining on, and says so.
2. That removing a participant ends their access on their device.

Both are on the M2 device checklist.

## Joining (A4)

1. The invite link opens the app, or the App Store and then the app.
   The scene delegate receives the share's metadata.
2. **Join?** shows the household's name, who invited you and whose iCloud holds it, from the metadata, before anything is accepted.
3. On "Join", the share is accepted and the household syncs in.
4. **Which one is you?** lists people without a personal device first, people who already have one dimmed, and "I'm new here", which adds a person.
   Someone whose iCloud account already has a device row in this household skips this step and keeps the same person.
5. The app opens Today.
   Photos stream in behind it.

If accepting fails offline, a banner offers to try again and nothing is half joined.

The phone's welcome screen for a device with no household now explains both ways in: open an invite link, or scan the code on a shared screen with the Camera app.

## The wall

- **Settings, Family & devices (A3, D2):** everyone in the household with their state (this device, has a phone, invited, not joined), this device's name and role, an Invite button, and "Show a code to join" which opens the QR screen.
  The owner can remove a participant from here.
- **Onboarding (A1):** two new steps on iPad: this device's role, and where the household lives (which iCloud account, and that it grows mainly with photos).
  An existing household that upgrades skips both and defaults to a shared screen.
- **Arrivals (D1):** a row written by a personal device carries its tag.
  When such rows arrive while the wall is showing, the row glows once and one short toast names who did it.
  A burst after being offline gives one summarizing toast, not one per row.
  Nothing loops, and the wall's rest mode is respected.

## The phone

- **Banners (E5):** one banner at a time at the top of Today, driven by `SyncStatus`: offline for a long while, paused because the owner's iCloud is full, signed out, or a decision needed.
  Removed-from-household is its own full screen.
- **You:** this device's name, the household's people with their devices, and Invite.

## Tests

- Device rows: one per install per household, updated on change, never duplicated.
- Stamping: every write path sets `deviceId`; the tag appears only for personal devices.
- Current household: arrives, becomes current, survives relaunch; falls back when it is removed.
- Joining with the fake: preview, accept, pick a person, "I'm new here", already-known account, failure and retry.
- Family & devices with the fake: each state renders, invite and remove call through.
- Schema rules and mirrors cover the new table and columns.
- Screens are covered by UI tests using the fake, driven by debug launch arguments.

Real sharing between two Apple IDs is verified on devices with the M2 checklist.

## Implementation notes

Choices made while building M2's sharing half, where the design above left room or did not fit the code or the library.

### Data

- The migration is "households v1: devices and where rows came from", registered after "sync v2".
  Sync had never been on anywhere, so it is a schema migration that adds the tables and columns directly and writes no rows.
- `device` gained one column the design didn't list, `model` ("iPhone" or "iPad"), nullable.
  The tag has to say "from Mia's phone" for an iPhone and "from Mia's iPad" for a personal iPad, and nothing else in the row knows the kind of device.
- `role` stores the app's own `DeviceRole` raw values, `sharedScreen` and `personal`, as UserDefaults already did; a value a newer version writes reads as a shared screen, which never credits anyone by mistake.
- `deviceState` is keyed by `key`, not by a UUID `id`, because it is a device-only key-value table; the schema rules test knows it as device-local.
  It holds the current household's id and name, the owner's name of a joined household (for the removed screen), and the restore token.
- A device's row id is `ID.derived(householdId, installId)`; the install id is a random UUID kept in UserDefaults under `device.installId`, and `AppDatabase` carries it.
- Stamping happens in the write layer: `AppDatabase.stamp(_:)` names this device's row in the current household, and each write path that adds a stamped row calls it once inside its own transaction (`insertLog`, `checkOff`, `creditChore`, `cashInReward`, `addListItem`, `addMeal`).
  Rows the engine writes when they arrive from iCloud keep the device that wrote them.
  Re-crediting an existing completion keeps its original device: the row still came from where it was first written.
- iOS no longer tells apps the name a person gave their device, so a device's name starts as "Mia's iPhone" on a personal device and "Shared iPad" on a shared screen, and can be changed in Settings or You.
- `ThisDeviceRow` writes the row whenever the household, the name, the role, the person or the iCloud account changes, and when the app comes to the front; `saveThisDevice` writes only when something changed or a new day began, so an idle device uploads at most once a day.

### The current household and a household that leaves

- `AppModel` remembers the current household (`rememberCurrentHousehold`) each time the household changes: the first household a device has becomes current, and a later one doesn't take over.
  Accepting an invite chooses the new household explicitly.
- A household that disappears while chosen, which is what SQLiteData does when its shared zone is deleted (the owner removed this device or stopped sharing), shows "You're no longer in …" (A6) on the phone and the wall.
  "OK" forgets it, and the oldest household left becomes current, or the welcome shows.
- The device's own removals ("Remove it from this iPad", "Use what is in iCloud") forget the household first and hold the remembering while the engine deletes, so they never read as someone else removing it.
- The removed screen has only "OK": starting a household on a phone (A2) isn't built.

### Sharing

- `HouseholdSharing` is a protocol with `LiveHouseholdSharing` and `FakeHouseholdSharing`; `HouseholdSharingModel` wraps either for the screens and keeps the last participants it read, so they show offline.
- The live sharing creates or saves the share with SQLiteData's `share(record:configure:)` on the household's mirror, sets the share's title to the household's name, and presents `CloudSharingView` with `[.allowReadWrite, .allowPrivate]`, so invites go to the people they're sent to and everyone can write.
- The join code sets `publicPermission = .readWrite` through the same call and shows the share's URL as a QR code; putting the code away sets it back to `.none`.
  `JoinCodePolicy.joinersKeepAccess` is the one switch for experiment S2: if link joiners lose access, set it to false, and the code stays joinable and the screen says so.
- Removing someone fetches the share fresh, removes the participant, saves the share to the private database, and fetches changes so the engine caches the new share; then the owner deletes that person's device rows, and their person stays.
- Participants are matched to people through device rows: a device carries its iCloud user's record name, and the share's participants carry theirs.
  On the owner's own devices a share may name its owner `__defaultOwner__`, so the current user's participant takes the record name the device read itself.
- An invite that names nobody yet is matched to a person by first name ("Mia" for an invite to Mia Cao); otherwise it is listed on its own as invited.
- The owner's name comes from their person, through their devices, else from iCloud's name for them.
- A full iCloud now pauses sync from either database: the owner's devices hit it in the private database and everyone else's in the shared one.
- The wall's Family & devices shows the code behind "Show a code to join" rather than always, because the code lets anyone who sees it join (A3's states); Remove sits on each joined person's row for the owner.

### Joining

- The app keeps the SwiftUI life cycle; `AppDelegate` (through `UIApplicationDelegateAdaptor`) gives every scene `SceneDelegate`, which hands invites to `ShareInbox` from `windowScene(_:userDidAcceptCloudKitShareWith:)` and, at a cold start, from `connectionOptions.cloudKitShareMetadata`.
  Nothing else about launching, the kiosk mode or the wall's look changes.
- The preview reads the household's name, the owner's name and the household's id from the share's metadata before anything is accepted; the household's people aren't in the metadata, so the preview shows no avatars.
- `JoinFlow` accepts, then waits up to a minute for the household's row before choosing it, so a join that fails at any point leaves nothing chosen; "Try again" accepts again.
- The reminders step (`a4remind`) is left out, as reminders don't exist yet, so the flow has two dots.
- "Bringing everything in" counts what has arrived from the database (people, walks and meals, photos whose thumbnail is here out of photos known), so it never guesses a total; it has no spinner.
- An iPad that joins is a shared screen by default and skips "Which one is you?".
- "Which one is you?" now lists people without a personal device first, then people with one, dimmed and still pickable, then "I'm new here", everywhere it shows, not only when joining.

### The wall

- Setup has eight steps: the role is the second, and iCloud the last; "Invite phones now" finishes setup and opens Settings on Family & devices.
  The iCloud step doesn't name the account's owner, which an app can't read; it says the household uses the iCloud account on this iPad.
- Arrivals (D1) are rows stamped by another device that is someone's own, newer than the last day, that weren't there when the wall started watching.
  The first look only notes what is there; while the photo frame shows, arrivals are noted quietly and never announced later.
  One arrival names who and what ("James walked Yo-Yo · from their phone"); several in one change give one summary ("3 updates from James's and Mia's phones").
  The toast goes after six seconds and the row's glow fades once; nothing repeats.
  A row that arrives before its device row would be noted without a toast.
- The timeline's tag shows on care, meals and chores; lists and cash-ins aren't on Today.
- The sync line in Settings (D2) names the newest change from another device; the storage meter is later.

### The phone

- E5's banners come from `SyncStatus`: a decision to make (which opens You, where the choices are), signed out (which opens iOS Settings), the owner's iCloud full, and offline once sync has been stuck an hour.
  "A newer Porchlight elsewhere" needs version tracking that doesn't exist yet, so it is left out.
- You shows the household, Invite someone, the people and their devices, this device's name and role, and changing who you are; a sync decision shows there too.
- "Someone new" on the invite page adds the person, then opens the same sharing sheet.
- The sharing sheet is presented from the You sheet itself, not from the invite page pushed inside it: a sheet presented from a pushed page took the You sheet down with it when it closed.
- The QR code is drawn with Core Image off the main thread, once per link: the first Core Image context takes seconds to start on a simulator, and drawing it in the view's body froze the screen meanwhile.
- A sample or reset launch (`-sampleHousehold`, `-resetData`) also forgets this device's name and role, so a UI test that changes them never leaks into the next one.

### What only real devices can prove

The live sharing code cannot run in tests or unsigned simulator builds; these lines are on the M2 device checklist:

- `SceneDelegate` receiving the share at a cold start and while running, with the SwiftUI life cycle.
- `HouseholdInvitation(metadata:)`: the share's title, the owner's name, and the household id from `hierarchicalRootRecordID`.
- `engine.acceptShare(metadata:)` and the household arriving in time on the joining phone.
- `LiveHouseholdSharing.share`: creating the share, the invite through `CloudSharingView`, and `publicPermission` for the code (experiment S2).
- `latestShare`: reading the cached share from the metadata and refreshing it from the private or shared database.
- `HouseholdMembers(share:currentUserName:)`: participants' names, statuses and record names, including `__defaultOwner__`.
- `remove(_:from:)`: removing a participant and that ending their access (experiment S2).
- A deleted shared zone removing the household on the participant's device, so the removed screen shows.
- The quota event arriving from the shared database on a member's device.
