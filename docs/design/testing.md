# Testing: which check goes where

This is the rule for deciding whether a check is a unit test or a UI test, and for keeping the whole suite fast.
It is a decision rule, to be applied without asking.
The audit at the end applies it to every UI test in the repository, with measured times.

## State of the suite

Where things stand, for anyone who does not need the audit.
Every number is from the run named in its column, on GitHub's hosted Macs (3 cores, 7 GB, iOS 27.2).

| | At the start: November 20, 2026 (run 44828667552) | Now: November 21, 2026 (run 44926520595) | Target |
|---|---|---|---|
| UI test seconds, all tests added up | 8,041 | 5,735 | 5,400 |
| UI tests in the suite | 150 | 136 | |
| UI tests over 60 seconds | 38 | 26 | |
| UI tests over 120 seconds | 7 | 0 | 0 |
| Longest UI test | 746 s | 120 s | 120 s |
| Longest job's seconds of tests | 2,153 | 1,506, and about 1,300 once the shards are weighed again from this run | 1,080 |
| A full run from start to green, with no queueing | 48.6 minutes | about 42 minutes: a 6.6 minute build, then a longest job of 35 | 30 minutes |
| A push to a working branch, with no queueing | 48.6 minutes: every push ran everything | about 20 minutes: the unit tests and the smoke set (run 44888821802) | 20 minutes |
| Unit tests | 572 | 614 | |

What the table says plainly: the tests take 29% less time and none is over the ceiling, but a full run is only 14% faster, because each test job now spends about ten minutes on what is not a test (booting a new simulator, settling it, fetching and unpacking the build, installing, collecting results).
That overhead, not the tests, is the next thing to shorten ("Budgets").
When a row here goes stale, update it from a green full run and name the run.

## The rule in one paragraph

A check lives at the lowest level that can express it.
If the answer does not depend on real rendering, hit-testing, focus, the keyboard, scrolling, a gesture, navigation or a system prompt, it is a unit test, and it runs in milliseconds.
A UI test is a journey a person takes from start to finish, and it asserts only what the real UI can get wrong.
When in doubt, ask "could this fail while every unit test passes, and would a person notice?"; if not, it is not a UI test.

## Decide in four questions

Ask these in order and stop at the first yes.

1. **Is it a value the code computes?**
   Words, a count, an order, a label, a time, a state, a row in the database, what sync sends.
   Unit test, against the type that computes it.
2. **Is it a rule about dates or times?**
   Unit test with the clock pinned, swept across the day and in more than one time zone (see "Hard rules").
3. **Is it buried in a View so that no type computes it?**
   Extract the smallest type or function that does, keeping behaviour identical, and unit test that.
   `PocketSyncNotice.pick` is the pattern: the view asks a pure function what to say and only draws the answer.
4. **Can only the real app get it wrong?**
   An element that is not hittable or is covered by the keyboard, a sheet that does not close, a tap that lands on the wrong thing, focus, a gesture, a push or a pop, a permission prompt, state that must survive a relaunch.
   UI test, and it belongs to a journey.

## What a unit test owns

Unit tests are Swift Testing suites in `PorchlightTests/`, one folder per feature.
They own everything whose correctness does not need the app on screen.

- **Logic and rules**: which slot one tap logs, what counts toward a streak, who a reward names, what a tap on a Where pill does (`PocketTodayTests`, `CareLogicTests`, `MealSourcesTests`).
- **Words and formatting**: every string built by code, in every state, compared whole (`SyncWordingTests`, `ArrivalsTests`, `HouseholdHomeTests`).
  A UI test never checks the wording of each state by launching the app once per state.
- **Order and counts**: card order on Today, aisles in store-walk order, "Groceries · 10" (`PocketTodayTests`, `PocketTabsTests`).
- **Dates and times**, with a pinned clock swept across the day and across time zones (`OwedSweepTests`, `ArrivalsTests.offlineSince`).
- **Database writes and migrations**, against an in-memory database (`AppDatabase.inMemory`, `SyncMigrationTests`, `DishDatabaseTests`).
- **Sync**, against the fake iCloud (`SyncHarness`, `SyncControllerTests`, `OlderBuildSyncTests`).
- **Store, model and flow state**: what a screen's model holds after each step (`JoinFlowTests`, `PocketWritesTests`, `TwoHouseholdsTests`, `TimeEntryTests`).

## What a UI test owns

UI tests are XCUITest classes in `PorchlightUITests/`; `Phone…Tests` run on the iPhone, every other class on the iPad.
Each one relaunches the app, which costs 15 to 20 seconds on a hosted Mac before the first assertion.

- **A journey a person takes, end to end**: one test per journey, on the phone and on the wall where both have it.
  It covers the happy path, plus the one or two failure paths that matter to a person (a join that fails offline, a permission that is turned off).
- **What only the real UI can get wrong**: an element not hittable, a field covered by the keyboard, a sheet that does not close, navigation, focus, gestures, a system permission prompt, a setting that must survive a relaunch.
- **The visual review shots**: light, dark and the largest text size, as a deliberately small set, one test per class at most (see "Looks").

A UI test does not own:

- The wording of each state: one launch proves the words reach the screen; the unit test proves every state's words.
- A rule's branches: one launch proves the control is wired to the rule; the unit test walks the branches.
- Anything that needs the app launched more than once to cover cases that differ only in data.

## Fixing a bug

1. **Reproduce it where the user hits it first.**
   This is a standing project rule: drive the app as the person did, so the fix is for the real problem.
   That reproduction is usually a UI run by hand or a temporary UI test.
2. **Pin the cause at the lowest level that can express it.**
   Write the unit test that fails for the cause, with the clock pinned and swept if time is involved, and fix it there.
3. **Keep at most one UI test for the journey.**
   If the journey already has a UI test, add nothing at the UI level; if the bug was one only the real UI can have (a tap that misses, a sheet that stays), add the assertion to that journey's test.

The two bugs of November 20 are the examples.
A care log placed in the wrong slot by the time of day, and a streak miscounted for a pet added late in the day, were both found on a device, and both are now held by `OwedSweepTests`, which walks every half hour of arrival against every half hour of now.
No UI test could have held them: a UI test runs at one time of day.

## Moving a check down

Coverage is proven, not assumed.

1. Write the unit test, or find the one that already holds the assertion.
2. Break the behaviour on purpose (change the words, flip the rule, read the real clock) and see that unit test fail; then put the code back.
   A unit test nobody has seen fail does not count as holding the assertion.
3. Only then remove the assertion from the UI test, and say in the UI test's comment which unit test holds it.
4. Never weaken a check to make it movable: if the unit test cannot say what the UI test said, extract the logic until it can, or leave the UI test alone.
5. Leave one launch that shows the value on screen, so the wiring from the type to the view stays covered.

## The middle options

These sit between a pure function and a launched app.
All eight are proven in this repository.

| Option | Proven by | Use it for |
|---|---|---|
| A pure function or small type the view asks | `PocketSyncNotice.pick`, `SyncStatus.summary`, `PocketToday`, `MealSources` | Words, order, counts and rules that a view shows |
| A store, model or flow tested directly | `JoinFlowTests`, `PocketWritesTests`, `TwoHouseholdsTests`, `TimeEntryTests` | What a screen holds after each step, without the screen |
| The real database in memory | `AppDatabase.inMemory`, `HomeDatabaseTests`, `SyncMigrationTests` | Writes, migrations, what a save stores |
| The fake iCloud | `SyncHarness`, `SyncControllerTests` | What sync sends, receives and says |
| A SwiftUI view drawn with `ImageRenderer` in the unit bundle | `WidgetRenderTests` | Review shots of self-contained views in light, dark and the largest text, in milliseconds |
| A component measured in a `UIHostingController` in the unit bundle | `TimeFieldLayoutTests` | A component's layout facts at every Dynamic Type size: it grows, it fits the width, it stacks instead of overlapping |
| A whole screen hosted in a window in the unit bundle (`HostedScreen`) | `PocketWeekScreenTests`, `PocketCareSheetScreenTests`, `PocketDishesScreenTests`, `PocketTabsScreenTests`, `PocketFoodScreenTests` | Where every element of a screen sits, and a picture of the whole page, in light, dark and the largest text |
| A line of text laid out with Core Text, its ink measured | `HandwritingTests`, `HandCompanionTests` | Whether a face's ink stays inside the box a `Text` gives it, at every size, with and without a fallback face |

The component option works by size, not by position.
`UIHostingController.sizeThatFits(in:)` gives the size a view takes in a given width with a text size and size class set in the environment, so "the pill is under its label" is checked as "the row is as tall as the label, the gap and the pill together".
It runs all twelve text sizes in a fifth of a second, where the UI test covers one size in a launch.
It suits a component whose layout rule is its own (`LogTimeField`, a pill, a row, a card).

The whole-screen option gives positions and a picture.
`HostedScreen.host` puts a screen, with its stores on an in-memory database holding sample data, in a 393 by 852 point window inside the unit tests' host app, in a look, and returns every accessibility element's label and frame and an image of the whole page, as tall as its content.
A companion's week in four looks takes about five seconds; `PhoneWeekTests.testWeekLooks` takes over twelve minutes for three, and failed once on a scroll that fell short (run 44860696474).
With `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder>` the pages are written as PNGs for review.

What the spike of November 20 found, so its limits are known:

- **It needs one private call.**
  SwiftUI builds its accessibility tree only for VoiceOver or an automation client, and without `_AXSSetAutomationEnabled` (the switch XCUITest flips in the app it drives) a hosted screen reads as no elements at all.
  The call is made only in the test bundle, and a test checks that it read elements, so if a future iOS removes it the tests fail instead of passing on nothing.
- **Frames come with scrolled-off content.**
  A scroll view's content is all laid out, so an element two screens down has a frame two screens down; nothing needs scrolling.
- **It can pick a tab, not drive a journey.**
  `host(_:look:activating:)` activates one element by its label before reading, as a tap would, which is enough to show a screen's other tab or section; anything longer is a journey and a UI test.
- **A row that scrolls sideways reaches past the edge.**
  Its later items have frames beyond the screen's width by design (the lists' chips at the largest text), so a "nothing runs off either side" check names such a row and leaves it out; it found that on its first run.
- **Frames, not ink.**
  "Nothing runs off either side" compares elements' frames with the screen, and a letter can draw outside its element's frame (hard rule 9); what the ink does is for an ink-bounds test, or for the eye on the page's picture.
- **Labels, not identifiers.**
  SwiftUI's elements here do not give their accessibility identifiers, so elements are found by label.
- **It is not the real screen's surroundings.**
  There is no status bar, tab bar, navigation bar, sheet or keyboard, nothing is hit-tested and no gesture runs, so "can it be tapped", "is it under the keyboard", "does paper show under the status bar" and "does the sheet close" stay UI tests.
- **The clock is the app's.**
  The screens and the sample data read `CompanionClock` themselves, which only the process-wide `-debugCompanionNow` pins, so a hosted test asserts where things sit, never a time, a count or a day's name, until the clock can be handed in.
- **Each screen needs its stores, and a missing one stops the whole run.**
  A screen hosted without an environment object it reads does not fail its test: SwiftUI stops the process, and every unit test after it is lost with it, so add the store the crash names and run again.
  The week needs a `CompanionStore`, a `ToastCenter` and `me`; a screen that reads more of the environment needs more, and one that reads `UIDevice` or the real permission state would need a seam first.
- **The unit tests run on the iPad simulator.**
  The phone's layout comes from a compact size class set on the hosting controller, which the week's screen follows; a screen that asks the device what it is would not.

It is proven for three (a companion's week, the care sheet and the dishes pages), and their looks have moved onto it, as have those of Lists, Glow and Pitch in (`PocketTabsScreenTests`) ("Review shots"); other screens move one at a time, each with a hosted test seen failing first and one UI test kept for what only the real screen shows.

When you add a new kind of test, add a working example with it and a row to the table above.

## Looks

The night look and the largest text size are checked by eye from screenshots, plus a few layout facts (a button whole on screen, a pill clear of its label).

- One looks test per class at most, visiting the class's screens in as few launches as it can: navigate between screens inside a launch instead of launching once per screen.
- A look is a launch, so three looks of one screen are three launches; do not also launch per screen.
- Never repeat a journey's steps in a looks test to get to a screen; start there with a debug launch argument (`-debugFoodView`, `-debugCompanionSheet`, `-debugYouPage`).
- A layout fact that holds for a component everywhere (the time pill, the photo row) is asserted once, in one looks test, not in each class that shows the component.

### Review shots

Review shots come from two places, and each screen's are named so a person knows where to look.

- **Hosted pages** (unit bundle, seconds): `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder> scripts/test.sh --unit-only` writes each hosted screen's whole page in each look there as a PNG, as `TEST_RUNNER_PORCHLIGHT_WIDGET_SHOTS` does for widgets.
  They show the page alone: no status bar, tab bar or sheet chrome.
- **Screenshots attached by UI tests** (in each job's `.xcresult`): the real screen, with its surroundings, at the steps of a journey.

| Screen | Hosted shots | Looks | UI test that stays, and what only it shows |
|---|---|---|---|
| A companion's week, walks and meals | `week-walk-<look>.png`, `week-feed-<look>.png` | light, dark, largest, largest-dark | `PhoneWeekTests.testWeekLooks`: the real page in the night look at the largest size, each routine's tab and log button within reach, water included (`week-40-largest-dark-top`, `week-41-largest-dark-<routine>`). The other tests of the class: the trail's dots open the right sheet, a log shows in trail and diary |
| The care sheet: new, fixing, catching up | `care-sheet-new-<look>.png`, `care-sheet-fix-<look>.png`, `care-sheet-catchUp-<look>.png` | light, dark, largest, largest-dark | `PhoneTabsTests.testFixingAWalkLooks`: the real sheet at the largest size, Save within reach (`edit-40-today-largest`, `edit-41-save-largest`). `PhoneCatchUpTests`, `PhoneTabsTests.testFixingAWalkFromToday`: the sheet opens, saves, asks before removing and closes (`catch-up-10-banner-sheet`, `edit-10-today`, `edit-11-remove`) |
| Dishes: the list, a dish, a restaurant | `dishes-list-<look>.png`, `dishes-dish-<look>.png`, `dishes-place-<look>.png` | light, dark, largest, largest-dark | `PhoneDishesTests`: search, the star, a restaurant from a dish, each person's face, renaming into a merge, removing with Undo (`dishes-02-list` to `dishes-10-empty`) |
| Food: the Where pills, the photo row and reframing, paper under the status bar | none yet: the status bar is not there in a hosted screen, and the editor's row needs the meal's photos handed in | | `PhoneFoodTests.testWhereLooks`, `testPhotoRowAndReframeLooks` and `testPaperUnderTheStatusBarAtNightAtTheLargestSize`: one look each, the night look at the largest size (`where-20-phone-largest-dark`, `parity-30-edit-row-largest-dark`, `parity-31-reframe-largest-dark`, `b5-60` to `b5-63` `-largest-dark`); `testNightLook` and `testLargestText` for the diary and a meal's page |
| Lists, Glow, Pitch in | `lists-<look>.png`, `glow-<look>.png`, `pitch-in-<look>.png` | light, dark, largest, largest-dark | `PhoneTabsTests.testLooks`: the real tabs in the night look at the largest size, the field and the cash-in button whole, cashing in to the celebration, the next 7 days (`m3-90-lists-largest-dark`, `m3-91-glow-largest-dark`, `m3-83-celebration-largest-dark`, `m3-94-next-7-days-largest-dark`); the journeys for adding, checking off and cashing in |
| The Food diary on this week, last week and an empty week | `food-week-0-<look>.png`, `food-week-1-<look>.png`, `food-week-3-<look>.png` | light, dark, largest, largest-dark | `PhoneFoodTests.testChangingWeeks`: back a week, a meal opened and Back to the same week, a past slot filled and kept in its week, back to this week (`b5-30-last-week`) |
| Joining, the sync banner, the household's name on Today | none yet | | `PhoneHouseholdTests.testLooks`: the night look at the largest size, Join and Continue within reach, the banner fitting, the household named whole (`phone-140-join-preview-largest-dark`, `phone-141-join-who-largest-dark`, `phone-142-banner-largest-dark`, `a5-22-today-header-largest-dark`, `a5-23-today-slots-largest-dark`) |
| Today | none yet | | `PhoneTests.testLooks`: the night look at the largest size, the log button whole and full width (`phone-90-largest-text-dark`, `phone-91-largest-text-chores-dark`); `phone-10` to `phone-12` from the journey |
| The dish editor's form | none yet | | `PhoneDishEditorTests.testTheFormAtNightAndAtTheLargestText`: one launch, the field and its suggestions over the keyboard (`editor-30-largest-dark`) |
| Notifications | none: the page reads the permission itself | | `PhoneRemindersTests.testLooks`: night look at the largest size in one launch (`e2-80-choices-largest-dark`); `e2-10-ask`, `e2-11-denied`, `e2-12-choices` from the journeys |

A screen moves to hosted shots when a hosted test of it exists and has been seen failing; until then its looks tests stay as they are.

### Shots that stay when the words move down

When the words of each state move to a unit test, the launches that only compared them go, and their screenshots with them.
One shot per shape of the screen stays, not one per wording.

| Screen | States that still have a shot | Why those | States without one |
|---|---|---|---|
| The phone's sync banner on Today | A full iCloud (`phone-110-banner-iCloudFull`); a restored copy (`phone-115-banner-restoredCopy`) and the choice it opens (`phone-119-restored-choice`); a missing iCloud at the largest text (`phone-142-banner-largest`) | The two shapes of the banner: a warning with no button, which also shows the owner's name reaching it, and a warning with its "Choose" button; and the longest layout | Restricted, needs sign-in, signed out at the usual size, offline: the same banner with other words, held by `ArrivalsTests` |
| Settings' sync section on the wall | Signed out (`74-sync-icloud-off`), the longest line; a full iCloud (`71-sync-icloud-full`); a different account (`70-sync-needs-decision`) and a restored copy (`90-restored-copy`), each with its buttons | The plain line under the switch at its longest, the paused card, and the two decision cards | Restricted and needs sign-in: the same line with other words, held by `SyncWordingTests` |

## Hard rules

The first six were each learned from a failed or misleading run in the week of November 16, 2026.
The ninth is from a defect found by eye on November 21; the others come from what the UI tests' own comments record.

1. **A test's outcome never depends on the real clock.**
   Pin it and sweep it.
   That includes the clock of the test itself: a UI test must never have to do something within so many seconds of the app's own timer, because a hosted Mac can take 50 seconds over one drag ("Flaky tests").
   Wait for a thing to happen, with a long limit, and put the timer's rule in a unit test with the times handed in.
   In a unit test, pass `now` and a `Calendar` with an explicit time zone, and walk the day in half hours in at least two zones when the rule has anything to do with the time of day or the day's edge.
   In a UI test, pin the time with `-debugCompanionNow yyyy-MM-ddTHH:mm`, which the wall and the phone both read, and never branch on `Date()`.
   The day in that argument is today's, because the sample household is built around today; the time of day is what must not move.
   Why: a log landed in the wrong slot, and a streak was miscounted, only at certain hours, where a test that runs at one hour cannot see it.
   A timestamp that is only stored, never compared, bucketed or formatted (a row's `createdAt`), may be `Date.now`.
2. **Every loop in a UI test helper has a bound.**
   Write `for _ in 0..<n where …`, or a deadline that fails the test when it passes, as `reveal` and `waitUntilResponsive` do.
   Why: an unbounded loop does not fail, it hangs the job until its 75 minute limit, and the log does not say which test.
3. **A launch argument that reaches `UserDefaults` needs a value.**
   Write `-sampleWater YES`, not `-sampleWater`.
   Why: the argument domain is read as key and value pairs, so a bare flag swallows the next argument or is not seen at all.
   Only flags the app reads from `ProcessInfo.arguments` itself (`-sampleHousehold`, `-resetData`) work bare.
4. **A suite that runs no tests fails.**
   `scripts/test.sh` reports "no tests ran" and exits non-zero when a selection matches nothing or only tests that skip themselves.
   Why: a phone class once ran on the iPad, skipped every test and reported success.
   Do not work around it; fix the selection.
5. **Do not find an element by a label that is also a button's title.**
   Give the element an accessibility identifier and query that (`save-care`, `went-Mia`, `dish-title`).
   Why: "Log a walk" is the sheet's title and a button on the page behind it, and "You" is a pill in the sheet and the avatar behind it, so the query matched before the sheet opened, or matched two elements.
6. **iPad frames come back in portrait coordinates unless the device is turned first.**
   Launch through `XCUIApplication.porchlight()`, which turns the iPad to landscape before the launch.
   Why: a new simulator boots in portrait, and on iPadOS 27 frames, swipes and the keyboard are then reported sideways, so "above the keyboard" checks compare the wrong edges.
7. **Never tap before the element has settled, and never rely on XCUITest to scroll for a tap.**
   Use `waitToSettle()` for anything in a sheet that is still sliding, and `reveal(_:in:)` before a tap below the fold.
   Why: a tap computed mid-slide lands outside the sheet and closes it, and under the floating tab bar automatic scrolling stops short and taps nothing.
8. **No fixed sleeps as a way of waiting.**
   Wait for the thing (`waitForExistence`, `waitForNonExistence`, an expectation on a predicate); a `Thread.sleep` is allowed only to let an animation finish before a screenshot.
   Why: a launch helper that sleeps 4 seconds adds 4 seconds to every test in its class, as `FoodMealsTests` and `MealPhotosTests` did for 17 tests until they waited for the app to answer and for their first element to settle instead.
9. **A frame inside the screen does not prove the ink is inside the frame.**
   Where a face draws past its letters' own widths, check the ink's bounds, not the element's frame.
   Why: Caveat's slanted letters reach up to 0.21 em past their advance, and a SwiftUI `Text` is as wide as its letters' advances and draws nothing beyond, so a handwritten title ending in "l", "f" or "i" lost the top of its last letter ("Bagel" drew as "Bagei").
   Every frame was where it should be; no frame check, on a real screen or a hosted one, could have seen it.
   `Text(handwritten:)` (`Handwriting.swift`) is now the one way the app writes a handwritten title, with room for the tails, and `HandwritingTests` lays each title out with Core Text at every size and requires the line's ink to sit inside the line's box.
   Do not write the handwritten face any other way, and when a new face or a new slant arrives, give it an ink-bounds test of its own.
10. **A test that needs the network or real delivery timing runs by hand, not in the suite.**
   Guard it with `XCTSkipUnless` on an environment variable, as `PhoneRemindersTests.testDeliveryByHand` and `FoodMealsTests.testLiveRestaurantSearchByHand` do, and when it is asked for it fails, never skips.
   Why: a test that skips itself when the network is down reports nothing either way.

## Tiers

Not every push needs every test, and the release line needs all of them.

| What happened | What runs | Macs | For |
|---|---|---|---|
| A push that touches only `docs/` or `README.md` | Nothing | 0 | Writing things down costs no Mac |
| A push to a working branch | The unit tests and the smoke set | 3 | "Did I break something obvious?", in about 20 minutes |
| A push to `integration/next` or `main` | The full suite: unit tests and both whole UI suites | 5 | The release gate |
| A run by hand on any branch, "only" left empty | The full suite | 5 | Before asking to merge |
| A run by hand with "only" set | Just those tests | 1 | Checking a change, or a failure |

A push that changes only the documentation runs nothing at all: when every file in the push is under `docs/` or is the `README.md`, the workflow does not start (`paths-ignore` in `.github/workflows/tests.yml`).
One file anywhere else in the push, a script or a workflow or a Markdown file inside a target's folder included, and it runs as usual, so a code change cannot be skipped by keeping it company with a document.
A run by hand is never filtered, so the full run before a merge is still made on the branch's last commit, whatever that commit touched.

The rules that make two tiers safe:

1. **The release gate is unchanged.**
   Nothing reaches `main`, TestFlight or the wall from a commit whose full suite is not green on `integration/next`.
2. **A branch runs the full suite once before asking to merge.**
   Its author, person or agent, starts it by hand on the branch's last commit (`gh workflow run Tests --ref <branch>`) and gives the run's id with the request; a branch whose last full run is red, or older than its last commit, is not merged.
   The smoke set on each push is for the author's own speed and is never the evidence for a merge.
3. **A red release line is put right within the hour.**
   The commit that turned `integration/next` or `main` red is reverted, not debugged in place; it comes back through its branch with the fix and a green full run.
   Whoever merged it does the revert.
4. **A flaky test is quarantined, with an owner and a week.**
   A test that fails and then passes with nothing changed is flaky, and a flaky test in the gate teaches everyone to rerun and ignore.
   It is taken out of the suite the day it is seen (an `XCTSkip` with the reason), and written into "Flaky tests" with its owner, and into "Tests that skip themselves" with a date one week on.
   One whose cause is found and fixed the day it is seen is written into "Flaky tests" as fixed, and stays in the suite.
   By that date it is fixed and back, or moved down to a unit test, or deleted with the reason recorded; it is never left skipped.
   A failure that XCTest's own launch retry covers ("could not start the app") is not a flaky test, and one that cannot be reproduced is written into "Known and not yet explained".
   Nor is a job that failed before any test ran: a build whose download arrived corrupted is checked against the build job's checksum and fetched again, and fails saying so if it cannot be put right (`scripts/ci/unpack-build.sh`), as one smoke job did on November 21 before that check existed.
5. **The smoke set is one journey for each major area on each shell, about ten minutes of tests.**
   It is defined in one place, `scripts/test.sh` (`smoke_wall`, `smoke_phone`), which the script's `--smoke` and the workflow both use.
   A journey's smoke test is its plain happy path, never a looks test and never one over 120 seconds unless nothing shorter covers the area (the first run's real permission prompt is the one exception).

The smoke set, with seconds from run 44883476613:

| Shell | Area | Test | Seconds |
|---|---|---|---|
| Wall | Today and chores | `DayAtAGlanceTests.testCheckingOffAChoreOnToday` | 38 |
| Wall | The calendar | `DayAtAGlanceTests.testMomentsInTheWeek` | 22 |
| Wall | Care: log, celebrate, fix | `LoggedEntryTests.testFixingAWalkFromToday` | 33 |
| Wall | Food: a meal and its dishes | `WallDishEditorTests.testHomeMealTypedWithASuggestion` | 31 |
| Wall | The household and inviting | `HouseholdTests.testFamilyAndDevicesShowsEveryoneAndBothWaysIn` | 38 |
| Wall | Sync's states | `SyncSettingsTests.testAFullICloudPausesSync` | 29 |
| Wall | First run, with the real prompt | `FirstRunTests.testOnboardingWithRealCalendarAccess` | 171 |
| Phone | Today: care in one tap | `PhoneTests.testOneTapLogAndUndo` | 19 |
| Phone | Chores | `PhoneTabsTests.testPitchInAndAddingAChore` | 48 |
| Phone | Lists | `PhoneTabsTests.testListsAndDinners` | 53 |
| Phone | Food: the camera to the diary | `PhoneFoodTests.testSnappingAMeal` | 41 |
| Phone | Joining a household | `PhoneHouseholdTests.testJoiningFromAnInvite` | 20 |
| Phone | Starting a household, every tab empty | `PhoneSetupTests.testStartingAHouseholdOnThisPhone` | 69 |

That is 362 seconds for the wall and 250 for the phone, 612 in all (10 minutes), against 6805 for the full suite in the same run.

What the smoke set leaves to the full suite: Glow, a companion's week, dishes, reminders, catching up, photos, the photo frame, the time pad, every failure path and every looks test.

## Tests that skip themselves

A skipped test is a decision, so every one is listed here with its reason; a skip that is not in this table is a mistake.
A full run reports exactly these: two skipped in the unit tests, three in the phone's UI suite, one in the wall's.

| Test | Skipped unless | Why |
|---|---|---|
| `PhoneRemindersTests.testDeliveryByHand` | `PORCHLIGHT_DELIVERY=1` | Real notification delivery; iOS's timing is not reliable enough for the suite |
| `PhoneRemindersTests.testNamedRemindersByHand` | `PORCHLIGHT_DELIVERY=1` | The same, for two households' reminders |
| `FoodMealsTests.testLiveRestaurantSearchByHand` | `PORCHLIGHT_LIVE_MAPS=1` | Needs the network and Apple Maps' own answer |
| `PhoneHouseholdTests.testImNewHereAgainAndAgainByHand` | `PORCHLIGHT_NEW_HERE=1` | A twelve-launch reproduction for a failure not yet explained ("Known and not yet explained") |
| `PhotoMigrationTests`, "A copy of the wall's real data keeps every photo file's bytes in a row" | `PORCHLIGHT_REAL_DATA_DIR` is set | Runs against a copy of the household's real data, which is never in the repository |
| `SyncMigrationTests`, "A copy of the wall's real data migrates without losing anything" | `PORCHLIGHT_REAL_DB` is set | The same |

A phone class on the iPad, or a wall class on the iPhone, also skips itself, but `scripts/test.sh` never sends a class to the wrong device, so those skips do not appear in a run.

## Flaky tests

Every test that failed and then passed with nothing changed, with its owner, what was found and what was done.
A test listed as quarantined is skipped in the suite and has a date by which it is fixed, moved down or deleted ("Tiers", rule 4); one that was fixed the day it was seen is listed as fixed, so the cause is not found twice.

| Test | Seen | Owner | Cause | Done | State |
|---|---|---|---|---|---|
| `ScrollingTests.testTouchesKeepTheWallAwake` | November 21, 2026, on the release line (run 44905599973, 146 s where it takes 51 to 58); the same commit had passed its full run an hour earlier | The agent on `tests/pyramid` | The test raced two clocks: it touched the wall every 4 seconds of a 12 second "minute" and then asserted Ambient had stayed away. In the failing run the touches came 10 seconds apart, and then one drag took 51 seconds on the hosted Mac, so the wall's timer rightly ran out. The app was right and the test was wrong: it broke hard rule 1 from the other side, by letting the outcome depend on how fast the test itself ran | The rule moved to `IdleRuleTests` (dates handed in, seen failing with the rule broken). The UI test was rewritten as `testTouchesReachTheIdleWatcherAndAnUntouchedWallGoesToAmbient`: one launch with a ten minute wait where a drag must be counted by the idle watcher, one with a three second "minute" where Ambient must come, each a one-sided wait | Fixed the same day; not quarantined |

### Infrastructure failures

A job can go red without a test having failed.
Each kind seen is listed here with what the scripts now do about it, so the next one is recognised; none of these is a flaky test, and none is retried in a way that could hide a test's failure.

| What the job said | Seen | What it was | What happens now |
|---|---|---|---|
| "The test runner crashed while preparing to run tests: PorchlightUITests-Runner at -[XCTWaiter(StallHandling) handleStalledWait:]", then "UI phone: 0/1 passed, 1 failed" | November 20, 2026, and November 21 (run 44909007366, Phone UI 1 of 3), the first class of the same phone shard both times; on the 21st the Mac's free memory fell from 63% to 19% and swap began just before | The test runner died before any test started, on a Mac short of memory | `scripts/test.sh` runs the suite once more when the log says the runner failed to start and holds no "Test Case ... started" line (`scripts/lib/runner-start.sh`), keeping the first log as `<suite>-never-started.log`. A second time fails saying "The test runner crashed before any test started, twice". A runner that dies after a test has started is never run again by this |
| "Truncated tar archive" in "Unpack the build" | November 21, 2026 (run 44900372201, Wall smoke), while the other jobs of the run unpacked the same build | One download of the build arrived cut short and was reported as a success | The download is checked against the build job's size and SHA-256 and fetched again up to twice (`scripts/ci/unpack-build.sh`); then it fails saying "The build's download was corrupted" |
| "The operation was canceled" in "Boot the ipad", and nothing else | November 20, 2026, twice, in jobs that had also built on the same Mac, with free memory near its lowest; November 21 (run 44926520830, Wall smoke), in a job that had not built, after the settle experiment's launch took 406 seconds and swap began | A boot step that stalled on a Mac short of memory until the job was cancelled from outside, with no word of where. The third shows it does not need a build on the same Mac, as the first two were thought to; what the three share is the 13-inch iPad simulator's first minutes on a 7 GB Mac, with memory falling | Each stage of the boot has its own limit (`scripts/ci/boot-simulator.sh`, `scripts/lib/stage.sh`): booting, 540 seconds, and the first uninstall answering, 150. A stage that stalls is named, the simulator is shut down, erased and booted once more, and a second stall fails the job saying "The ipad simulator stalled twice, first at ... and then at ...". The step's own 25 minute limit is only the backstop |
| "Failed to launch", "Failed to get launch progress", "does not have a process ID", "Failed to terminate", with no crash report | Several runs a day on the hosted Macs | XCTest could not start, or quit, the app for one test | That test runs once more on its own, and the summary says "passed on a second launch" (`scripts/lib/launch_retry.py`); any other failure stands |

`zsh scripts/ci/check-runner-start.sh`, `zsh scripts/ci/check-unpack-build.sh` and `zsh scripts/ci/check-boot-simulator.sh` check the first three rules against sample logs, a stand-in download and a stand-in simulator, and run with every build.

**An experiment that was tried and taken out the same day, November 21, 2026: letting a fresh simulator settle.**
The two runner crashes above, and the two lost-keys failures in "Known and not yet explained", all happened in the first test class of a job, minutes after its simulator booted.
So for one commit `scripts/ci/boot-simulator.sh` launched Settings, waited 15 seconds and quit it before the tests.
It did harm.
In the one full run with it (44926520595) it cost 23 to 60 seconds a job, where 20 were expected, because launching an app on a simulator that new is itself slow.
In the push run of the same commit (44926520830, Wall smoke) the launch took 406 seconds, with the Mac's free memory falling from 61% to 49% and swap going from nothing to 1.4 GB while it waited, and the job was cancelled in its boot step: the step meant to protect the first test had become the thing that stalled.
A new simulator is still busy for minutes after it says it has booted, and asking it to launch an app then adds to the load that causes these failures; it does not get it out of the way.
Do not bring it back in that form.
If the first class after a boot keeps failing, the candidates left are waiting for the simulator to go quiet without asking anything of it, and putting a class that does not type first in each share.

### Tests that wait on the app's own timers

The idle test was the only one that could fail by being slow against a timer that was right.
These others wait for something the app does on a timer; each waits one way only (for a thing to come, or to go, with a long limit), so a slow Mac delays them and does not fail them unless it stalls longer than the limit.
They are listed so that a failure in one of them on a slow run is read as this and not as the app.

| Test | Waits for | Limit | A stall that would fail it |
|---|---|---|---|
| `ScrollingTests.testTouchesReachTheIdleWatcherAndAnUntouchedWallGoesToAmbient` | A touch to be counted; Ambient to come after 3 seconds untouched | 30 s; 120 s | Over 30 s to count a touch, or two minutes to look |
| `SyncSettingsTests.testChecksTickOnAnUntouchedWall` | Three sync checks to be counted | 45 s | The app's poll loop starved for most of 45 s |
| `HouseholdTests.testRowsFromPhonesAreTaggedAndArrivalsNamed` | An arrival's toast to come a few seconds after launch, and to go by itself | 15 s to come, 12 s to go | A look at the screen that takes longer than the toast stays, so it is never seen; or over 12 s for it to go |
| `LoggedEntryTests.testFixingAWalkFromToday` | A celebration to come, and to go by itself | 15 s each | Over 15 s for either |
| Every test that taps a toast's Undo or Open (`tapToastAction`) | The toast still being there when the tap lands | Toasts stay 30 s in UI tests (`PORCHLIGHT_TOAST_SECONDS`) | Over 30 s between the action and the tap |

The second kind in the third row, and the last row, are the same shape as the idle test: something must be caught before the app's timer takes it away.
They have room (30 seconds, where a tap normally lands in two), and the 51 second stall of November 21 would have failed them too; if one does fail that way, give the app a debug way to hold the thing until the test has seen it, as `PORCHLIGHT_TOAST_SECONDS` began to, and do not lengthen a sleep.

## Known and not yet explained

A failure that could not be reproduced is written down here with what was ruled out, so the next occurrence is recognised and not rediscovered.

### "I'm new here": the name field shows its cursor, the keyboard is up, and typed keys never arrive

- **Seen**: `PhoneHouseholdTests.testImNewHere`, twice on November 20-21, 2026, on two unrelated branches (runs 44871628859 and 44864042037), on hosted Macs on iOS 27.2.
  Not seen before that day.
- **What the artifacts show**: the same steps as a passing run.
  "I'm new here" is tapped, the field appears and reports the keyboard focus by itself (the app focuses it, so the test never taps it), and `A`, `v`, `a` are typed three times over; the field stays empty each time.
  The recording's last frame shows the row picked, the cursor in the empty field and the keyboard up.
- **The code in question**: `WhoAreYouView` asks for the field's focus in the same update that adds the field (`choice = .new; nameFocused = true`).
- **Ruled out**:
  - The first responder.
    Hosted in the unit bundle, ten times, the text field is the window's first responder at once after the row is picked, and text given to the first responder reaches the name.
    Whatever loses the keys is between the keyboard and the field, which a hosted screen cannot see.
  - The screen alone.
    Twelve fresh launches in a row, one try at typing each, lost no round, twice (runs 44877585751 and 44877595687, 24 launches).
  - Memory.
    Both failing Macs had 48% and 51% of memory free and no swap at the time (the heartbeat lines).
  - The test before it.
    `testHeaderAndSlotsLargestText` ran just before it in both failures, but also in the runs that passed: the class runs in alphabetical order.
  - Asking for the focus later.
    A change to focus the field a turn after it appears was tried and taken out again: with no failure in 24 launches of the old code there was nothing for it to be measured against.
- **What both failures share, and the leads left**: `PhoneHouseholdTests` was the first class in its job both times, so this was the first time the keyboard came up on a simulator booted about three minutes earlier, and it came up for a field the app focused, not one a tap focused.
  No other test meets a cold keyboard that way: every other field is tapped first.
  The same was true of a run that passed (44860696474), and in another that passed (44828667552) the class ran later in its job but was still the first to bring the keyboard up, so it is a condition, not a cause.
- **Whether a person can hit it**: not shown either way.
  A phone's keyboard is not cold the way a simulator's is three minutes after boot, which makes it less likely, not impossible.
- **What may hide it now**: the typing helper (`type(_:into:in:)`) taps the field again before a second try.
  That is right for the tests, and it means this failure would now pass on its second round.
  If a new member reports a name field that looks ready and takes no keys, or the by-hand reproduction loses a round, this is that; the reproduction never taps and never retries.

## Budgets

Measured on GitHub's hosted Macs (3 cores, 7 GB, iOS 27.2), run 44828667552 of November 20, 2026, the commit this work started from.
The first batch (run 44860696474) took 42 minutes from start to the last job's end, against 48.6, with the shards reweighed and three tests trimmed.
By run 44883476613 of November 21, with the looks of the week, the care sheet and the dishes hosted and `reveal` rewritten, the UI tests summed to 6,805 seconds over 154 tests (8,041 over 150 at the start), five tests were over 120 seconds (seven), and the longest was 249 seconds (746).
By run 44900373348 later that day, with the tabs' and the food's looks at one launch each and the duplicates gone, they summed to 6,031 seconds over 145 tests, a quarter less than at the start: 28 tests over 60 seconds (38), two over 120 (seven), the longest 151, a median of 33, and the five jobs between 1,108 and 1,276 seconds of tests each, where the longest had been 2,153.
By run 44926520595 that evening, with the household's, Today's and the dish form's looks at one launch each and seven small tests folded into their neighbours, they summed to 5,735 seconds over 136 tests: 26 over 60 seconds, none over 120, the longest 120.
The jobs had drifted apart again (878 to 1,506 seconds), so the shards were weighed from that run, and the unit tests' 368 seconds are now counted into the wall's first share, which runs on their Mac.
Each test job spent about ten minutes outside its tests in that run (the two longest: 611 and 592 seconds), which is now the larger part of what a full run can still lose.

| | Measured |
|---|---|
| UI tests that ran | 150 (and 2 that only run by hand) |
| Sum of UI test seconds | 8,041 (134 minutes), over 5 jobs |
| Median UI test | 35 seconds |
| UI tests over 60 seconds | 38, holding 4,407 seconds (55% of the time) |
| UI tests over 120 seconds | 7, holding 1,722 seconds (21% of the time) |
| Looks tests (night, largest text, status bar) | 23, holding 2,543 seconds (32% of the time) |
| Unit tests | 572 in a 398 second step, of which about 200 seconds are the tests themselves |
| Build job | 6.8 minutes |
| Longest test job | 41.7 minutes (37 minutes of tests) |
| Whole run, no queueing | 48.6 minutes; about 70 when the five Macs are shared with other branches |

Targets:

- **Full suite: 30 minutes from push to green with no queueing.**
  That is the 7 minute build, 5 minutes to boot and unpack, and no shard over 18 minutes of tests.
  With three phone shards and two wall shards, that is at most 3,240 seconds of phone tests (5,662 today) and 2,160 of wall tests (2,390 today): 5,400 seconds in all, a third less than today.
- **A push to a working branch: about 20 minutes.**
  The 7 minute build, 5 minutes to boot and unpack, and then the unit tests (about 7 minutes) or one shell's smoke tests (4 to 7 minutes), each on its own Mac ("Tiers").
- **Per UI test: 60 seconds on a hosted Mac, and never over 120.**
  The median is 35, so 60 leaves room for a real journey; the 38 tests over it are where more than half the time goes.
  A long test is also a fragile one: the only failure of run 44860696474 was the suite's longest test, 322 seconds into it.

When a UI test goes over 60 seconds, in this order:

1. Move down every assertion the four questions send to a unit test, and delete the steps that only served them.
2. Start nearer the screen with a debug launch argument instead of walking there.
3. Merge it with a test that makes the same launch and visits the same screen, if the journey is the same.
4. If the time is in looking at the screen (a `reveal` loop on a long page, `descendants(matching: .any)` on a big tree, the largest text size), query by identifier inside a container, and scroll less.
5. If it is still over, split it into two journeys; a test over 120 seconds is a failure to fix, not a number to record.

### Where a job's time outside its tests goes

Measured step by step in run 44926520595 (November 21, 2026), the five test jobs of a full run.

| Job | Whole job | Tests | Boot step | Of which: boot, first uninstall answering, settle | Fetch and unpack the build | Inside the Test step but not a test |
|---|---|---|---|---|---|---|
| Phone UI 2 of 3 | 2,098 s | 1,506 s | 422 s | 254, 116, 46 | 20 s | 126 s |
| Unit and Wall UI 1 of 2 | 2,113 s | 1,133 s and the unit tests' 368 s step | 434 s | 100, 270, 60 | 77 s | 82 s, and about 170 s of the unit step |
| Phone UI 3 of 3 | 1,425 s | 878 s | 422 s | | 20 s | 84 s |
| Phone UI 1 of 3 | 1,573 s | 1,154 s | 192 s | | 19 s | 186 s |
| Wall UI 2 of 2 | 1,725 s | 1,063 s | 246 s | | 6 s | 383 s |

What it shows:

- **Booting a brand-new simulator is most of it: 3 to 7 minutes a job.**
  Each job creates its simulator and boots it for the first time; the boot takes 100 to 254 seconds and the simulator then takes 38 to 270 more before it answers its first request.
  The settle step added 23 to 60 seconds and is gone.
- **Starting and ending `xcodebuild` is the second part: 1.5 to 6 minutes a job** (installing the app and the runner, the first launch, writing the result bundle, and a second run of any test that could not start its app).
- **Fetching the build is small**: 6 to 77 seconds.
- Over the five jobs that is about 50 minutes of Mac time outside the tests in a run whose tests take 96, and 7 to 10 minutes on the longest job.

What could shorten it, none of it tried or decided:

- Fetch the build while the simulator boots, not after it: up to a minute a job, and no risk.
- Fewer, longer jobs: four test jobs make four boots, and wait for fewer Macs, at the cost of a longer longest job (about 1,770 seconds of tests for two phone shares against 1,230 for three).
- Keep a simulator that has already had its first boot from one run to the next, so a job starts one that is ready: the largest saving and the least certain, since a cached simulator is several gigabytes and may not survive a new Xcode.

### Where a slow test's time goes

Each test's steps are in its job's `ui-phone.log` or `ui-wall.log` (the `results-…` artifact), one line a step with its time, so a slow test is read, not guessed at.
Three causes account for most of what was found on November 20, in run 44828667552:

- **`reveal` dragging to its limit without getting there.**
  In the run of November 20, sixteen calls in the phone suite used all fourteen drags, 557 seconds in all (7% of the UI suite), and the tap that followed still worked, because XCUITest scrolled to the element itself at the tap.
  They were mostly a sheet's own bottom button (Save, Done), which the old `reveal` never counted as in view.
  `reveal` was rewritten on November 21 to stop when its drags make no progress and to know a sheet's floor; `PhoneSetupTests.testACompanionInTheWallsEditor` went from 143 seconds to 48 with it, and PhoneFoodTests from about 1,180 to 800.
  When a test is slow, count its drags in the log first.
- **`waitToSettle` on an element that is off screen.**
  It waits for an unchanged frame that is also hittable, so an element below the fold uses all twenty looks, each a second or more on a long page.
  Reveal first, then settle.
- **Changing the look.**
  A test in the night look pays for quitting the app before it (20 seconds in one case), quitting it again in teardown (11) and switching the look back (4), so the night look and the largest size of one screen belong in one test.

A class's time moves by a fifth and more between two runs of the same code on these Macs (PhoneRemindersTests took 384 seconds in one run and 217 in the next, untouched), so compare a test with itself over several runs before calling a change a saving, and update `scripts/lib/ui-test-seconds` only for a drift that lasts or a class that is new.

## Examples from this repository

| This check | Lives in | Because |
|---|---|---|
| The phone's sync banner says "iCloud isn't allowed on this iPhone" when the account is restricted | `ArrivalsTests.banners` (unit) | The words are computed from the status by `PocketSyncNotice.pick`; the app need not launch once per status |
| The banner's "Choose" opens the choice in You | `PhoneHouseholdTests.testSyncBannersOnToday` (UI) | A tap, a sheet and navigation; only the real app shows whether the button is wired |
| Settings says why iCloud is missing, for each way it can be | `SyncWordingTests.missingICloud` (unit) | Three strings from one switch |
| The line and the gear's dot are on screen for a missing iCloud | `SyncSettingsTests.testAMissingICloudSaysWhy` (UI, one state) | Proves the status reaches Settings and the rail, once |
| "Offline since 4:55 PM" today, "Offline since Nov 6" after midnight | `ArrivalsTests.offlineSince` (unit, swept every half hour in two time zones) | A rule about the day's edge; a UI test runs at one time of day |
| A slot is owed only if its window closes after the companion arrived | `OwedSweepTests` (unit, swept) | The bug hid by hour |
| A tap on a Where pill adds a kind, and never removes the last one | `MealSourcesTests` (unit) | A rule with branches |
| Picking two kinds, saving, and seeing both on the meal's page | `PhoneFoodTests.testWhereTakesSeveralKinds`, `FoodMealsTests.testEditingWhereIntoTwoKinds` (UI) | The journey, once per shell |
| Each digit typed on the number pad counts at once | `TimeEntryTests` (unit) | The model of the pad, with no pad |
| The number pad opens instead of the iPad's keyboard | `TimeFieldTests.testTypingAMealTime` (UI) | Only the real app shows which keyboard came up |
| The restaurant field stays above the keyboard | `FoodMealsTests.testDineOutWithARestaurant` (UI) | Keyboard avoidance is real layout |
| A join that fails offline leaves nothing half joined | `JoinFlowTests` (unit) and `PhoneHouseholdTests.testAJoinThatFailsCanBeTriedAgain` (UI) | The state is the flow's; the banner and its "try again" tap are the failure path a person meets |
| Granting calendar access through the system prompt | `FirstRunTests` (UI) | A system prompt cannot be reached from a unit test |
| Every widget family in every look | `WidgetRenderTests` (unit bundle, `ImageRenderer`) | Widgets cannot be driven by UI tests, and a render takes milliseconds |
| The time pill goes under "Started" instead of squeezing it, at every text size | `TimeFieldLayoutTests` (unit bundle, hosting controller) | A component's own layout rule; twelve sizes in a fifth of a second |
| The time pill on the real care sheet at the largest size, in light and dark | `PhoneTabsTests.testFixingAWalkLooks` (UI, looks) | One look at the row among everything else on the sheet |

## Appendix: the audit

Every UI test, with its seconds on a hosted Mac (run 44828667552) and a verdict.

- **Keep**: it is a journey, or a check only the real UI can fail.
- **Merge**: its launch and screen are another test's; fold its assertions into that one and drop the launch.
- **Down**: its assertions are values the code computes; the unit test named holds them, and the UI test goes or shrinks.
- **Delete**: another UI test already makes the same assertions.
- **By hand**: it depends on the network or on delivery timing.

"Saves" is the projected saving in seconds on a hosted Mac, from the measured cost of a launch (15 to 20 seconds) and of the steps removed.
It is a projection until the row says "done", where it is the measured difference.

The status column says what has happened: "done" (migrated on `tests/pyramid`, the unit test seen failing when the behaviour is broken), or blank (verdict only).

### Phone

#### PhoneFoodTests (1,200 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testWeekAndDiary | 22 | Snap is hittable; "On this day"; "added by you"; the restaurant's name | Merge into testMealPage (same launch); who added and where from are `PocketFoodTests` | 15 | |
| testMealPage | 59 | Pager swipes between photos; whole photo opens and closes; an edit shows at once | Keep | | |
| testSnappingAMeal | 46 | Camera ask, shutter, details, save, toast, new meal | Keep (smoke) | | |
| testChangingWeeks | 121 | Back a week, a meal opened and Back to the same week, a past slot filled and kept in its week, back to this week | Keep: the journey, new on November 21 (seconds from run 44899330787). It is one second over the 120 limit on its first measured run; if it stays there, split filling the past slot into its own test | | |
| testWhereTakesSeveralKinds | 115 | Seven toggle steps, then save, page says both, editor shows both | Down for the toggle rules (`MealSourcesTests`: "A tap adds a kind…", "On a new meal the first tap replaces…"); the journey stays: pick two, save, see both, edit | 35 | done |
| testWhereLooks | 84 | Where pills in dark and at the largest size | One launch, the night look at the largest size (was two) | 40 | done, 37 s measured |
| testCoverAndReframeWhenSnapping | 119 | Two shots, second made cover, reframed, saved framed | Keep | | |
| testCoverAndReframeWhenEditing | 116 | Same in the editor, saved and shown again | Keep | | |
| testReframingAnotherPhotoWhenEditing | 42 | Reframe from the action sheet frames that photo only | Merge into testCoverAndReframeWhenEditing (same launch and editor); the order and framing rules are `MealPhotoOrderTests` and `PhotoFramingTests` | 35 | |
| testPhotoRowAndReframeLooks | 185 | Row and reframe in dark and largest, in four launches | One launch of the editor in the night look at the largest size, Done still in reach; the new meal's row is the same component and is not launched for again. It took 249 seconds in run 44883476613 | 180 | done, 94 s measured |
| testCameraTurnedOff | 48 | Camera denied: Settings, Photos, no photo | Keep (failure path) | | |
| testEmptyHousehold | 16 | "Nothing in the diary this week" | Delete: `PhoneSetupTests.testStartingAHouseholdOnThisPhone` asserts the same text on the same tab | 16 | done |
| testNightLook | 31 | Shots | Keep (looks) | | |
| testPaperUnderTheStatusBar | 76 | Four screens scrolled, nothing under the clock, four launches | Merge to one launch by navigating diary, meal, camera, details | 45 | |
| testPaperUnderTheStatusBarAtNight | 85 | Same in dark | Merged with the largest size into `testPaperUnderTheStatusBarAtNightAtTheLargestSize`: the two looks share their four launches | 80 | done, 92 s measured for the merged test |
| testPaperUnderTheStatusBarAtTheLargestSize | 81 | Same at the largest size | Merged as above. A hosted screen has no status bar, so this stays a UI test | | done |
| testLargestText | 75 | Snap and Save whole on screen | Keep (looks) | | |

#### PhoneTabsTests (1,022 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testSeveralCompanionsGoToAGrid | 19 | Three cards, each with its one tap | Keep | | |
| testCompanionWeek | 58 | Week opens from a card; a missed slot is caught up | Delete once `PhoneWeekTests` is unfrozen: it opens the week from the card in every test, and `PhoneCatchUpTests.testCatchingUpFromTheWeek` is the same catch-up; "Walker of the week" is `CompanionWeekTests` | 58 | |
| testPitchInAndAddingAChore | 50 | Yours, everyone, add a chore, it is mine today | Keep (smoke) | | |
| testAWidgetLinkOpensLists | 48 | `porchlight://lists` and `://today` | Merge into testListsAndDinners (open the link instead of tapping the tab) | 30 | done |
| testListsAndDinners | 52 | Add, check, dinners' needs, counts | Keep; the counts and aisles are also `PocketTabsTests` | | |
| testGlowAndCashingIn | 28 | Cash in asks once, celebrates, starts again | Keep | | |
| testNextSevenDays | 40 | Row opens the page, grouped by day | Merged into `testLooks`, which reaches the page from Today and keeps "grouped by day"; grouping is `PocketTabsTests` | 25 | done |
| testChoosingCalendars | 33 | Why before asking; sharing choices | Keep (permission) | | |
| testCalendarsFromYou | 45 | Calendars row in You opens the page | Merge into `PhoneTests.testYouSheet` (same launch); it settled the row before revealing it, now the other way round | 30 | done |
| testFixingAWalkFromToday | 70 | Fix, saved, remove asks, slot open again | Keep | | |
| testFixingAWalkFromTheWeek | 76 | Diary row opens, Keep it backs out, remove | Keep | | |
| testFixingAWalkOnASharedScreen | 30 | Names, with no "You" | Keep | | |
| testFixingAWalkLooks | 158 | Fix sheet in dark, largest, largest dark | One launch at the largest size for what only the real sheet shows (the pill among everything else, Save within reach); the looks are hosted in `PocketCareSheetScreenTests` | 100 | done, 38 and 63 s measured (runs 44871628859, 44871628840) |
| testTheTimePillGrowsWithText | 100 | Pill grows, clear of "Started", on screen; three launches at the largest size | Merge into testFixingAWalkLooks, which already opens the same sheet at the same size in both looks; the rule at every size is `TimeFieldLayoutTests` | 85 | done |
| testNightLook | 39 | Shots | Merged with testLargestText into `testLooks`: one launch in the night look at the largest size; the pages themselves are hosted in `PocketTabsScreenTests` | 60 | done, 78 s measured for `testLooks` |
| testPaperUnderTheStatusBar | 95 | Four tabs scrolled, at two sizes | Keep, and take `PhoneTests.testYouOnEveryTab` | | |
| testLargestText | 81 | Field, cash-in whole on screen | Merged into `testLooks`, which keeps both assertions on the real screen | | done |

#### PhoneWeekTests (953 s)

Unfrozen on November 21, when the dish editor landed.

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testTappingThePawTrail | 74 | A logged, a missed and an open dot each open the right sheet | Keep; the dots' labels are `CompanionWeekTests` | | |
| testAMealInTheDiaryAndTheTrail | 72 | A dinner logged from the trail shows in trail and diary | Keep | | |
| testWater | 30 | Water has its week | Down: "Log a refill" and "Water diary" are `CompanionWeekTests`; keep as a tab tap inside testAMealInTheDiaryAndTheTrail | 20 | |
| testWeekLooks | 746 | Three looks times three routines, each scrolled top to bottom and back | One launch, night look at the largest size, for what only the real page shows: each routine's tab and log button can be scrolled to and reached, water included. The whole page in each look, for walks and meals, is hosted in `PocketWeekScreenTests`. It took 385 to 786 seconds from run to run and failed twice on November 20 for reasons that were not the app's (in run 44860696474, on a scroll that fell short) | 650 | done, 88 s measured (run 44883476613) |
| testAFirstWeek | 30 | First week's words | Down: all three sentences are `CompanionWeekTests`; keep one shot inside testWeekLooks | 30 | |

#### PhoneHouseholdTests (587 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testSwitchingHouseholds | 26 | Header, list, one tap switches every tab | Keep | | |
| testSwitcherNightLook | 23 | Shots | Merged into `testLooks`: three launches in the night look at the largest size, one for each place a person starts from (joining, a member's Today with a banner, two households) | 15 | done |
| testHeaderAndSlotsLargestText | 24 | Header whole; slot reads without a dot | Merged into `testLooks`, which keeps both assertions | 15 | done |
| testOneHouseholdHasNoSwitcher | 27 | No switcher; start another | Keep | | |
| testTheWelcomeExplainsBothWaysIn | 14 | Two doors, and how to join | Delete: `PhoneSetupTests.testStartingAHouseholdOnThisPhone` opens the same screen and taps the same door; move "Or scan your family's code" there | 14 | done |
| testJoiningFromAnInvite | 36 | Preview, who, bringing in, Today | Keep (smoke) | | |
| testImNewHere | 35 | A new name joins as that person | Keep | | |
| testAnAccountTheHouseholdKnowsSkipsWhoYouAre | 21 | The who step is skipped | Down: `JoinFlowTests` "An iCloud user who already has a phone in the household keeps the same person" | 21 | done |
| testAJoinThatFailsCanBeTriedAgain | 26 | Banner, nothing half joined, try again | Keep (failure path) | | |
| testARemovedHouseholdSaysSoOnce | 16 | Says so, then the welcome | Keep | | |
| testSyncBannersOnToday | 91 | Six launches, one per sync state, each banner's title | Down for the titles (`ArrivalsTests.banners`, `offlineSince`); keep two launches: a member sees whose iCloud is full, and "Choose" opens the choice | 60 | done, 23 s measured |
| testYouListsPeopleAndInvites | 33 | People, invite, share sheet | Keep | | |
| testShowingTheCodeOnThePhone | 21 | The code is drawn | Keep | | |
| testWithSyncOffTheHouseholdIsOnThisPhoneOnly | 38 | Says so, the switch turns it on, invites can go | Keep; the words are `HouseholdHomeTests` | | |
| testAMemberSeesWhoseICloudItIs | 18 | Owner's iCloud; no invite for a member | Merge into `PhoneSetupTests.testAMemberLeaves` (identical launch) | 18 | done |
| testRenamingThisPhone | 35 | Type a name, saved | Keep | | |
| testNightLook | 52 | Shots | Merged into `testLooks`: three launches in the night look at the largest size, one for each place a person starts from (joining, a member's Today with a banner, two households) |  | done |
| testLargestText | 50 | Join and banner fit | Merged into `testLooks`, which keeps its assertions; it was the slowest test in the suite at 151 seconds in run 44900373348 |  | done, 61 s measured for `testLooks`, where the four it replaced took about 250 |

#### PhoneSetupTests (511 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testStartingAHouseholdOnThisPhone | 76 | A2 from a fresh install to Today and every empty tab | Keep (smoke) | | |
| testAnEmptyTodayOffersSetup | 19 | Empty Today leads to Household | Keep | | |
| testSettingUpTheHouseholdFromThePhone | 153 | Add, rename, archive a person; a chore; a list | Keep, split in two (people; chores and lists): over the limit | 30 | |
| testACompanionInTheWallsEditor | 147 | Companion and routine editors open, rename saves | Keep. 94 of its seconds were two `reveal` calls dragging fourteen times each without getting there; with the rewritten `reveal` it took 48 and 68 seconds (runs 44875496226 and 44883476613) | 95 | done by the rewrite |
| testAMemberLeaves | 36 | Leave, confirm, welcome | Keep | | |
| testTheOwnerIsPointedToRemovingSomeone | 42 | Owner is sent to remove; person stays | Keep | | |
| testStorage | 21 | Breakdown names photos; whose iCloud | Keep (the page) | | |
| testStorageWhenTheOwnersICloudIsFull | 17 | Paused banner names the owner | Down: extract the banner's words from `PocketLeaveAndStorage` and test them with `HouseholdHomeTests` | 17 | |

#### PhoneRemindersTests (384 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testSaysWhyBeforeAsking | 58 | Why, then allow, then the choices | Keep | | |
| testTurnedOff | 52 | Denied: one way to fix | Keep (failure path) | | |
| testChoosingReminders | 54 | A slot's choice and the chores switch | Merge into testSaysWhyBeforeAsking, which ends on the same page | 45 | |
| testDeliveryByHand | 0 | Real delivery | By hand already | | |
| testNamedRemindersByHand | 3 | Real delivery | By hand already | | |
| testNightLook | 147 | One shot | Merged with testLargestText into `testLooks`: one launch in the night look at the largest size. The page reads the phone's notification permission itself, so it can't be hosted until that has a seam | 150 | done, 43 and 67 s measured for testLooks |
| testLargestText | 69 | The choice is whole on screen | Merged into `testLooks`, which keeps the assertion | | done |

#### PhoneCatchUpTests (378 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testCatchingUpFromTodaysBanner | 105 | Banner, sheet for the slot, saved as chosen | Keep | | |
| testCatchingUpFromTheWeek | 88 | Missed row, sheet, saved | Keep | | |
| testCatchingUpLooks | 186 | Sheet in dark and largest, each after removing a walk by hand | Hosted: `PocketCareSheetScreenTests` draws and checks the catch-up sheet in four looks; the two journeys above stay as the real sheet's UI tests | 186 | done, gone from the suite |

#### PhoneDishesTests (332 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testDishesAndAPlace | 71 | List, dish, favourite, place | Keep | | |
| testSearch | 28 | Typing finds dishes and places | Merge into testDishesAndAPlace; matching is `DishBookTests` | 20 | |
| testEveryoneRatesAMeal | 38 | Own face saved and shown | Keep | | |
| testRenameIntoAMergeAndRemoveWithUndo | 82 | Rename offers a merge; remove with undo | Keep | | |
| testEmpty | 22 | Empty state | Keep | | |
| testNightAndLargestText | 91 | Five launches for five shots | Hosted: `PocketDishesScreenTests` draws and checks the list, a dish and a restaurant in four looks; the journeys above stay as the real screens' UI tests | 91 | done |

#### PhoneTests (295 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testPickingWhoYouAre | 19 | Asks once, greets | Keep | | |
| testTodayWithSomethingDue | 28 | Order of Today's cards | Keep; the order is `PocketTodayTests` | | |
| testOneTapLogAndUndo | 21 | One tap, toast, undo | Keep (smoke) | | |
| testCareSheet | 22 | More opens the sheet; save | Keep | | |
| testCatchingUp | 21 | Banner, sheet, saved | Delete: `PhoneCatchUpTests.testCatchingUpFromTodaysBanner` is the same journey, in full | 21 | done |
| testCheckingChores | 29 | Check, undo, shared chore credited | Keep (smoke) | | |
| testAllClear | 30 | A finished day folds to one line | Keep for now: "Yo-Yo is all set" and "Nothing else for you today" are written in the views, so nothing below the UI can say them yet; `PocketTodayTests` holds when a card folds | 30 |  |
| testYouSheet | 29 | Household, role, change who I am | Keep | | |
| testYouOnEveryTab | 32 | The avatar is on each tab | Merge into `PhoneTabsTests.testPaperUnderTheStatusBar`, which visits each tab | 30 | done |
| testNightLook | 24 | Shots | Merged with testLargestText into `testLooks`: one launch in the night look at the largest size; the care sheet's look is hosted |  | done |
| testLargestText | 41 | Log button whole and full width | Merged into `testLooks`, which keeps its assertions |  | done, 41 s measured for `testLooks` |

### Wall

#### FoodMealsTests (320 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testSeveralDishesInOneMeal | 27 | Stack opens, other dish one tap away, add another | Keep | | |
| testDineOutWithARestaurant | 48 | Suggestions above the keyboard; saved note | Keep (keyboard) | | |
| testWhereTakesSeveralKinds | 37 | Toggle rules, then saved "at work" | Down for the toggle rules (`MealSourcesTests`); the journey stays, since the saved note's "at work" is built in the view and only this test sees it: pick two, save, read the note | 37 | done |
| testEditingWhereIntoTwoKinds | 29 | Only kind can't come off; two kinds saved and shown | Keep | | |
| testLiveRestaurantSearchByHand | 34 | Maps suggests places; used to skip itself offline | By hand: skipped unless `PORCHLIGHT_LIVE_MAPS=1`, and then it fails when Maps can't be reached | 34 | done |
| testEditingAMealIntoDiningOut | 34 | Field above the keyboard; typed name kept | Keep (keyboard) | | |
| testSeveralDishesOnTodaysPlates | 26 | Today's plate opens its stack | Keep (smoke) | | |
| testSwipingBetweenDishesInTheWeek | 31 | Swipe changes the top dish | Keep (gesture) | | |
| testOpeningAMealFromTheMonth | 25 | Day sheet gives way to the meal | Keep | | |
| testWritingDayNotesFromTheCaptureForm | 28 | To the page and back | Keep | | |

#### HouseholdTests (303 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testFamilyAndDevicesShowsEveryoneAndBothWaysIn | 48 | Rows, invite sheet, code | Keep (smoke); the rows' words are `FamilyTests` | | |
| testWithSyncOffTheHouseholdIsOnThisIPadOnly | 27 | Invite waits; link scrolls to the switch | Keep | | |
| testTheOwnerRemovesSomeonesPhone | 29 | Remove asks; the person stays | Keep | | |
| testRenamingThisIPadFitsAboveTheKeyboard | 63 | Save and title above the keyboard | Keep (keyboard) | | |
| testSetupAsksHowThisIPadIsUsed | 18 | Role step, shared screen picked | Keep for now: `FirstRunTests` asserts the same step and default, but only this test taps the other role; fold that tap into `FirstRunTests` when it is next touched | 18 |  |
| testSetupSaysWhereTheHouseholdLives | 31 | iCloud step with and without an account, two launches | Keep the launch without an account; `FirstRunTests` covers the other | 15 | |
| testRowsFromPhonesAreTaggedAndArrivalsNamed | 28 | Arrival toast comes and goes | Keep; the sentences are `ArrivalsTests` | | |
| testSampleMealsHaveTheirPhotos | 17 | Breakfast is on the week | Delete: five `MealPhotosTests` open that breakfast | 17 | done |
| testARestoredCopyWaitsForAChoice | 40 | Choice, never "send", keeping brings back the switch | Keep | | |

#### SyncSettingsTests (246 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testChecksTickOnAnUntouchedWall | 49 | Three polls on a wall nobody touches | Keep: real timers in the real app | | |
| testADifferentAccountAsksWhatToDo | 38 | Choice; dot comes and goes | Keep | | |
| testAFullICloudPausesSync | 44 | Paused, dot, nothing on Today | Keep (smoke) | | |
| testEachMissingICloudSaysWhy | 95 | Three launches, one per account state, each line whole | Down for the words and the dot's rule (`SyncWordingTests`); keep one launch as testAMissingICloudSaysWhy | 63 | done, 37 s measured |
| testAFreshInstallLooksForItsHouseholdFirst | 20 | Looking, then start fresh | Keep | | |

#### MealPhotosTests (220 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testShotsWaitInTheFormUntilSave | 35 | Nothing saves before Save; discard asks | Keep | | |
| testTheRemoveBadgeTakesTapsOverThePhoto | 26 | Badge wins the tap over the photo | Merge into testPagingAndEditingPhotosOfASavedMeal, which removes the same photo | 26 | done |
| testPagingAndEditingPhotosOfASavedMeal | 34 | Paging; cancel keeps; save removes | Keep | | |
| testTheViewfinderIsThePolaroidSquare | 20 | Viewfinder is square; shots under it | Merge into testShotsWaitInTheFormUntilSave (same screen) | 20 | done |
| testWholePhotoAndReframing | 35 | Whole photo; drag moves the square | Keep (gesture) | | |
| testReframingAnotherPhoto | 38 | Reframe frames that photo only | Merged with testMakingAnotherPhotoTheCover: the second photo is reframed, then made the cover, in one editor | 31 | done |
| testMakingAnotherPhotoTheCover | 31 | No duplicate; one cover | As above; the order rule is `MealPhotoOrderTests` |  | done |

#### DayAtAGlanceTests (197 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testCheckingOffAChoreOnToday | 54 | Who did it, done chip, timeline line | Keep (smoke) | | |
| testOpeningAChoreFromToday | 88 | A row opens the chore's sheet and closes | Merge into testCheckingOffAChoreOnToday (same launch); 88 seconds for one tap needs a look | 75 | done, 25 s measured for the merged test |
| testMomentsInTheWeek | 32 | Walks and meals open from the week grid | Keep | | |
| testChoresInTheCalendar | 23 | Lane opens a chore and updates | Keep | | |

#### PhotoFrameTests (160 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testChoosingThePorchView | 108 | Choice survives a relaunch, both ways, four launches | Keep as it is: the choice is kept in the simulator's defaults between tests, so the test has to end on Our photos again, and its second half is that. Its seconds are four launches of Settings and Ambient | 50 |  |
| testRemovingSeveralPhotos | 52 | Select three, remove, counts | Keep | | |

#### TimeFieldTests (135 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testTypingAMealTime | 43 | Pad not keyboard; then eight digit rules | Down for the digit rules (`TimeEntryTests`); keep open, type, Done | 15 | |
| testNightHoursCrossMidnight | 63 | Suggestion sets; "next day"; then puts both back | Keep as it is, for the same reason: it puts both hours back because the next test would read them | 20 |  |
| testARoutineWindow | 29 | A refused time is explained and can't be kept | Keep | | |

#### PitchInTests (128 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testFixingWhoDidAChore | 23 | Change who; board updates | Keep (smoke) | | |
| testCheckingOffASharedChore | 23 | Asks who; done by | Keep | | |
| testLoggingCareFromTheBoard | 26 | Done care opens its log to fix; care to do opens its own sheet | Keep; pinned to 5:20 pm, so it checks both on every run where it used to check whichever the time of day offered | | done |
| testCashingInOnGlow | 30 | Cash in; new round | Keep | | |
| testNewChoreWithAStartDay | 26 | Picker reads back; chore on the board | Keep; the summaries are `RecurrenceTests` | | |

#### CatchUpTests (124 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testCatchingUpFromYoYosWeek | 72 | Diary and trail catch up | Keep | | |
| testLoggingYesterdaysDinnerFromTheCalendar | 30 | Missed mark opens the sheet for that slot | Keep | | |
| testMissedCareInTheWeek | 22 | Missed slots are marked | Keep: the rule is `CareCatchUpTests`, but only this test shows the week grid drawing the marks | 22 |  |

#### LoggedEntryTests (114 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testFixingAWalkFromToday | 40 | Log, celebrate, fix who and how long | Keep | | |
| testLoggingAWalkSaysWhenItStarted | 26 | A suggestion sets the time, closes the card and is marked | Merged into testFixingAWalkFromToday, which is pinned to 5:20 pm now and says when the walk started before it saves; which choices are offered at each minute of the day is `LogTimeTests.suggestionsThroughTheDay` | 26 | done |
| testOpeningMealsFromToday | 23 | Timeline and plates open the meal | Keep | | |
| testFixingAWalkFromTheCompanionPage | 24 | Diary row opens; remove asks | Keep | | |

#### The rest of the wall

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| WallTourTests.testEditingAMeal | 32 | Name field above the keyboard; edit saved | Keep (keyboard) | | |
| WallTourTests.testHandwritingOnDayPage | 32 | Strokes, Done | Keep (gesture) | | |
| WallTourTests.testSheetsWithTheKeyboardUp | 44 | Two sheets' fields above the keyboard | Keep (keyboard) | | |
| WallTourTests.testScreens | 0 | Screenshots only | Not in the suite; `--tour` | | |
| CompanionEditorTests.testAddingARoutineFromSettings | 103 | Editor, routine, photo picker, save | Keep; over the limit, split at the photo picker | 20 | |
| FirstRunTests.testOnboardingWithRealCalendarAccess | 101 | First run with the real prompt | Keep (smoke); its length is the system prompt's | | |
| ScrollingTests.testSettingsScrollsToTheLastSection | 32 | Settings scrolls to the end | Keep (scrolling) | | |
| ScrollingTests.testTouchesKeepTheWallAwake | 55 | Touches hold off Ambient, timed against a 12 second "minute" | Down for the rule (`IdleRuleTests`, every time handed in); the UI test is now `testTouchesReachTheIdleWatcherAndAnUntouchedWallGoesToAmbient`: a real drag is counted by the idle watcher, and an untouched wall goes to Ambient, neither of which a slow Mac can fail. It went red on the release line on November 21 ("Flaky tests") |  | done, 34 s measured |
| WallDishesTests.testDishesAPlaceAndADish | 21 | Dishes, a place, a dish | Keep | | |
| WallDishesTests.testEveryoneSaysHowItWas | 21 | Own face saved | Keep | | |

#### PhoneDishEditorTests (307 s) and WallDishEditorTests (125 s)

Landed on November 21; seconds from run 44875496226.

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| PhoneDishEditorTests.testRestaurantMealWithTwoDishesFromLastTime | 66 | A restaurant, two dishes from last time, saved | Keep | | |
| PhoneDishEditorTests.testHomeMealTypedWithASuggestion | 50 | A typed dish, a suggestion taken | Keep (keyboard) | | |
| PhoneDishEditorTests.testAPhotoAloneIsAWholeMeal | 45 | A meal with no dish saves | Keep; the rule is `DishLinesEditTests` | | |
| PhoneDishEditorTests.testEditAddsAndTakesOffADish | 61 | An edit adds and removes a line | Keep | | |
| PhoneDishEditorTests.testTheFormAtNightAndAtTheLargestText | 84 | The form in two looks | One launch in the night look at the largest size, keeping the typed dishes and the field over the keyboard; the chips are the restaurant journey's. It took 133 and 158 seconds in full runs | 70 | done, 57 s measured |
| WallDishEditorTests.testRestaurantMealWithTwoDishesFromLastTime | 42 | The same journey on the wall | Keep | | |
| WallDishEditorTests.testHomeMealTypedWithASuggestion | 31 | The same on the wall | Keep (keyboard) | | |
| WallDishEditorTests.testAPhotoAloneIsAWholeMeal | 23 | The same on the wall | Merge into testHomeMealTypedWithASuggestion's launch, or leave: 23 seconds | | |
| WallDishEditorTests.testEditAddsAndTakesOffADish | 28 | The same on the wall | Keep | | |

### Unit suites that hold what a UI test would otherwise

These arrived on November 21 with the food diary's other weeks and handwritten titles, written to this document's rule from the start, so there is no UI test to move down: they are listed so the audit says where those checks live.
Seconds are from a local run of the unit suite; all of them together are under two seconds.

| Suite | Kind | Holds | The UI test beside it |
|---|---|---|---|
| `PocketFoodWeeksTests` | Pure functions, clock pinned and swept across the day, a daylight saving change and two time zones | Which seven days a week is, how far back the pager goes, which week a saved meal shows in, the pager's words | `PhoneFoodTests.testChangingWeeks`: back a week, a meal opened and Back to the same week, a past slot filled, back to this week |
| `PocketFoodScreenTests` | Hosted whole screen | The diary on this week, last week and an empty week, in four looks: fits across, says which week | The same test; its shots are `food-week-<n>-<look>.png` |
| `HandwritingTests` | Core Text ink bounds | Every handwritten title's ink inside its `Text`'s box, at every Dynamic Type size and the wall's sizes, with and without the Chinese and Japanese companion | None: no UI test can see ink |
| `HandCompanionTests` | Pure functions and a fake font download | Which companion face a reader gets, its weights and line heights against Caveat's, and a download that fails or arrives late | None needed: `PhoneFoodTests` shows a diary with titles drawn |

### What the audit adds up to

| | Seconds | Share of 8,041 |
|---|---|---|
| Phone, verdicts outside PhoneWeekTests | 1,279 | 16% |
| PhoneWeekTests, once unfrozen | 600 | 7% |
| Wall | 489 | 6% |
| All verdicts | 2,368 | 29% |
| Done by run 44926520595 | 2,306 measured (8,041 to 5,735, with fourteen fewer tests in the suite) | 29% |

The verdicts were projected to bring the suite to about 5,700 seconds, short of the 5,400 target; measured, it stands at 5,735, 335 seconds from the target, with a few verdicts still open.
Moving checks down and deleting duplicates is worth about 640 seconds (8%) on its own; most of the saving is merging launches and cutting the looks tests' walking.
The rest of the way to the target, and beyond it, is `reveal` (557 seconds in calls that drag fourteen times without getting there, "Where a slow test's time goes"), which no verdict above counts, and checking whole screens' looks without launching the app ("The middle options").
Removing the 4 second sleep from 17 wall launches is worth up to 68 seconds more, less what waiting for the first element costs.
