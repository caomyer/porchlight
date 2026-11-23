# Glow: the week's story on the phone and the wall

Glow answers "what did we do for each other this week?".
The proposal is `docs/proposals/glow.html`, approved on November 23, 2026 with all five of its recommendations.
This note is what was built and the rules behind it.

## What people come for

- To be seen: the stars say what they were for, not only how many.
- To see the load: who is carrying what, with nobody ranked.
- To look forward: what is being saved for and when it comes at this pace.
- To look back: earlier weeks, and the rewards already enjoyed.

## One reading, two screens

Every number and sentence comes from one place, so the phone and the wall cannot disagree about a week.

- `GlowSummary` (`HomeLogic.swift`) is a week's totals, each person's week and the feed.
- `GlowStory`, `GlowWeeks`, `RewardPace`, `CashInNews` and `GlowWords` (`GlowStory.swift`) are the rest: the stars by task, "Lately" by day, what was cashed in, a reward's pace, the cash-in a shared screen still owes a celebration, and the words.
- `GlowReading` (phone) and the wall's `GlowScreen` only draw them.

Star counts always go through `StarWords`.

## Rules

- **Nobody is ranked.**
  People sit side by side in household order.
  Each is compared only with their own last week.
  No sentence says most, best, ahead or behind; a slower week is only told the number it follows ("This time last week: 11").
  `GlowStoryTests` and the phone's screen test both check for ranking words.
- **A fair comparison mid-week.**
  This week is compared with last week up to the same weekday, for the household and for each person (`lastWeekSoFar`).
  An earlier week is read whole and compared with the whole week before it (`GlowWeeks.readThrough`).
- **Each thing done counts once.**
  A walk taken together is one time and its stars once in the household's total and in "Where the stars came from", with both people named.
  On a person's own page it is their own credit.
- **Tasks are told by what was done.**
  A task is a chore or a companion's routine, whoever did it and whichever day (`GlowStory.tasks`).
  The row says how often and who: "6 times · Mia 4, you 2".
- **Lately is on the phone too.**
  The first phone design left the feed on the wall; the phone is where "what just happened" is asked most, so it has it now, told by day.
  The porch sparks stay on the wall.
- **Words stay whole.**
  On the phone a person's row says what they did and their own trend on separate lines.
  At the accessibility text sizes the stars join the words in a row instead of standing beside them, and the reward ideas become a column, so no word breaks mid-way.
  The phone leaves the paw print emoji out of a person's row, because it is dark on dark paper; the wall, always light, keeps it.
- **Calm motion.**
  The lamp never pulses, confetti falls once and stays, nothing loops.

## Looking back

Glow's weeks are the household's own weeks (`HomeWeek`), counted back from the one holding today (`GlowWeeks.week`).
The pager is the one the food diary and a companion's week use (`WeekPager` on the phone, `PagerButton` on the wall).
It goes back to the week of the first star anyone earned (`HomeSnapshot.firstStarDay`) and returns to this week when the day turns.
Stars are loaded two weeks back by default; paging further asks the store for more (`HomeStore.include(from:)`), one week before the week shown, for its trend.
Nothing about what iCloud stores changes.

On an earlier week the total, the strip, each person, the tasks and what happened are that week's ("that week" in the labels).
"Saving for" stays about now, and says so.
"Cashed in" shows what was enjoyed that week; on this week it is the household's short history.

## Rewards

- **Pace.**
  "about 3 days away at this pace" is the reward's remaining stars at the average of the 14 days ending today, from the same stars that count toward it (everyone's, each thing once, for a shared goal; the owner's for a treat).
  It says nothing when the reward is reached, when fewer than 3 of those days have a star, or when it is more than 12 weeks away (`RewardPace`).
- **Ideas.**
  A household with chores and nothing to save for is offered three shared rewards in one tap, and "Your own" (`RewardIdeas`).
  Each is an ordinary reward afterwards and can be edited.
- **Cashing in asks, then celebrates, on both screens.**
  The question names who earned the round and what is spent (`PocketGlowLogic.cashInMessage`).
  On the wall, reward cards ask through `askCashIn` and the whole screen celebrates (`WallCashIn.swift`).
- **A cash-in made on a phone is celebrated on the wall.**
  The wall keeps the time of the newest cash-in it has marked, per household, on the device.
  A newer one made on another device in the last 7 days is celebrated once, the next time the wall is awake with nothing else open (`CashInNews`).
  The first time the wall looks, nothing is owed for what is already there.
  Its round has already started over by then, so it says whose treat it was and what it cost, not who earned each star.
  The celebration waits for a touch and steps aside by itself after 45 seconds, so the wall can rest.

## Tests

- Unit: `GlowStoryTests` (tasks, words, weeks, an earlier week, Lately, cashed in, pace, ideas, cash-in news), `HomeLogicTests.glow`.
- Hosted screens: `PocketGlowScreenTests` (the page and a person's page in four looks, an earlier week, the pager's reach, reading further back, the reward ideas and picking one, the pace line), `PocketTabsScreenTests` (Glow fits).
- Journeys: `PhoneTabsTests.testGlowWeekPersonAndLookingBack` (the week, a week back and home again, a person's page), `PhoneTabsTests.testGlowAndCashingIn`, `PitchInTests.testCashingInOnGlow` (the wall asks, celebrates, steps back a week and opens a person).
- Not tested end to end: the wall celebrating a cash-in made on another device, which needs a second device; its rule is `GlowStoryTests.cashInNews`.
