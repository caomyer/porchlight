# Testing: which check goes where

This is the rule for deciding whether a check is a unit test or a UI test, and for keeping the whole suite fast.
It is a decision rule, to be applied without asking.
The audit at the end applies it to every UI test in the repository, with measured times.

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
All seven are proven in this repository.

| Option | Proven by | Use it for |
|---|---|---|
| A pure function or small type the view asks | `PocketSyncNotice.pick`, `SyncStatus.summary`, `PocketToday`, `MealSources` | Words, order, counts and rules that a view shows |
| A store, model or flow tested directly | `JoinFlowTests`, `PocketWritesTests`, `TwoHouseholdsTests`, `TimeEntryTests` | What a screen holds after each step, without the screen |
| The real database in memory | `AppDatabase.inMemory`, `HomeDatabaseTests`, `SyncMigrationTests` | Writes, migrations, what a save stores |
| The fake iCloud | `SyncHarness`, `SyncControllerTests` | What sync sends, receives and says |
| A SwiftUI view drawn with `ImageRenderer` in the unit bundle | `WidgetRenderTests` | Review shots of self-contained views in light, dark and the largest text, in milliseconds |
| A component measured in a `UIHostingController` in the unit bundle | `TimeFieldLayoutTests` | A component's layout facts at every Dynamic Type size: it grows, it fits the width, it stacks instead of overlapping |
| A whole screen hosted in a window in the unit bundle (`HostedScreen`) | `PocketWeekScreenTests` | Where every element of a screen sits, and a picture of the whole page, in light, dark and the largest text |

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

It is proven for three (a companion's week, the care sheet and the dishes pages), and the care sheet's and the dishes' looks have moved onto it ("Review shots"); other screens move one at a time, each with a hosted test seen failing first and one UI test kept for what only the real screen shows.

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
The last three come from what the UI tests' own comments record.

1. **A test's outcome never depends on the real clock.**
   Pin it and sweep it.
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
9. **A test that needs the network or real delivery timing runs by hand, not in the suite.**
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
   It is taken out of the suite the day it is seen (an `XCTSkip` with the reason), and written into "Tests that skip themselves" with its owner and a date one week on.
   By that date it is fixed and back, or moved down to a unit test, or deleted with the reason recorded; it is never left skipped.
   A failure that XCTest's own launch retry covers ("could not start the app") is not a flaky test, and one that cannot be reproduced is written into "Known and not yet explained".
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
| testWhereTakesSeveralKinds | 115 | Seven toggle steps, then save, page says both, editor shows both | Down for the toggle rules (`MealSourcesTests`: "A tap adds a kind…", "On a new meal the first tap replaces…"); the journey stays: pick two, save, see both, edit | 35 | done |
| testWhereLooks | 84 | Where pills in dark and at the largest size | One launch, the night look at the largest size (was two) | 40 | done |
| testCoverAndReframeWhenSnapping | 119 | Two shots, second made cover, reframed, saved framed | Keep | | |
| testCoverAndReframeWhenEditing | 116 | Same in the editor, saved and shown again | Keep | | |
| testReframingAnotherPhotoWhenEditing | 42 | Reframe from the action sheet frames that photo only | Merge into testCoverAndReframeWhenEditing (same launch and editor); the order and framing rules are `MealPhotoOrderTests` and `PhotoFramingTests` | 35 | |
| testPhotoRowAndReframeLooks | 185 | Row and reframe in dark and largest, in four launches | One launch of the editor in the night look at the largest size, Done still in reach; the new meal's row is the same component and is not launched for again. It took 249 seconds in run 44883476613 | 180 | done |
| testCameraTurnedOff | 48 | Camera denied: Settings, Photos, no photo | Keep (failure path) | | |
| testEmptyHousehold | 16 | "Nothing in the diary this week" | Delete: `PhoneSetupTests.testStartingAHouseholdOnThisPhone` asserts the same text on the same tab | 16 | done |
| testNightLook | 31 | Shots | Keep (looks) | | |
| testPaperUnderTheStatusBar | 76 | Four screens scrolled, nothing under the clock, four launches | Merge to one launch by navigating diary, meal, camera, details | 45 | |
| testPaperUnderTheStatusBarAtNight | 85 | Same in dark | Merged with the largest size into `testPaperUnderTheStatusBarAtNightAtTheLargestSize`: the two looks share their four launches | 80 | done |
| testPaperUnderTheStatusBarAtTheLargestSize | 81 | Same at the largest size | Merged as above. A hosted screen has no status bar, so this stays a UI test | | done |
| testLargestText | 75 | Snap and Save whole on screen | Keep (looks) | | |

#### PhoneTabsTests (1,022 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testSeveralCompanionsGoToAGrid | 19 | Three cards, each with its one tap | Keep | | |
| testCompanionWeek | 58 | Week opens from a card; a missed slot is caught up | Delete once `PhoneWeekTests` is unfrozen: it opens the week from the card in every test, and `PhoneCatchUpTests.testCatchingUpFromTheWeek` is the same catch-up; "Walker of the week" is `CompanionWeekTests` | 58 | |
| testPitchInAndAddingAChore | 50 | Yours, everyone, add a chore, it is mine today | Keep (smoke) | | |
| testAWidgetLinkOpensLists | 48 | `porchlight://lists` and `://today` | Merge into testListsAndDinners (open the link instead of tapping the tab) | 30 | |
| testListsAndDinners | 52 | Add, check, dinners' needs, counts | Keep; the counts and aisles are also `PocketTabsTests` | | |
| testGlowAndCashingIn | 28 | Cash in asks once, celebrates, starts again | Keep | | |
| testNextSevenDays | 40 | Row opens the page, grouped by day | Merge into `PhoneTests.testTodayWithSomethingDue` (same launch, Today's last row); grouping is `PocketTabsTests` | 25 | |
| testChoosingCalendars | 33 | Why before asking; sharing choices | Keep (permission) | | |
| testCalendarsFromYou | 45 | Calendars row in You opens the page | Merge into `PhoneTests.testYouSheet` (same launch); it settled the row before revealing it, now the other way round | 30 | |
| testFixingAWalkFromToday | 70 | Fix, saved, remove asks, slot open again | Keep | | |
| testFixingAWalkFromTheWeek | 76 | Diary row opens, Keep it backs out, remove | Keep | | |
| testFixingAWalkOnASharedScreen | 30 | Names, with no "You" | Keep | | |
| testFixingAWalkLooks | 158 | Fix sheet in dark, largest, largest dark | One launch at the largest size for what only the real sheet shows (the pill among everything else, Save within reach); the looks are hosted in `PocketCareSheetScreenTests` | 100 | done, 38 and 63 s measured (runs 44871628859, 44871628840) |
| testTheTimePillGrowsWithText | 100 | Pill grows, clear of "Started", on screen; three launches at the largest size | Merge into testFixingAWalkLooks, which already opens the same sheet at the same size in both looks; the rule at every size is `TimeFieldLayoutTests` | 85 | done |
| testNightLook | 39 | Shots | Keep (looks) | | |
| testPaperUnderTheStatusBar | 95 | Four tabs scrolled, at two sizes | Keep, and take `PhoneTests.testYouOnEveryTab` | | |
| testLargestText | 81 | Field, cash-in whole on screen | Keep (looks) | | |

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
| testSwitcherNightLook | 23 | Shots | Merge into testNightLook | 15 | |
| testHeaderAndSlotsLargestText | 24 | Header whole; slot reads without a dot | Merge into testLargestText | 15 | |
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
| testNightLook | 52 | Shots | Keep (looks) | | |
| testLargestText | 50 | Join and banner fit | Keep (looks) | | |

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
| testYouOnEveryTab | 32 | The avatar is on each tab | Merge into `PhoneTabsTests.testPaperUnderTheStatusBar`, which visits each tab | 30 | |
| testNightLook | 24 | Shots | Keep (looks) | | |
| testLargestText | 41 | Log button whole and full width | Keep (looks) | | |

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
| testTheRemoveBadgeTakesTapsOverThePhoto | 26 | Badge wins the tap over the photo | Merge into testPagingAndEditingPhotosOfASavedMeal, which removes the same photo | 26 | |
| testPagingAndEditingPhotosOfASavedMeal | 34 | Paging; cancel keeps; save removes | Keep | | |
| testTheViewfinderIsThePolaroidSquare | 20 | Viewfinder is square; shots under it | Merge into testShotsWaitInTheFormUntilSave (same screen) | 20 | |
| testWholePhotoAndReframing | 35 | Whole photo; drag moves the square | Keep (gesture) | | |
| testReframingAnotherPhoto | 38 | Reframe frames that photo only | Merge with testMakingAnotherPhotoTheCover into one editor journey | 31 | |
| testMakingAnotherPhotoTheCover | 31 | No duplicate; one cover | As above; the order rule is `MealPhotoOrderTests` | | |

#### DayAtAGlanceTests (197 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testCheckingOffAChoreOnToday | 54 | Who did it, done chip, timeline line | Keep (smoke) | | |
| testOpeningAChoreFromToday | 88 | A row opens the chore's sheet and closes | Merge into testCheckingOffAChoreOnToday (same launch); 88 seconds for one tap needs a look | 75 | done |
| testMomentsInTheWeek | 32 | Walks and meals open from the week grid | Keep | | |
| testChoresInTheCalendar | 23 | Lane opens a chore and updates | Keep | | |

#### PhotoFrameTests (160 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testChoosingThePorchView | 108 | Choice survives a relaunch, both ways, four launches | Keep the first half (choose, relaunch, porch view); the way back needs a new unit test of which view Ambient picks for the setting, beside `Home/PhotoFrameTests` | 50 | |
| testRemovingSeveralPhotos | 52 | Select three, remove, counts | Keep | | |

#### TimeFieldTests (135 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testTypingAMealTime | 43 | Pad not keyboard; then eight digit rules | Down for the digit rules (`TimeEntryTests`); keep open, type, Done | 15 | |
| testNightHoursCrossMidnight | 63 | Suggestion sets; "next day"; then puts both back | Keep the first two; nothing needs putting back in a sample sandbox | 20 | |
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
| testLoggingAWalkSaysWhenItStarted | 26 | A suggestion sets the time, closes the card and is marked | Keep, pinned to 5:20 pm; which choices are offered at each minute of the day is `LogTimeTests.suggestionsThroughTheDay`. Later, merge into testFixingAWalkFromToday, which opens the same card | 26 | pinned |
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
| ScrollingTests.testTouchesKeepTheWallAwake | 55 | Touches hold off Ambient | Keep (real idle timer) | | |
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
| PhoneDishEditorTests.testTheFormAtNightAndAtTheLargestText | 84 | The form in two looks | Hosted next: the form needs the snap's stores and a photo handed in | 70 | |
| WallDishEditorTests.testRestaurantMealWithTwoDishesFromLastTime | 42 | The same journey on the wall | Keep | | |
| WallDishEditorTests.testHomeMealTypedWithASuggestion | 31 | The same on the wall | Keep (keyboard) | | |
| WallDishEditorTests.testAPhotoAloneIsAWholeMeal | 23 | The same on the wall | Merge into testHomeMealTypedWithASuggestion's launch, or leave: 23 seconds | | |
| WallDishEditorTests.testEditAddsAndTakesOffADish | 28 | The same on the wall | Keep | | |

### What the audit adds up to

| | Seconds | Share of 8,041 |
|---|---|---|
| Phone, verdicts outside PhoneWeekTests | 1,279 | 16% |
| PhoneWeekTests, once unfrozen | 600 | 7% |
| Wall | 489 | 6% |
| All verdicts | 2,368 | 29% |
| Done by run 44883476613 | 1,236 measured (8,041 to 6,805, with four more tests in the suite) | 15% |

The verdicts bring the suite to about 5,700 seconds, short of the 5,400 target.
Moving checks down and deleting duplicates is worth about 640 seconds (8%) on its own; most of the saving is merging launches and cutting the looks tests' walking.
The rest of the way to the target, and beyond it, is `reveal` (557 seconds in calls that drag fourteen times without getting there, "Where a slow test's time goes"), which no verdict above counts, and checking whole screens' looks without launching the app ("The middle options").
Removing the 4 second sleep from 17 wall launches is worth up to 68 seconds more, less what waiting for the first element costs.
