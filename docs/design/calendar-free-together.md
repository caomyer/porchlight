# Free together

Step 4 of the family calendar MVP (docs/proposals/family-calendar.html, the "Free together" frame and "The MVP" item 4), on the shared calendar (docs/design/calendar-shared.md), the phone's Calendar tab (docs/design/calendar-phone-tab.md) and who an event is for (docs/design/calendar-add-edit.md).
It answers one question: "When are we free?"
It reads only what the device already has and adds no record, so it changes no CloudKit schema.

## What it shows

Today and the next 13 days as the times a household plans things into: each weekday evening, and each weekend day.
A free Tuesday at 5 AM is not a free Friday evening, so time outside those windows is never offered.

One row for each, as the proposal's frame shows: "Tonight" (or "Today" on a weekend day) first, then "Evening" or "Weekend" with the day ("Thu 19").

- **Everyone free from 5:30 PM**, in green, when everyone asked about is free for long enough; a weekend day says "Everyone free all day", "Everyone free after noon" or "Everyone free from 3:00 PM".
  "Nothing planned" under it when nothing at all is in the window.
- Otherwise who isn't free and why, in plain words where it is known: "Sam out" over "Book club, 7:00 to 9:00 PM"; "Alex at work" over "Until 7:30 PM"; "Mia busy" over "6:00 to 8:00 PM" for a Busy only calendar; "Everyone out: Grandma's 80th" when it is the household's; then who is free, "Mia free from 7:30 PM".
- The day's all-day events under the row, for context: "All day: Aunt Rosa visiting" (see "All-day events").

With a person's chip picked it answers for that person alone ("Free from 5:30 PM"); "Everyone" is the household.
Past evenings are not shown.

## The windows

| | Weekday evening | Weekend day |
|---|---|---|
| Window | 5:30 PM to 9:30 PM | 9:00 AM to 9:30 PM |
| Free for | 2 hours unbroken inside it | 3 hours unbroken inside it |
| "From" | the start of the first such stretch | "all day" when the whole window is free; "after noon" when the first stretch starts between 12:00 and 1:00 PM; otherwise the stretch's start |

A stretch starts on a quarter hour: something ending at 5:31 makes the evening free from 5:45.
Friday is a weekday evening like the others.
Which days are the weekend follows the household's calendar and locale (`Calendar.isDateInWeekend`): Saturday and Sunday in the US, Friday and Saturday in Israel.
These are the defaults, kept in one value (`FreeWindows`) that the logic takes as a parameter, so a household setting can change them later without touching the rule; this step adds no setting.
Times are in the household's time zone and calendar (`Household.calendar`), as the rest of the calendar is, and the windows are read off the wall clock of each day, so the day the clocks change is still 9 to 9:30.

Today counts from now: this evening's window starts at the later of 5:30 PM and now, rounded up to the next quarter hour.
A window already over, or with less left than counts as free, is left out: at 8:15 PM there is no "Tonight".

## What counts as busy

Everything the device shows on the calendar, for the person or people it is for:

- A timed event is busy from its start to its end, for each of its owners (`CalendarEvent.owners`, which already folds in who an event is "For" and the faces of an event two people share).
- An event for the household as a whole ("Everyone") makes everyone busy, and says so once: "Everyone out".
- Work shown quietly is busy for its whole block, the first meeting's start to the last one's end, as the wall shows it ("at work until 5:30"): a gap between two meetings is not free time at home.
- Calendars shown in full and Busy only calendars count event by event.
- A calendar this device hides (`isShown` false, like Holidays) doesn't count; a calendar another device keeps to itself (Just me) never reaches this device, so it can't count, and the view's footer says so plainly: "From the calendars your household shares."
- A timed event longer than the window (a trip from Friday to Sunday entered as timed) is busy across every window it covers.

Being busy is about people, not calendars: an event in James's calendar marked "For Mia" makes Mia busy and not James.
When someone isn't free, the reason shown is the busy time that takes most of the window.

## All-day events

An all-day event never makes anyone busy by itself.
Most are not plans that take the evening (a birthday, a holiday, "Trash day"), and some are ("Mia in Denver", "Aunt Rosa visiting").
Guessing from the title ("visiting", "trip") would be wrong as often as right and different in every language.

Instead the day's all-day events are shown under that day's row ("All day: Aunt Rosa visiting"), so the household sees what it is weighing and decides.
A Busy only all-day event shows as "All day: Busy".

A later option, not built and not planned yet: an all-day event counts as busy when its calendar says it is ("Show as: Busy", `EKEvent.availability`).
That is the rule calendars themselves use and needs no guessing, but it needs one more field on `sharedEvent`, so a schema change and a Production deploy.

## Where it lives

**On the phone**, the Calendar tab gets a two-way control under its title, "Calendar" and "Free together", as the proposal's frame shows.
Free together replaces the week strip and the list with the rows, under the same person chips.
A green row plans something: it opens step 3's add sheet with the new event starting when everyone is free that day; what the line says replaces that only when it names a day or a time, read from that day.

**On the wall**, a row under the week grid, first among the lanes, one cell per day: green with "Everyone free from 5:30 PM" where everyone is free, otherwise who is out and why and the faces of who is free.
The week grid already shows the events; the row only adds the answer.
Paging the week pages the row with it; days past, or beyond the two weeks ahead, are empty.
A green cell opens the add sheet the same way when the iPad has the home calendar.

## The logic

`FreeTogetherLogic.times(events:people:from:days:windows:calendar:) -> [FreeTime]` is pure: the store's events (quiet blocks already made), the people asked about, the clock and the household's calendar are handed in.
`FreeTime` holds the day, the kind, the window, each free person's first free stretch, the stretch free for everyone, whether everyone is free for all of it, why each person who isn't free isn't, and the day's all-day events.
`FreeWords` turns it into the rows' words in the phone's time style, 12 or 24 hours as the device says.
The views only draw it.

Busy time is merged per person into sorted, non-overlapping intervals (events that touch or overlap join), then each window is cut by them.

## Tests

`FreeTogetherLogicTests`, pure, on the UI tests' Wednesday, November 18, 2026:

- the two weeks, weekend days by locale (US and Israel), tonight at 4 PM, 6 PM, 6:05 PM, 7:30 PM, 8:15 PM and 9:45 PM, and a Saturday already begun;
- an event ending as the evening opens, a minute later, and one starting as it closes;
- the two-hour and three-hour thresholds, exactly and a quarter hour short, and "after noon";
- an event across midnight and a timed event across a whole weekend;
- the clocks changing (March 8 and November 1, 2026, in Los Angeles) and a second time zone;
- quiet work as one block against the same meetings shown in full, Busy only, an event "For" one person in another's calendar, one for everyone, one two people share, all-day events (never busy, listed);
- one person's chip, a household of four, ranges in 12 and 24 hours;
- swept over a year in two zones: every window inside its day, in order, never in the past.

`PocketFreeTogetherScreenTests` hosts the phone's view in the four looks on a week with each kind of row.
`PhoneFreeTogetherTests.testPlanningAFreeEvening`: Free together from the tab, Mia's chip, a green evening planned through the add sheet.
`WallSharedCalendarTests.testFreeTogetherUnderTheWeek`: the row under the week and a green cell opening the add sheet.

## Words

"Free together" names the view; "Everyone free" is the line, as "Everyone" is the household elsewhere.
Times as the rest of the phone writes them (`ClockFormat.phoneTime`), and a range as "7:00 to 9:00 PM".
