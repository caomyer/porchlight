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
All six are proven in this repository; use them freely.

| Option | Proven by | Use it for |
|---|---|---|
| A pure function or small type the view asks | `PocketSyncNotice.pick`, `SyncStatus.summary`, `PocketToday`, `MealSources` | Words, order, counts and rules that a view shows |
| A store, model or flow tested directly | `JoinFlowTests`, `PocketWritesTests`, `TwoHouseholdsTests`, `TimeEntryTests` | What a screen holds after each step, without the screen |
| The real database in memory | `AppDatabase.inMemory`, `HomeDatabaseTests`, `SyncMigrationTests` | Writes, migrations, what a save stores |
| The fake iCloud | `SyncHarness`, `SyncControllerTests` | What sync sends, receives and says |
| A SwiftUI view drawn with `ImageRenderer` in the unit bundle | `WidgetRenderTests` | Review shots of self-contained views in light, dark and the largest text, in milliseconds |
| A component measured in a `UIHostingController` in the unit bundle | `TimeFieldLayoutTests` | A component's layout facts at every Dynamic Type size: it grows, it fits the width, it stacks instead of overlapping |

The last one works by size, not by position.
`UIHostingController.sizeThatFits(in:)` gives the size a view takes in a given width with a text size and size class set in the environment, so "the pill is under its label" is checked as "the row is as tall as the label, the gap and the pill together".
It runs all twelve text sizes in a fifth of a second, where the UI test covers one size in a launch.
It suits a component whose layout rule is its own (`LogTimeField`, a pill, a row, a card).

Not proven yet, so not to be relied on until a working example lands:

- **Where each element sits in a whole screen, without launching the app.**
  That needs the screen in a window and its accessibility tree, which SwiftUI builds only for an automation client, and a screen needs its stores in the environment.
  The looks tests are 32% of the UI suite's time, so this is the next experiment.
- **Review shots of whole screens without launching the app.**
  `ImageRenderer` does not draw scroll views, navigation or sheets, so a screen needs a hosting controller in a window, drawn with `drawHierarchy`; no example yet.

When you add a new kind of test, add a working example with it and a row to the table above.

## Looks

The night look and the largest text size are checked by eye from screenshots, plus a few layout facts (a button whole on screen, a pill clear of its label).

- One looks test per class at most, visiting the class's screens in as few launches as it can: navigate between screens inside a launch instead of launching once per screen.
- A look is a launch, so three looks of one screen are three launches; do not also launch per screen.
- Never repeat a journey's steps in a looks test to get to a screen; start there with a debug launch argument (`-debugFoodView`, `-debugCompanionSheet`, `-debugYouPage`).
- A layout fact that holds for a component everywhere (the time pill, the photo row) is asserted once, in one looks test, not in each class that shows the component.

## Hard rules

The first six were each learned from a failed or misleading run in the week of November 16, 2026.
The last three come from what the UI tests' own comments record.

1. **A test's outcome never depends on the real clock.**
   Pin it and sweep it.
   In a unit test, pass `now` and a `Calendar` with an explicit time zone, and walk the day in half hours in at least two zones when the rule has anything to do with the time of day or the day's edge.
   In a UI test, pin the time with `-debugCompanionNow yyyy-MM-ddTHH:mm`, and never branch on `Date()`.
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
   Why: a launch helper that sleeps 4 seconds adds 4 seconds to every test in its class (`FoodMealsTests` and `MealPhotosTests` do, 17 tests in all).
9. **A test that needs the network or real delivery timing runs by hand, not in the suite.**
   Guard it with `XCTSkipUnless` on an environment variable, as `PhoneRemindersTests.testDeliveryByHand` does.
   Why: a test that skips itself when the network is down reports nothing either way.

## Budgets

Measured on GitHub's hosted Macs (3 cores, 7 GB, iOS 27.2), run 44828667552 of November 20, 2026, the commit this work started from.

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
- **A push: 15 minutes.**
  A push to a working branch should answer "did I break something obvious" with the unit tests and the smoke set (13 UI tests, 580 seconds today), on three Macs after the build.
  The full suite then runs on `integration/next` and `main`, by hand on any branch (Actions, Tests, Run workflow), and before every release.
  This is a proposal: `.github/workflows/tests.yml` still runs everything on every push until James decides.
- **Per UI test: 60 seconds on a hosted Mac, and never over 120.**
  The median is 35, so 60 leaves room for a real journey; the 38 tests over it are where more than half the time goes.

When a UI test goes over 60 seconds, in this order:

1. Move down every assertion the four questions send to a unit test, and delete the steps that only served them.
2. Start nearer the screen with a debug launch argument instead of walking there.
3. Merge it with a test that makes the same launch and visits the same screen, if the journey is the same.
4. If the time is in looking at the screen (a `reveal` loop on a long page, `descendants(matching: .any)` on a big tree, the largest text size), query by identifier inside a container, and scroll less.
5. If it is still over, split it into two journeys; a test over 120 seconds is a failure to fix, not a number to record.

When class times change by more than a fifth, update `scripts/lib/ui-test-seconds` from a run's log, so the shards stay even.

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
| testWhereTakesSeveralKinds | 115 | Seven toggle steps, then save, page says both, editor shows both | Down for the toggle rules (`MealSourcesTests`: "A tap adds a kind…", "On a new meal the first tap replaces…"); keep pick two, save, see both, edit | 35 | |
| testWhereLooks | 84 | Where pills in dark and at the largest size | Merge into testLargestText and testNightLook, which reach the same details screen | 64 | |
| testCoverAndReframeWhenSnapping | 119 | Two shots, second made cover, reframed, saved framed | Keep | | |
| testCoverAndReframeWhenEditing | 116 | Same in the editor, saved and shown again | Keep | | |
| testReframingAnotherPhotoWhenEditing | 42 | Reframe from the action sheet frames that photo only | Merge into testCoverAndReframeWhenEditing (same launch and editor); the order and framing rules are `MealPhotoOrderTests` and `PhotoFramingTests` | 35 | |
| testPhotoRowAndReframeLooks | 185 | Row and reframe in dark and largest, in four launches | Merge to two launches: the new meal's row is the same component as the editor's | 80 | |
| testCameraTurnedOff | 48 | Camera denied: Settings, Photos, no photo | Keep (failure path) | | |
| testEmptyHousehold | 16 | "Nothing in the diary this week" | Delete: `PhoneSetupTests.testStartingAHouseholdOnThisPhone` asserts the same text on the same tab | 16 | |
| testNightLook | 31 | Shots | Keep (looks) | | |
| testPaperUnderTheStatusBar | 76 | Four screens scrolled, nothing under the clock, four launches | Merge to one launch by navigating diary, meal, camera, details | 45 | |
| testPaperUnderTheStatusBarAtNight | 85 | Same in dark | Merge with the largest size into one dark, largest launch | 85 | |
| testPaperUnderTheStatusBarAtTheLargestSize | 81 | Same at the largest size | Merge as above, one launch | 45 | |
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
| testCalendarsFromYou | 45 | Calendars row in You opens the page | Merge into `PhoneTests.testYouSheet` (same launch) | 30 | |
| testFixingAWalkFromToday | 70 | Fix, saved, remove asks, slot open again | Keep | | |
| testFixingAWalkFromTheWeek | 76 | Diary row opens, Keep it backs out, remove | Keep | | |
| testFixingAWalkOnASharedScreen | 30 | Names, with no "You" | Keep | | |
| testFixingAWalkLooks | 158 | Fix sheet in dark, largest, largest dark | Keep (looks), now also holding the time pill's checks; still three launches, so still over 120 seconds until looks get cheaper | | done |
| testTheTimePillGrowsWithText | 100 | Pill grows, clear of "Started", on screen; three launches at the largest size | Merge into testFixingAWalkLooks, which already opens the same sheet at the same size in both looks; the rule at every size is `TimeFieldLayoutTests` | 85 | done |
| testNightLook | 39 | Shots | Keep (looks) | | |
| testPaperUnderTheStatusBar | 95 | Four tabs scrolled, at two sizes | Keep, and take `PhoneTests.testYouOnEveryTab` | | |
| testLargestText | 81 | Field, cash-in whole on screen | Keep (looks) | | |

#### PhoneWeekTests (953 s)

Frozen while `dishes/editor` is in flight; verdicts only.

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testTappingThePawTrail | 74 | A logged, a missed and an open dot each open the right sheet | Keep; the dots' labels are `CompanionWeekTests` | | |
| testAMealInTheDiaryAndTheTrail | 72 | A dinner logged from the trail shows in trail and diary | Keep | | |
| testWater | 30 | Water has its week | Down: "Log a refill" and "Water diary" are `CompanionWeekTests`; keep as a tab tap inside testAMealInTheDiaryAndTheTrail | 20 | |
| testWeekLooks | 746 | Three looks times three routines, each scrolled top to bottom and back | Keep as looks, cut to one full scroll per look and the three tabs checked without scrolling each page; over the 120 second limit six times | 550 | |
| testAFirstWeek | 30 | First week's words | Down: all three sentences are `CompanionWeekTests`; keep one shot inside testWeekLooks | 30 | |

#### PhoneHouseholdTests (587 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testSwitchingHouseholds | 26 | Header, list, one tap switches every tab | Keep | | |
| testSwitcherNightLook | 23 | Shots | Merge into testNightLook | 15 | |
| testHeaderAndSlotsLargestText | 24 | Header whole; slot reads without a dot | Merge into testLargestText | 15 | |
| testOneHouseholdHasNoSwitcher | 27 | No switcher; start another | Keep | | |
| testTheWelcomeExplainsBothWaysIn | 14 | Two doors, and how to join | Delete: `PhoneSetupTests.testStartingAHouseholdOnThisPhone` opens the same screen and taps the same door; move "Or scan your family's code" there | 14 | |
| testJoiningFromAnInvite | 36 | Preview, who, bringing in, Today | Keep (smoke) | | |
| testImNewHere | 35 | A new name joins as that person | Keep | | |
| testAnAccountTheHouseholdKnowsSkipsWhoYouAre | 21 | The who step is skipped | Down: `JoinFlowTests` "An iCloud user who already has a phone in the household keeps the same person" | 21 | |
| testAJoinThatFailsCanBeTriedAgain | 26 | Banner, nothing half joined, try again | Keep (failure path) | | |
| testARemovedHouseholdSaysSoOnce | 16 | Says so, then the welcome | Keep | | |
| testSyncBannersOnToday | 91 | Six launches, one per sync state, each banner's title | Down for the titles (`ArrivalsTests.banners`, `offlineSince`); keep two launches: a member sees whose iCloud is full, and "Choose" opens the choice | 60 | done |
| testYouListsPeopleAndInvites | 33 | People, invite, share sheet | Keep | | |
| testShowingTheCodeOnThePhone | 21 | The code is drawn | Keep | | |
| testWithSyncOffTheHouseholdIsOnThisPhoneOnly | 38 | Says so, the switch turns it on, invites can go | Keep; the words are `HouseholdHomeTests` | | |
| testAMemberSeesWhoseICloudItIs | 18 | Owner's iCloud; no invite for a member | Merge into `PhoneSetupTests.testAMemberLeaves` (identical launch) | 18 | |
| testRenamingThisPhone | 35 | Type a name, saved | Keep | | |
| testNightLook | 52 | Shots | Keep (looks) | | |
| testLargestText | 50 | Join and banner fit | Keep (looks) | | |

#### PhoneSetupTests (511 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testStartingAHouseholdOnThisPhone | 76 | A2 from a fresh install to Today and every empty tab | Keep (smoke) | | |
| testAnEmptyTodayOffersSetup | 19 | Empty Today leads to Household | Keep | | |
| testSettingUpTheHouseholdFromThePhone | 153 | Add, rename, archive a person; a chore; a list | Keep, split in two (people; chores and lists): over the limit | 30 | |
| testACompanionInTheWallsEditor | 147 | Companion and routine editors open, rename saves | Keep; find why two sheets and one field take 147 seconds | 60 | |
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
| testNightLook | 147 | One shot | Merge with testLargestText into one looks test; find why one dark launch takes 147 seconds | 90 | |
| testLargestText | 69 | The choice is whole on screen | Keep (looks) | | |

#### PhoneCatchUpTests (378 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testCatchingUpFromTodaysBanner | 105 | Banner, sheet for the slot, saved as chosen | Keep | | |
| testCatchingUpFromTheWeek | 88 | Missed row, sheet, saved | Keep | | |
| testCatchingUpLooks | 186 | Sheet in dark and largest, each after removing a walk by hand | Keep as looks, opened with `-debugCompanionSheet catchUp` instead of removing a walk first | 100 | |

#### PhoneDishesTests (332 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testDishesAndAPlace | 71 | List, dish, favourite, place | Keep | | |
| testSearch | 28 | Typing finds dishes and places | Merge into testDishesAndAPlace; matching is `DishBookTests` | 20 | |
| testEveryoneRatesAMeal | 38 | Own face saved and shown | Keep | | |
| testRenameIntoAMergeAndRemoveWithUndo | 82 | Rename offers a merge; remove with undo | Keep | | |
| testEmpty | 22 | Empty state | Keep | | |
| testNightAndLargestText | 91 | Five launches for five shots | Merge to two launches, navigating list, dish, place | 45 | |

#### PhoneTests (295 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testPickingWhoYouAre | 19 | Asks once, greets | Keep | | |
| testTodayWithSomethingDue | 28 | Order of Today's cards | Keep; the order is `PocketTodayTests` | | |
| testOneTapLogAndUndo | 21 | One tap, toast, undo | Keep (smoke) | | |
| testCareSheet | 22 | More opens the sheet; save | Keep | | |
| testCatchingUp | 21 | Banner, sheet, saved | Delete: `PhoneCatchUpTests.testCatchingUpFromTodaysBanner` is the same journey, in full | 21 | |
| testCheckingChores | 29 | Check, undo, shared chore credited | Keep (smoke) | | |
| testAllClear | 30 | A finished day folds to one line | Down: `PocketTodayTests` "A card that just finished shows it was logged, then folds to all set" | 30 | |
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
| testWhereTakesSeveralKinds | 37 | Toggle rules, then saved "at work" | Down: `MealSourcesTests`; the journey is testEditingWhereIntoTwoKinds | 37 | |
| testEditingWhereIntoTwoKinds | 29 | Only kind can't come off; two kinds saved and shown | Keep | | |
| testLiveRestaurantSearch | 34 | Maps suggests places; skips itself offline | By hand | 34 | |
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
| testSetupAsksHowThisIPadIsUsed | 18 | Role step, shared screen picked | Delete: `FirstRunTests` asserts the same step and default; the default is `DeviceSettingsTests` | 18 | |
| testSetupSaysWhereTheHouseholdLives | 31 | iCloud step with and without an account, two launches | Keep the launch without an account; `FirstRunTests` covers the other | 15 | |
| testRowsFromPhonesAreTaggedAndArrivalsNamed | 28 | Arrival toast comes and goes | Keep; the sentences are `ArrivalsTests` | | |
| testSampleMealsHaveTheirPhotos | 17 | Breakfast is on the week | Delete: five `MealPhotosTests` open that breakfast | 17 | |
| testARestoredCopyWaitsForAChoice | 40 | Choice, never "send", keeping brings back the switch | Keep | | |

#### SyncSettingsTests (246 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testChecksTickOnAnUntouchedWall | 49 | Three polls on a wall nobody touches | Keep: real timers in the real app | | |
| testADifferentAccountAsksWhatToDo | 38 | Choice; dot comes and goes | Keep | | |
| testAFullICloudPausesSync | 44 | Paused, dot, nothing on Today | Keep (smoke) | | |
| testEachMissingICloudSaysWhy | 95 | Three launches, one per account state, each line whole | Down for the words and the dot's rule (`SyncWordingTests`); keep one launch as testAMissingICloudSaysWhy | 63 | done |
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
| testOpeningAChoreFromToday | 88 | A row opens the chore's sheet and closes | Merge into testCheckingOffAChoreOnToday (same launch); 88 seconds for one tap needs a look | 75 | |
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
| testLoggingCareFromTheBoard | 26 | Care opens its own sheet | Keep, but pin the time: it branches on what is done at the real time of day | | |
| testCashingInOnGlow | 30 | Cash in; new round | Keep | | |
| testNewChoreWithAStartDay | 26 | Picker reads back; chore on the board | Keep; the summaries are `RecurrenceTests` | | |

#### CatchUpTests (124 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testCatchingUpFromYoYosWeek | 72 | Diary and trail catch up | Keep | | |
| testLoggingYesterdaysDinnerFromTheCalendar | 30 | Missed mark opens the sheet for that slot | Keep | | |
| testMissedCareInTheWeek | 22 | Missed slots are marked | Down: `CareCatchUpTests` and `CalendarTests` | 22 | |

#### LoggedEntryTests (114 s)

| Test | s | Asserts | Verdict | Saves | Status |
|---|---|---|---|---|---|
| testFixingAWalkFromToday | 40 | Log, celebrate, fix who and how long | Keep | | |
| testLoggingAWalkSaysWhenItStarted | 26 | Suggestions; branches on the real time of day | Down: `LogTimeTests`; testFixingAWalkFromToday already opens the pad and its suggestions. It is in the smoke set, so swap in testFixingAWalkFromToday | 26 | |
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

`PhoneDishEditorTests` and `WallDishEditorTests` are on `dishes/editor` and are audited when that branch lands.

### What the audit adds up to

| | Seconds | Share of 8,041 |
|---|---|---|
| Phone, verdicts outside PhoneWeekTests | 1,279 | 16% |
| PhoneWeekTests, once unfrozen | 600 | 7% |
| Wall | 489 | 6% |
| All verdicts | 2,368 | 29% |
| Done so far (three tests) | 208 projected | 3% |

The verdicts bring the suite to about 5,700 seconds, short of the 5,400 target.
Moving checks down and deleting duplicates is worth about 640 seconds (8%) on its own; most of the saving is merging launches and cutting the looks tests' walking.
The rest of the way to the target, and beyond it, is checking whole screens' looks without launching the app ("The middle options"), and the two tests that take 147 seconds for reasons not yet understood (`PhoneRemindersTests.testNightLook`, `PhoneSetupTests.testACompanionInTheWallsEditor`).
