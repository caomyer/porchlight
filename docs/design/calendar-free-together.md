# Free together

Step 4 of the family calendar MVP (docs/proposals/family-calendar.html, the "Free together" frame and "The MVP" item 4), on the shared calendar (docs/design/calendar-shared.md), the phone's Calendar tab (docs/design/calendar-phone-tab.md) and who an event is for (docs/design/calendar-add-edit.md).
It answers one question: "When are we free?"
It reads only what the device already has, writes nothing, and adds no record, so it changes no CloudKit schema.

## What it shows

The coming two weeks as the times a household plans things into: each weekday evening, and each Saturday and Sunday.
A free Tuesday at 5 AM is not a free Friday evening, so time outside those windows is never offered.

For each of those times, one line:

- **Everyone free from 6:00 PM**, in green, when every person in the household is free for long enough.
- Otherwise who is free, by their faces, and who is not, dimmed: "Mia free, James busy until 8:00 PM".
- A weekend day also says when: "Everyone free all day", "Everyone free after noon", or "Everyone free from 3:00 PM".
- An all-day event on that day, under the line, for context: "All day: Aunt Rosa visiting" (see "All-day events").

The person chips at the top of the Calendar tab filter it as they filter the calendar: with Mia picked, the lines say when Mia is free, and "Everyone" is the household.

## The windows

| | Weekday evening | Weekend day |
|---|---|---|
| Window | 5:30 PM to 9:30 PM | 9:00 AM to 9:30 PM |
| Free for | 2 hours unbroken inside it | 3 hours unbroken inside it |
| "From" | the start of the first such stretch | "all day" when the whole window is free; "after noon" when the first stretch starts between 12:00 and 1:00 PM; otherwise the stretch's start |

Friday evening is a weekday evening.
These are the defaults, kept in one value (`FreeWindows`) that the logic takes as a parameter, so a household setting can change them later without touching the rule; this step adds no setting.
Times are in the household's time zone and calendar (`Household.calendar`), as the rest of the calendar is.

Today counts from now: this evening's window starts at the later of 5:30 PM and the current minute, rounded up to the next quarter hour, and a window already over is left out.
So at 8:15 PM tonight, with less than two hours left, tonight is not offered.

## What counts as busy

Everything the device shows on the calendar, for the person or people it is for:

- A timed event is busy from its start to its end, for each of its owners (`CalendarEvent.owners`, which already folds in who an event is "For").
- An event for the household as a whole ("Everyone") makes everyone busy.
- Work shown quietly is busy: the quiet block's meetings each count, not the block's outline, so a gap between meetings is free.
- A Busy only event is busy, for its calendar's owner.
- A calendar this device hides (`isShown` false, like Holidays) doesn't count; a calendar another device keeps to itself (Just me) never reaches this device, so it can't count, and the note says so plainly in the view's footer: "From the calendars your household shares."
- A timed event longer than the window (a trip from Friday to Sunday entered as timed) is busy across every window it covers.

Being busy is about people, not calendars: an event in James's calendar marked "For Mia" makes Mia busy and not James.

## All-day events

An all-day event never makes anyone busy by itself.
Most are not plans that take the evening (a birthday, a holiday, "Trash day"), and some are ("Mia in Denver", "Aunt Rosa visiting").
Guessing from the title ("visiting", "trip") would be wrong as often as right and different in every language.

Instead the day's all-day events are shown under that day's line ("All day: Aunt Rosa visiting"), so the household sees what it is weighing and decides.
A Busy only all-day event shows as "All day: Busy".

Proposed for later, not in this step: an all-day event counts as busy when its calendar says it is ("Show as: Busy", `EKEvent.availability`).
That is the rule calendars themselves use, it needs no guessing, and "Aunt Rosa visiting" set to Busy would then block the weekend.
It needs one more field on `sharedEvent`, so a schema change and a Production deploy; I would rather see a week of real use first.

## Where it lives

**On the phone**, the Calendar tab's header gets a two-way control under the title, "Calendar" and "Free together", as the proposal's frame shows.
Free together is a list, two weeks long, one row per evening or weekend day, grouped by week ("This week", "Next week"), with the person chips above it.
Tapping a row opens that day in the calendar view, scrolled to the window, so the person can see what the busy ones have.
"+" stays in the header in both views, and in Free together it starts the new event on that row's day and "from" time.

**On the wall**, a row under the week grid, one cell per day of the week shown: the evening (or the weekend day) as a green cell with "Everyone free from 6" where everyone is free, and otherwise the faces of who is free.
The week grid already shows the events; the row only adds the answer.
Paging the week pages the row with it; weeks past the two weeks ahead show no row, as there is nothing promised there.

## The logic

One pure function, in `FreeTogetherLogic`:

```swift
static func times(
    events: [CalendarEvent], people: [Person], from now: Date,
    days: Int = 14, windows: FreeWindows = .standard, calendar: Calendar
) -> [FreeTime]
```

`FreeTime` holds the day, the kind (evening or weekend day), the window, each person's free stretches inside it, whether everyone is free, the "from" words' time, and the day's all-day events.
The views only draw it.

Busy time is merged per person into sorted, non-overlapping intervals first (events that touch or overlap join), then each window is cut by them; this keeps it linear in the number of events.

## Tests

`FreeTogetherLogicTests`, pure, on the pinned clock (`UITestClock`'s Wednesday, November 18, 2026, and fixed times handed in), swept:

- both sides of each window's edges: an event ending exactly at 5:30 PM leaves the evening free; one ending at 5:31 PM moves "from" to 5:31 rounded to 5:45;
- the two-hour and three-hour thresholds, at exactly the length and a minute short;
- tonight at 4 PM, 6 PM, 8:15 PM and 9:45 PM;
- an event crossing midnight, and a timed event across a whole weekend;
- the clocks changing (March 8 and November 1, 2026, in Los Angeles), and the same week in a second time zone;
- a week starting on Sunday and on Monday (which days are weekend days doesn't change: Saturday and Sunday);
- quiet work blocks with a gap, a Busy only event, an event "For" one person in another's calendar, an event for everyone, a hidden calendar, an all-day event (never busy, but listed);
- a household of one (the "Everyone" line says "Free"), of two, and of four.

`PocketFreeTogetherScreenTests`, hosted, in the four looks, and one hosted look of the wall's row at the wall's sizes.
One UI journey per device: on the phone, switch to Free together, pick a person, tap a row and land on that day; on the wall, the row under the week on the pinned week with the sample's events (`-sampleSharedCalendar YES`).

## Words

"Free together" names the view; "Everyone free" is the line, as "Everyone" is the household elsewhere.
Times as the rest of the phone writes them (`ClockFormat.phoneTime`), ranges with a plain hyphen.

## Questions

1. The windows' defaults: 5:30 to 9:30 PM evenings and 9 AM to 9:30 PM weekends, with two and three hours as "free". Are those your household's?
2. All-day events: shown as context, never busy, in this step; "Show as: Busy" counting is proposed for after a week of use. Agree?
3. Should Friday evening be treated as part of the weekend (a later end, say 11 PM)?
