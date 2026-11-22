# Add and edit, in your real calendar

Step 3 of the family calendar MVP (docs/proposals/family-calendar.html, "The idea", the "New event" frame, "Hard cases", "The MVP" item 3), on the shared calendar (docs/design/calendar-shared.md) and the phone's Calendar tab (docs/design/calendar-phone-tab.md).
Porchlight starts writing to EventKit here: an event added in Porchlight is a real event in a real calendar, so it is in Apple Calendar and on a watch, and comes back to every device through step 1's passing on.
No "Maybe", no "Who's on it", no hand-off through a phone for the wall.

## The home calendar

The household chooses one home calendar, once: a shared Google or iCloud calendar it already has, or a new one.
It is a real, writable calendar that several of the household's devices see, each under its own local `calendarIdentifier`, which differs from device to device and can't be shared.

So the choice has two halves:

- **The household's**: one synced record, `homeCalendar`, naming the calendar by what every device can see of it: its title and its account kind ("Family", "Google"), who chose it and when.
- **Each device's**: which of its own calendars that is, kept on the device in `calendarSource` (a new `isHome` flag, never synced, as the rest of that table).

A device finds its half by itself: when the household's choice arrives or changes, or a calendar appears, it looks among its own writable calendars for the one with that title and account kind.
Exactly one: that is it, silently.
None: this device doesn't have the home calendar; it can still read everyone's events, but adds nothing ("Add events from a phone that has Family (Google)").
More than one (two calendars of the same name in one account): the Calendars page asks once which it is, and remembers.

Choosing: the phone's Calendars page and the wall's calendar settings list this device's writable calendars under "Home calendar", and "New calendar named Home" which makes one in the device's default account (iCloud where signed in) through EventKit.
The choice can be changed at any time; events already added stay where they are.
The proposal's step: "Choose a home calendar once" is asked the first time someone taps "+" with no home calendar chosen, as a short sheet, rather than in onboarding.

## Adding

"+" in the phone's Calendar tab opens the one-line sheet; the wall's calendar has "+ Add" when its own home calendar is found and writable.
On a wall without it, in its place: "To add an event, use a phone that has Family (Google)."

The line ("Leo dentist thu 4pm") is read on the device with no network and no model (`EventLine.read`):

1. Dates and times by `NSDataDetector` on the line, with the household's calendar, time zone and the pinned clock as the reference date; then simple rules the detector misses or gets wrong for a family calendar: a weekday alone is the next one (today counts if the time is still ahead), "tonight" is 7 PM today, "noon", "lunch" (12:30), "dinner" (6:30 PM), a bare hour from 7 to 11 without "am" is morning and from 1 to 6 is afternoon ("soccer 4" is 4 PM), "all day".
2. A range ("4-5pm", "4pm to 6", "from 4 for 2 hours") sets the end; otherwise an hour, or all day for a date with no time.
3. A person's first name, at the start or after "for", sets "For" and stays in the title ("Leo dentist" stays "Leo dentist"; the household reads it that way on the wall).
4. What remains, trimmed of the date words, is the title, its first letter capitalized.

The sheet shows "Reads as Leo dentist · Thursday, Nov 26 · 4:00 PM" as you type, and below it every field the reading filled, each editable: For (the household's people, or Everyone), When (start, end or all day), Repeats, Where, Notes, and "Saved in Family · Google".
Nothing is saved before Add, and the reading never changes a field after the person has edited it.

Repeats offers what EventKit's simple rules do exactly: Never, Every day, Every week, Every 2 weeks, Every month (on that date), Every year.
An event repeating some other way, made elsewhere, shows its own words read only ("Repeats: custom") and is kept as it is when edited.

## For whom

An event's owner today is whoever its calendar belongs to.
A home calendar is everyone's, so an event in it needs its own "For": Porchlight's own fact about a real event.
It can't live in the event: EventKit has no field for it, a note or URL would show in Apple Calendar and in Google, and other people's devices couldn't write it.

So it is a small synced record, `eventFor`, one per event series, keyed so every device finds the same one:

- id derived from the household and the event's match key (`CalendarPassOn.matchKey`, the hash of the id iOS shares across devices), so two devices that set it write the same row and the last one stands;
- the people it is for, as their ids (empty is everyone);
- when it was set, and by whom.

Showing: an event's owners are its `eventFor` people when there is one, else its calendar's owner, as today.
That holds for every event, not only home calendar ones, so "For" can be set on any event a device shows whose match key it has; it is the household's view of the event and changes nothing in the real calendar.
An event with no match key (a calendar that doesn't share ids, which home calendars do) can't be given a "For"; the sheet says so instead of offering it.

## Editing and deleting

On the device that has an event's calendar and may write it (`EKCalendar.allowsContentModifications`), the event's page has Edit and Delete, for any event there, not only ones Porchlight made.
Edit opens the same sheet with the event's fields; the line at the top is then not shown.
For a repeating event, both ask "This event" or "This and future events" and save with `EKSpan.thisEvent` or `.futureEvents`; nothing silently changes the whole series.
Delete asks once, and "Undo" puts back what it took (title, times, place, notes, repeat, calendar) as a new event, with the same "For".

On every other device the page stays read only and says whose device can change it: "Sam's iPhone can change this."

## The wall

The wall's calendar gains "+ Add" in its header when the iPad has the home calendar and can write it, opening the same sheet at the wall's size with big person chips.
Otherwise there is no button, and the empty space under the header says "Add events from a phone that has Family (Google)."
Edit and delete on the wall follow the same rule as any device: only for events in calendars the iPad has and can write.

## Words that become false

`NSCalendarsFullAccessUsageDescription` says Porchlight only reads calendars and never changes them.
It becomes: "Porchlight shows the calendars you choose, on Today and on your household's wall. It adds or changes an event only when you do, in the calendar you choose."
The phone's Calendars page and the wall's calendar settings and onboarding ("Read-only. Porchlight never changes your calendars.") say the same in their own words.

## When it goes wrong

- **The home calendar became read only or was removed** (unshared, account signed out): "+" opens a line saying so ("Family (Google) can't be added to on this iPhone any more") with "Choose another home calendar"; nothing is written anywhere else silently.
- **No calendar access**: "+" leads to the Calendars page, which explains before asking, as today.
- **The write worked but passing on is delayed** (offline, iCloud slow): the event is in this device's calendar and shows here at once, from EventKit; the others see it when this device next passes on, and "Sam's calendar, updated Tuesday" says so if that takes a day.
  If the home calendar is shared through Google or iCloud, the other devices that have it see it from their own EventKit sooner, and show it once (step 1's matching).
- **The same event edited on two devices**: each writes to its own copy of the real calendar; the calendar's own service (Google, iCloud) decides, and every device then shows what it has.
  Porchlight adds no merging of its own. Two devices setting "For" at once: the last write stands, as every Porchlight field.
- **A save fails** (EventKit's error): the sheet stays open with what was typed and says why in a line.

## Records

Two synced tables, under the household; the schema goes into `Config/cloudkit-schema.ckdb` with step 1's, so one deploy can cover both:

```
household
├── homeCalendar   one per household; id derived from the household
│                  title, accountKind, chosenById (a device id), chosenAt
└── eventFor       one per event series that has been given a "For"
                   id derived from the household and the match key
                   matchKey, personIds (comma-separated person ids, '' for everyone), setById, setAt
```

Both hang off the household, which every device has, so an older build keeps them waiting and an updated one puts them in at once.
`calendarSource` (device only) gains `isHome`.

## Tests

- `EventLineTests`: a table of real phrases on the pinned clock: weekdays and "next Friday", "tomorrow", "tonight", times with and without am or pm and the bare-hour rule, 24-hour times, ranges and durations, dates across the year's end, all day, a person's name at the start and after "for", both first weekdays, and a 12- and a 24-hour phone.
- EventKit stays behind `CalendarProvider`, which gains writes (save, delete, make a calendar); `FakeCalendarProvider` records them, and the store's add, edit, delete, undo and "this and future" are unit tests against it.
- The home calendar's matching (one, none, two candidates; title or account changed; read only) and "For" precedence are unit tests; `homeCalendar` and `eventFor` across two devices and an older build join `SharedCalendarSyncTests` and `OlderBuildSyncTests`.
- UI: one journey adding an event on the phone, one editing one (with "This and future events"), one adding on the wall.
