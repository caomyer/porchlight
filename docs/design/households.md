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
A household started on this device becomes current too, and so does the newest accepted invite; one arriving through sync never takes over.
Switching between several is journey A5, below.

### Two households (A5)

A phone can belong to several households: a co-parent's, a grandparent's, a neighbor's pets.
The M5 gate is that two households under different Apple IDs never mix, so the design starts from scoping, then the screens.

What one device holds:

- Each household is its own tree of rows under its `household` row, in its own iCloud zone: ours in our private database, a joined one in its owner's zone through the shared database.
  A new row inherits its parent's zone (SQLiteData's triggers), so a row written into a household goes to that household's zone; `TwoHouseholdZonesTests` checks it.
- `currentHouseholdId` names the one on screen; every screen reads only that household (`Household.current`), and switching rewrites that one value, so every store's observation runs again.
- "Me" is per household (`DeviceSettings.me(in:)`, keyed by household id): James can be James in both, or Mia in one and Mom in the other.
- This device has a row in each household it opened, with the same install id and a different row id per household (`Device.id(householdId:install:)`).

The screens:

- You lists "Your households" when there are two or more: each with "You are James · 2 people", a tick on the one showing, one tap to switch (the You sheet closes, so the tabs show it), and "Join or start another".
  With one household, You keeps its usual rows and adds "Join or start another" under them.
- Today's header names the household, tappable to switch, only when there are two or more ("Sunday · Grandma Rosa's ▾").
- Today, Food, Lists, Glow and the rest show one household at a time; the tab you were on stays.
- "Join or start another" offers starting one here (the phone's own setup, with "Cancel" and your name filled in) or joining one, by an invite or the owner's code.
  A household started here shows at once; one joined shows once it arrives, as for a first join.
- Leaving or being removed from the household showing shows the removed screen; "OK" shows the other household.
- A shared screen shows one household and never offers the switcher.

Reminders come from every household this phone belongs to, for "me" in each, and, when there are two or more, each title starts with its household's name ("Grandma Rosa's · Water the tomatoes"), with one notification thread per household.
A reminder's action logs into its own household, for "me" there, whichever household is showing.

The audit (every read and write, checked for the household it touches) found these, all fixed with tests in `TwoHouseholdsTests`:

1. Stamping a row with "this device" used the household showing, so a write into the other household (a reminder's action, a widget's button) named this device's row in the wrong household.
   `stamp(in:)` now takes the household the row is written into.
2. Reminders were planned for the household showing only, so switching removed every reminder of the other household.
3. A reminder's action read the household showing, so acting on the other household's reminder logged nothing.
4. The evening chores reminder had one id per day, so two households' chores on the same day replaced each other; the id now includes the household.
5. The companion snapshot read every household's care-log people, then used only its own; it now reads only its own.
6. A care log could credit people from another household (nothing checked); the write now refuses anyone who doesn't live in the routine's household.
7. Checking off a chore from a widget or Siri credited "me" of the household showing even for a chore of the other household; it now uses the chore's household and "me" there.
8. Starting a household on a phone that already had one left the old one showing, so setup continued out of sight; a household started here now becomes current.
9. Switching to a household in another time zone left "today" on the old one for up to 30 seconds; it now follows at once.

Widgets and Siri follow the household showing.
Per-widget household choice (the atlas's "a widget shows the household it was set up for") is left out: a widget configured for a household that isn't showing would need the summary of every household, and a household that left would leave widgets behind showing nothing.
When there are two or more, the medium widget's title is the household's name, and Siri's answers say which household ("At Grandma Rosa's · For James at 6:05pm").
A widget button tapped after a switch, before the widget redraws, still logs where it said: the routine's own household, for "me" there.

What only two real Apple IDs can prove:

- a household joined from another Apple ID lives in that owner's zone, and a row written into it reaches the owner's devices and never ours;
- switching on a phone never makes the wall or the other household's devices show anything of the household not theirs;
- removing this phone from one household leaves the other's sync untouched;
- reminders of both households arrive, each named, and the actions log into the right one with the app closed.


## Sharing

`HouseholdSharing` is a small protocol with a live implementation over the engine and CloudKit, and a fake for tests.

- `participants()` reads the household's share: owner, accepted and pending participants, with names.
- `invite()` returns what the system share sheet needs.
  The standard `UICloudSharingController` (SQLiteData's `CloudSharingView`) sends the invite by Messages, Mail or a copied link, and manages who has access.
  It is Apple's own UI for this, it handles every edge of the sharing rules, and people have seen it in Notes and Reminders.
- `openSeat()`, `seatState()` and `closeSeat()` make, follow and put away one private seat for a join code; `publicLink()` and `closePublicLink()` are the safety net for a share left public; see "The join code".
- `accept(_:)` accepts an invite that opened the app.
- `remove(_:)` removes a participant, for the owner.

Participants get read and write access.

### The join code (experiment S2, answered)

On the first two-Apple-ID test, Carol joined by scanning the wall's code, and the moment the code sheet closed her phone showed "removed".
That is what the platform says it does; the earlier design (a QR of the share's public link, closed again when the sheet closed) assumed the opposite.
From the iOS 26.2 SDK's CloudKit headers:

- `CKShare.publicPermission`: "CloudKit removes all public participants when you save the share if you set the property's value to none."
- `CKShare.addParticipant` and `removeParticipant`: "To modify the list of participants, a share's publicPermission must be none. You can't mix and match public and private users in the same share."
- `CKShare.Participant`: anyone with the URL of a public share joins with the `publicUser` role; "CloudKit removes any pending participants if the owner changes the share's publicPermission. CloudKit removes all participants if the new permission is none."
- `CKShare.Participant` roles: the owner "can invite private users"; a private user "can access the share"; only an administrator, a role that needs iOS 26, "can add and remove participants".
- `CKShare.Participant.oneTimeURLParticipant()` (iOS 18): "When a participant's email address / phone number / userRecordID isn't known up-front, you can add a oneTimeURLParticipant to the share. Once you save the share, you can get a custom invitation link or one-time URL for the added participant via `CKShare.oneTimeURL(for:)`. Any recipient user can use this custom link to fetch share metadata and accept the share."
  A pending one-time participant has empty name components and no lookup info.
- `CKShare.oneTimeURLForParticipantID:` (iOS 18): "One-time URLs are stable, and tied to the associated participantIDs as long as the participant is part of the share. After share acceptance, the one-time URL becomes functionally equivalent to the regular URL."
- Access requests (`allowsAccessRequests`, `requesters`, `CKShareRequestAccessOperation`) need iOS 26 on both sides.

So a household open to whoever holds a link can't also have members invited by name, and closing that link removes everyone who came through it.
The decision: Porchlight never sets `publicPermission` to anything but none.

- A join code is one private seat: `oneTimeURLParticipant()` with read and write, added and saved by the owner's device that shows the code, one seat per showing.
  The code is that seat's one-time URL; the first person who opens it takes the seat and is a private participant like anyone invited by name.
- The sheet follows the seat every few seconds: "One person can join with this code. It works until you close this.", then "Carol joined with this code." once her phone has said who she is.
- Putting the code away removes the seat when nobody took it: the share is fetched fresh, the participant with that `participantID` is removed only while its status isn't accepted, and the share is saved.
  Removing a participant from a private share touches no one else, so accepted members are never affected (`removeParticipant` names exactly one participant).
- Only the share's owner can add participants, and only a device with iOS 18 can make a seat.
  So "Show a code" appears only on the owner's own iOS 18 device; the iPadOS 17 wall and members' phones show one line instead: "To show a join code, open Porchlight on James's iPhone: You, Invite someone, Show a code.", which on a member's phone starts "Only James can add people to the household."
  A member's device shows no invite button at all, since the share wouldn't let it add anyone.
- The phone's welcome says where the code is: "On the household owner's iPhone, open Porchlight: You › Invite someone › Show a code, and point the Camera app at it."
- A safety net for shares left public by the earlier code: when the owner's device reads the share and finds its link open, it closes it at once if nobody joined through it; if someone did, Family & devices and the phone's invite page say who and offer "Close the link…", which first says who closing it removes and that they can be invited again by name.
  Nothing is ever closed by itself while someone is in through it.
- The share's operations go to the sync log: a seat added or removed unclaimed, the link closed, a participant removed, and participants counted by role and status (owner, private, link; joined, pending, removed), never who.

The member's side: a phone that was removed shows the removed screen, starts over on "OK", and can join again; the household arrives through the engine as on a first join, and a "me" chosen for that household before is kept, since it is the same household.
The owner's side: once the share is known, a personal device whose iCloud user is neither the owner nor someone who joined no longer counts as having the app; the person shows "Not joined: Carol's iPhone no longer has access", and invites from there work as for anyone.

Still to prove on devices:

- a one-time URL made on James's iPhone, scanned by a second Apple ID, joins as a private participant, and the sheet sees it taken;
- putting the code away untaken removes the seat, and the person who took a seat before stays;
- a member's phone can't add participants (the headers say only the owner, or an iOS 26 administrator, can), and the share sheet there offers no invite;
- the safety net on the wall's existing share, which was public during the first test.

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
- The removed screen has only "OK"; on a phone the welcome after it offers "Start a household" (A2).

### Sharing

- `HouseholdSharing` is a protocol with `LiveHouseholdSharing` and `FakeHouseholdSharing`; `HouseholdSharingModel` wraps either for the screens and keeps the last participants it read, so they show offline.
- The live sharing creates or saves the share with SQLiteData's `share(record:configure:)` on the household's mirror, sets the share's title to the household's name, and presents `CloudSharingView` with `[.allowReadWrite, .allowPrivate]`, so invites go to the people they're sent to and everyone can write.
- The join code adds a one-time participant to the share, saves it to the private database, and shows the participant's one-time URL as a QR code (see "The join code").
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
  It is a quiet footnote in the muted color, with no outline or fill: with phones in use nearly every row carries one, and only the one-time glow and the toast should draw the eye.
- The sync line in Settings (D2) names the newest change from another device; the storage meter is later.

### The phone

- E5's banners come from `SyncStatus`: a decision to make (which opens You, where the choices are), signed out (which opens iOS Settings), the owner's iCloud full, and offline once sync has been stuck an hour.
  "A newer Porchlight elsewhere" needs version tracking that doesn't exist yet, so it is left out.
- You shows the household, Invite someone, the people and their devices, this device's name and role, and changing who you are; a sync decision shows there too.
- "Someone new" on the invite page adds the person, then opens the same sharing sheet.
- The join, removed and welcome screens stand outside the tabs, so besides the kit's paper behind the status bar they clip their scrolling content to the safe area; the paper alone didn't keep large text out of the clock there.
- None of the new phone screens raises a toast, so none needed `ToastCenter.showAfterSheet`; counts that can be one ("1 person", "1 so far") were checked.
- The sharing sheet is presented from the You sheet itself, not from the invite page pushed inside it: a sheet presented from a pushed page took the You sheet down with it when it closed.
- The QR code is drawn with Core Image off the main thread, once per link: the first Core Image context takes seconds to start on a simulator, and drawing it in the view's body froze the screen meanwhile.
- A sample or reset launch (`-sampleHousehold`, `-resetData`) also forgets this device's name and role, so a UI test that changes them never leaks into the next one.

### Leaving and starting a household on a phone (M4)

- `HouseholdSharing` gained `leave(_:)`, for a member: the live sharing deletes the household's share from this user's shared database, which takes them off it and leaves the owner's household and everyone else's access alone; then it fetches changes, so the engine sees the shared zone go and removes the household from this device, as it does when the owner removes someone.
  The owner can't leave (the household's zone is theirs), and the phone says why instead of offering it.
- `HouseholdSharingModel.leave` runs inside `AppModel.removeHouseholdHere`, so the household is forgotten first and its going isn't shown as being removed; a failure (offline) leaves everything as it was.
- The fake records "leave", can fail a set number of times as if offline, and takes the household out of the database through `onLeave`, which `-debugSharing member` wires to deleting it, as the engine would.
- Removing someone from the phone uses the same `HouseholdSharingModel.remove` as the wall, and the same words (`RemoveDevicesWords`).
- A household started on a phone (A2) is created by `HouseholdSetup`, the model the wall's first run uses, and is the share's root like any other, so a wall that joins it, or opens with the same Apple ID, finds an ordinary household.
- The removed screen keeps only "OK": after it, the welcome offers "Start a household".

### What only real devices can prove

The live sharing code cannot run in tests or unsigned simulator builds; these lines are on the M2 device checklist:

- `SceneDelegate` receiving the share at a cold start and while running, with the SwiftUI life cycle.
- `HouseholdInvitation(metadata:)`: the share's title, the owner's name, and the household id from `hierarchicalRootRecordID`.
- `engine.acceptShare(metadata:)` and the household arriving in time on the joining phone.
- `LiveHouseholdSharing.share`: creating the share and the invite through `CloudSharingView`; `openSeat` and `closeSeat` for the join code (a one-time participant, iOS 18).
- `latestShare`: reading the cached share from the metadata and refreshing it from the private or shared database.
- `HouseholdMembers(share:currentUserName:)`: participants' names, statuses and record names, including `__defaultOwner__`.
- `remove(_:from:)`: removing a participant and that ending their access (experiment S2).
- A deleted shared zone removing the household on the participant's device, so the removed screen shows.
- The quota event arriving from the shared database on a member's device.
- `leave(_:)`: deleting the share from a member's shared database taking them off it, the engine then removing the household from their device, and the owner and other members keeping it.
- A household started on a phone and then opened by a wall signed in to the same Apple ID, or joined by one.

### Merging the phone's everyday tabs

- "calendar v2: just me" (the phone's device-local `calendarSource.isPersonal`) is registered after "sync v2" and "households v1".
  Each of the three changes different tables, and GRDB runs every unapplied migration in registered order, so a simulator that already ran the phone's migration still gets the other two, and one that ran ours gets the calendar's; the wall has run none of them.
- The phone's cached sample photos now cache the bytes `MealPhotoImaging.prepare` makes, and sample meals store them as photo rows, as camera shots are; the cache key moved to `v2` because the files differ from the phone branch's.
- The phone's new screens (Pitch in, Lists, Glow, the care sheet) write through the same store and database functions, so their rows are stamped too; `PhoneStampTests` checks every stamped table through those paths.

### Where the household lives, said truthfully

- Every place that names where the household is stored (the wall's Family & devices card, the phone's You sheet and invite page) reads it from `HouseholdHome`, which follows sync's state rather than the share alone.
  With sync off it says "on this iPad only"; signed out or waiting for a choice, "on this iPad until …"; syncing, "stored in your iCloud" on someone's own device, or the owner's name on a shared screen and on members' devices.
- While sync can't carry an invite, Invite and the code are disabled and a line says why; with sync off by choice, "Go to iCloud sync" brings the wall's switch into view.
  The phone gained its own sync switch in You, so the same advice has somewhere to go there too.
