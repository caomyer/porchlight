# One shared calendar

Step 1 of the family calendar MVP (docs/proposals/family-calendar.html, "The MVP").
Every device, each phone and the wall, passes on the calendars chosen on it into the household's shared iCloud zone, so every device shows everyone's events.
Nothing is written to EventKit in this step.

## What each choice passes on

Each calendar on a device has one choice, set on that device only (`calendarSource`, which never syncs):

| Choice | What the household gets | What never leaves the device |
|---|---|---|
| Show everything | Each event's title, place, notes (first 1,000 characters), times | The account it comes from (it can hold an email address) |
| Keep it quiet | The same events, shown as one soft block per person per day ("Alex at work until 5:30"), the events listed on tap | The same |
| Busy only | Each event's times and whether it is all day | Title, place, notes, the calendar's own name, the account |
| Just me | Nothing | Everything; anything passed on before is removed |

"Belongs to" a person or everyone stays as today and is passed on with the calendar.
Today's values migrate: `visibility = full` becomes Show everything, `busy` becomes Busy only, and `isPersonal` becomes Just me whatever the visibility.

The choice is enforced where the record is built (`SharedCalendarRecord.make`, `SharedEventRecord.make`): for Busy only those functions have no title, place or notes to write, and for Just me they return nothing.
Unit tests fill every text field of an event with a marker and fail if the marker reaches any column of any row the publisher writes for those choices.

### A newly seen calendar

A calendar first seen on a device starts as Show everything, and belongs to the guessed owner, as today.
Show everything is the default because the household calendar is the point of the feature, and a family's own calendars (iCloud, Google, school) are what they want to see; a choice that hides by default would leave the wall empty after setup.
The protection is that nothing is passed on from a device until its calendar choices have been seen there at least once (`deviceState`, "calendar choices seen"): the phone's Calendars page and the wall's calendar settings set it when shown.
The phone's first-run explanation names work calendars as the ones to set to Keep it quiet.
A calendar added later, after the choices were seen, follows the default; its row on the Calendars page says what it is set to.

## Tables

Three synced tables, each device writing only under its own `device` row, so no two devices ever write the same row and there are no conflicts to resolve:

```
device (exists)
└── calendarFeed      one per device that passes calendars on; id derived from the device's
    │                 deviceId, passedOnAt, passedOnBy, windowStart, windowEnd, eventCount
    └── sharedCalendar  one per calendar passed on; id derived from (device, calendar id)
        │               feedId, title ('' for Busy only), accountKind, colorHex, ownerId (plain id), choice
        └── sharedEvent  one per occurrence in the window; id derived from (calendar row, occurrence)
                         sharedCalendarId, matchKey, title, location, notes (NULL for Busy only),
                         start, end, isAllDay
```

- `accountKind` is a word, never an address: iCloud, Google, Exchange, Subscribed, Birthdays, On this device.
- `matchKey` is the SHA-256 (first 16 bytes, hex) of the event's `calendarItemExternalIdentifier`, the id iOS means to be shared across devices, so the same invite on two phones has the same key without the raw id (which can name a domain) leaving either.
- All-day events are stored as the household calendar's midnights for the days the device shows, so every device puts them on the same days.
- The parent chain is device, feed, calendar, event: removing a device removes everything it passed on, and a device that updates puts the three new tables in parents first, which is why this step builds on SQLiteData's ordering fix (docs/design/dishes.md, "Why a card photo hangs off the dish").
- Volume: a few hundred occurrences per person in the 104-day window, a few kilobytes each at most.

## Passing on

`CalendarPublisher.publish(trigger:)`, on the device that has the calendars:

1. Stop if the household, this device's row, calendar access, or "choices seen" is missing. Without access, remove the feed (access was taken away).
2. Build the wanted rows: for each calendar the provider has whose choice isn't Just me, its `sharedCalendar` record, and a `sharedEvent` record for each occurrence overlapping 14 days back to 90 days ahead of today, in the household calendar, through `CompanionClock`.
3. In one write, compare with the rows already under this device's feed: delete rows no longer wanted (a calendar set to Just me or gone takes its events with it), insert new ones, update only rows whose content changed, leave the rest untouched.
4. Write the feed row: when (`passedOnAt`), why (`passedOnBy`: change, open, background, day, choice), the window and the count.
5. SQLiteData sends what changed; an unchanged calendar sends one small feed record.

It runs when EventKit says something changed (gathered over two seconds), when the app comes to the front, when a choice changes, at the day's turn (the window rolls), and from a background refresh (`BGAppRefreshTask`, `com.mingyucao.porchlight.calendar.passOn`, asked for again each time, earliest in an hour), which iOS grants when it chooses.
The wall, which is always on, also runs it every hour.

## Showing

`CalendarStore` shows this device's own EventKit events, as today, plus every other device's `sharedEvent` rows:

- A device never shows its own passed-on rows; it already has the events themselves.
- The same event is shown once: two events match when their `matchKey` and start are equal, or, when either has no key, when title, start and end are equal (Busy only events, which have no title, match only by key).
  A match shows one event with each owner's face.
- Keep it quiet events from another device are drawn as one block per owner per day, from the first start to the last end: "Alex at work" with "Until 5:30 PM · 3 meetings", and tapping it lists them. On the device that has the calendar they show in full.
- Busy only events read "Busy", as today.

### How fresh

Every device shows, quietly, "Sam's calendar, updated Tuesday" for any other device whose feed is more than a day old, on the wall's calendar and the phone's Today card.
Sync details lists a line per device: when it last passed its calendars on, why, and how many events, so the numbers from real devices can be read off one screen.

## Removing

- A calendar set to Just me, or removed from the device, is removed at the next pass, events and all.
- Leaving the household removes this device's feed and sends that before leaving the share.
- The owner removing someone's devices removes their device rows, and with them their feeds.

## Older builds

A device on the build before this has none of the three tables.
The sync engine keeps their records in its metadata and syncs everything else as before; when the device updates, they arrive parents first.
An older build can't remove a device that has a feed (iCloud refuses to delete a record that is still a parent); the device comes back there until the remover updates.
`OlderBuildSyncTests` covers both.

## Schema

The three record types go into `Config/cloudkit-schema.ckdb` through `SchemaFileTests`, and into Development with `scripts/cloud-schema.sh import`.
Production needs James's deploy before any build with them reaches TestFlight.
