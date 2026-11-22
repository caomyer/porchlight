# The phone's Calendar tab

Step 2 of the family calendar MVP (docs/proposals/family-calendar.html, "iPhone"), on the shared calendar of step 1 (docs/design/calendar-shared.md).
Read only: nothing is added or changed here until step 3, and Free together comes in step 4.

## What it is

The fifth tab, between Today and Food; porchlight://calendar opens it.
From the top:

- The month ("November 2026", or "Nov – Dec 2026" for a week across two) with "You" beside it.
  Tapping it unfolds the week into the month; tapping a day there picks it and folds the month away.
  There is no separate month screen.
- A chip for Everyone and one per person, filtering everything below.
  A person's events are theirs, the shared ones they are on, and the household's own; the chips wrap onto a second line at large text rather than run off the side.
- "‹ This week ›", as Food's diary pages, with "Back to today" when away from today, and a sideways swipe on the strip.
- The week strip from the household's first weekday: the weekday's letter, the date, and a dot per person with something that day in the household's order, the household's own last.
  Today's date is in the accent color with a ring; the picked day sits in a filled pill.
- "Sam's calendar, updated Tuesday" for a device more than a day quiet.
- The list: the picked day, then the days after it that have something, through two weeks.
  The picked day always shows, "Nothing planned." when it is empty; the empty days after it are left out.
  Each day says "Today, Tuesday", "Tomorrow, Wednesday", the weekday this week, or "Mon, Dec 7", and how many things.
  All-day events first, then by start; each row is the time, a bar in the owner's color as tall as its words, the title, the end and place, and every face.
  A quiet calendar is one row per person per day; Busy only reads "Busy".

Tapping a row opens the event's page in the app: when, where, notes, who it is for, and where it came from ("From Sam's Google · Mia Soccer", or "Your Work calendar, on this iPhone").
A Busy only event says its words stay on its phone; a quiet day lists its meetings.
Only an event from this phone has "Open in Calendar": one passed on from another device can't open in this phone's Calendar.
Whether an event repeats isn't shown yet: the other devices don't pass it on, and this phone's own would be the only ones with it.

## Times

Every time on the phone's calendar says morning or afternoon: "6:00 PM", "to 7:30 PM", "Until 5:30 PM" (`ClockFormat.phoneTime`), and on a phone set to 24-hour time, "18:00" with no marker.
The time sits in its own column, which goes over the title at the largest text sizes, so the marker always fits.
Today's "At home today" card uses the same style.

## Next 7 days is retired

Today's card links to the tab on today ("Calendar ›") instead of to the Next 7 days page, which is gone.
The tab does everything that page did (the days ahead, grouped, in each person's color) and more (any week, a person, an event's page), and keeping both would have meant two lists of the same events to keep right; the page also promised "Tap an event to open it in Calendar", which is false for an event from another device.

## Tests

`PocketCalendarLogicTests` holds the weeks from either first weekday over a year, paging across the clocks changing, the month grid, the header, dots, the person filter, the list's days and the time style, on calendars and days handed in.
`PocketSharedCalendarScreenTests` hosts the tab and Today's card with another device's events in light, dark and the largest text.
`PhoneCalendarTests` has two journeys: the week, a day, a person and an event's page; and the month.
