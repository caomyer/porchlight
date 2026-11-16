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
