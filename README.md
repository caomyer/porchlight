# Porchlight

A family wall calendar for an iPad you already own.
The household, its people, companions and journals are all set up in the app; nothing about one family is hard-coded.

The product plan and UX mocks live in [.lavish/porchlight.html](.lavish/porchlight.html).

## What it does

- **Today**: big clock, local weather, one timeline mixing calendar events, care logs (walks, feeding), meals and chores done, plus companion cards, a Pitch in card with today's chores to check off, today's plates and countdowns.
- **Calendar**: Week, Month and Day views of every calendar on the iPad (via EventKit), colored by person.
  Walks, feeds and meals sit in the week and day grids at their times, chores in a Pitch in lane, and each opens the same sheet as on Today.
- **Companions**: pets, plants or anything cared for; routines with time windows, logging who did it and when with a celebration, tap any logged walk to fix or remove it, care missed earlier in the week shown as faint marks in the calendar, Paw trail and the diary that log it for that day when tapped, a weekly page with paw trail, podium, mood meter and cheeky captions.
- **Food diary**: snap a meal with the camera or pick from Photos (up to 6 photos per dish, the first as its cover; the shutter only takes a photo, and the meal saves on Save), with a square viewfinder that is exactly the polaroid; the whole shot is kept, any photo can be reframed by dragging and zooming, and tapping a meal's polaroid shows the whole photo; add photos to a saved meal any time, home-cooked, delivery, dining out (with the restaurant picked from live Apple Maps search) or company food, several dishes per meal, a polaroid week where any meal can be fixed or removed, and a handwritten paper month written with Apple Pencil (one fixed-ratio page per day, zoomed for writing). Every time in the app (meals, walks and other care, routine windows, night hours) is a pill; tapping it opens a small card already showing that time, with a few suggestions, the hour and minutes in their own boxes, and its own number pad, so the iPad's keyboard never covers the form. Each digit counts the moment it's typed (7 1 5 is 7:15), typing an hour keeps AM or PM, and 12 or 24-hour follows the iPad.
- **Pitch in**: what everyone does for the household on one board, a column per person plus "Anyone" for shared chores and companion care. Tap a box to check it off, a row to fix who did it, undo, edit or archive it. Chores and routines share one repeat rule (every day, some weekdays, every few days, monthly, just once) with a start day.
- **Glow**: everyone's stars in one place. Every chore and every walk or feed earns stars, the week shows as sparks around the porch light, and rewards are saved up for and cashed in.
- **Lists and meal plan**, and an **Ambient** photo frame with a night clock: your photos shuffled, or the porch view, a still sky that follows the day and uses the least power.

## Develop

`project.yml` is the source of truth; the Xcode project is generated.

```bash
brew install xcodegen
cp Config/Local.example.xcconfig Config/Local.xcconfig   # then set DEVELOPMENT_TEAM
xcodegen generate
open Porchlight.xcodeproj
```

Run the tests on an iPad simulator (build output must stay outside iCloud-synced folders):

```bash
xcodebuild test -project Porchlight.xcodeproj -scheme Porchlight \
  -destination 'platform=iOS Simulator,name=iPad (10th generation)' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Porchlight-main CODE_SIGNING_ALLOWED=NO -skipMacroValidation
```

iCloud sync uses Point-Free's SQLiteData, whose Swift macros Xcode asks to trust once when the project is opened.
Command-line builds pass `-skipMacroValidation` instead; every script here does.
Builds with `CODE_SIGNING_ALLOWED=NO` (simulators, tests) have no iCloud entitlement, so sync stays off in them and Settings says why.

Screenshot a screen with sample data:

```bash
scripts/sim-shot.sh <simulator-udid> /tmp/today.png -sampleHousehold -startScreen today
```

Debug-only launch arguments:
- `-resetData` (start at onboarding), `-sampleHousehold` (seed a sample household with a week of everything; add `-samplePhotos N` for N photos in the photo frame)
- `-startScreen today|calendar|companion-1|food|chores|glow|lists|photos|settings` on the wall, `-startScreen today|food|lists|glow|you|week|pitchIn|nextWeek|calendars` on a phone (`you` opens the You sheet; `week` is the first companion's week)
- `-sampleCompanions 2|3` with `-sampleHousehold`: also Miso the cat, then a fiddle fig watered every three days (due today), for the phone's grid of companions
- `-calendarAccess notDetermined|denied` with `-sampleHousehold`: start the sample calendars without access, to see how the phone asks for it
- `-notificationAccess notDetermined|denied|allowed` on a phone: pretend that notification permission state, so the Notifications page can be seen in each state without the system prompt (asking then allows)
- `-debugCamera sample` on a phone: the simulator has no camera, so "Snap a meal" shows a generated dish in the viewfinder and the shutter takes it (each shot a little different), through the same photo path as a real shot; `-cameraAccess notDetermined|denied|allowed` pretends the camera permission state the same way as `-notificationAccess`
- `-debugSetup you|people|companion|done` with `-resetData` on a phone: open that step of starting a household on the phone, filled in as The Lake House (from `companion` on, the household exists)
- `-debugYouPage household|person|companions|companion|chores|rewards|lists|storage|leave` with `-startScreen you` on a phone: open that page of You (`person` is the last person, `companion` the first companion, `leave` the leave sheet; with `-debugSharing member` it is a member's, else the owner's)
- `-debugFoodView snap|details|detail` on a phone (with `-startScreen food`): open the camera, the details of a new meal, or today's first meal; `-sampleFood none` with `-sampleHousehold` leaves the diary empty, and `-samplePhotoMeals` gives every meal of the sample week two photos (the first launch draws and caches them, which takes a while)
- `-debugReminderIn N` on a phone with notifications really allowed: the day's first care reminder arrives N seconds after launch, to try delivery and its actions by hand; `TEST_RUNNER_PORCHLIGHT_DELIVERY=1` with `-only-testing:PorchlightUITests/PhoneRemindersTests/testDeliveryByHand` runs that check
- `-sampleSecondHousehold` with `-sampleHousehold`: also Grandma Rosa's (Rosa and James, tomatoes watered every three days, one chore of James's), with The Lake House showing, for the household switcher (journey A5)
- `-me NAME` on a phone: this phone belongs to the person called NAME in every household that has one, so it skips "Which one is you?" (for example `-sampleHousehold -me James`)
- `-debugCompanionNow yyyy-MM-ddTHH:mm` pins "now" for care, for example `2026-11-16T17:20` so Yo-Yo's evening walk and dinner are open; the phone's writes use it too
- `-debugSyncStatus off|upToDate|syncing|waiting|noAccount|iCloudFull|needsDecision|restoredCopy` (with `-sampleHousehold` or `-resetData`) puts sync in that state, without iCloud, for screenshots of Settings, the phone's banners and the gear's dot (`needsDecision` is a different iCloud account, `restoredCopy` a database put back from a backup); `lookingForHousehold` with `-resetData` holds the first-launch "Looking for your household in iCloud" screen
- Sharing without iCloud, with a fake (sample data only): `-debugSharing invited|joined|member` (with `-sampleHousehold`): this device is the owner James's with Mia invited and Ava without a phone, the same with Mia joined from her iPhone, or this device is Mia's and James owns the household
- Joining: `-debugJoin preview|failing|known` (with `-resetData`): an invite to The Lake House opened the app; `failing` fails the first try as if offline, `known` means this iCloud user already has a phone in the household
- `-debugRemoved` (with `-resetData` or `-sampleHousehold`): this device's household was removed by its owner; `-debugArrival` (with `-sampleHousehold`, on the wall): lunch came from Mia's phone and a walk arrives from James's phone a few seconds after launch
- `-seedCloudSchema`: teach CloudKit's Development environment every record type and field, in a throwaway database and zone that are removed afterwards; run it through `scripts/cloud-schema.sh seed`, which installs it as its own app, never over Porchlight (docs/design/sync-icloud.md, "Deploying the CloudKit schema")
- Widgets can't be driven by UI tests, so `WidgetRenderTests` draws every widget family in every look (light, dark, largest text, redacted, stale, no household, not set up, shared screen); with `TEST_RUNNER_PORCHLIGHT_WIDGET_SHOTS=<folder>` set for `xcodebuild test`, each render is saved there as a PNG for review
- Feature previews: `-calendarMode month|day` (with `-calendarDate yyyy-MM-dd` to open on a day), `-debugCompanionSheet log|celebrate|onboarding|editor|routine` (on a phone, `log|catchUp` opens the care sheet or the catch-up sheet), `-debugFoodView month|write|capture|saved|detail` (with `-debugCaptureShots N` to start the capture with N generated photos), `-homeSheet newChore|whoDidIt|week|ambient|...`

Review the real iPad's rendering (sample data lives in a separate storage sandbox, so the household's data is never touched).
The tour needs a Debug build, so install one first and put the Release build back afterwards:

```bash
scripts/deploy-ipad.sh --debug
```

```bash
scripts/device-tour.sh /tmp/porchlight-device-tour
```

Measure idle CPU on the iPad, screen by screen, also on a Debug build.
Decorative motion should play briefly and rest, never loop: on the 120 Hz screen a forever animation keeps the app and the render server busy all day.

```bash
scripts/idle-cpu.sh
```

UI tests (screen tour, handwriting round trip, meal editing, choosing the photo frame and removing several photos, fixing who did a chore, care from the board, cashing in a reward, several dishes per meal, several photos per meal, dining out with restaurant search, editing a companion and adding a routine, fixing logged walks and meals from Today, typing times on the number pad (meals, night hours across midnight, routine windows), chores on Today and in the calendar, walks and meals in the week grid, keyboard placement, scrolling, the idle timer, sync's states in Settings with the gear's dot, the first launch looking for a household in iCloud, and a first run that grants real calendar access and assigns a calendar) run with the `PorchlightUI` scheme on a simulator.
The wall iPad runs iPadOS 17, so run them on an iOS 17.5 simulator (`xcodebuild -downloadPlatform iOS -buildVersion 17.5`).

### Running the tests

Before adding or moving a test, read [docs/design/testing.md](docs/design/testing.md): which checks are unit tests and which are UI tests, the hard rules for both, the time budgets, and the audit of every UI test.
In short, a check lives at the lowest level that can express it, and a UI test is one journey that asserts only what the real UI can get wrong.

`scripts/test.sh` builds once, then runs the unit tests and the wall's UI suite on an iPad simulator and the phone's UI suite on an iPhone simulator, side by side when the Mac has room for both, and says how long each step took.

```bash
scripts/test.sh                    # everything
scripts/test.sh --smoke            # unit tests and 13 UI tests across both shells: the gate before installing
scripts/test.sh --unit-only        # unit tests only
scripts/test.sh --wall --ui-only   # the wall's UI suite only; --phone for the phone's
scripts/test.sh --only PhoneTests/testCheckingChores FirstRunTests   # just these, each on the right simulator
```

It skips the screen tour, which only takes screenshots for review; add `--tour` before deploying.
`--serial` runs the iPad and then the iPhone even with room for both, `--runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5` runs on another installed iOS, and `--no-build` reuses the last build.
A UI test class named `Phone…Tests` is the phone's and runs on the iPhone; every other one is the wall's.
A suite that runs no test at all, for a name in `--only` that matches none or only tests that skip themselves, fails ("no tests ran").
`--shard 2/3` runs only the second of three shares of each UI suite's test classes, `--build-only` only builds, and `--progress` prints each test as it ends.
Results and logs are in `$TMPDIR/porchlight-tests-<checkout>`: `unit`, `ui-wall` and `ui-phone`, each an `.xcresult` and a `.log`.

How it stays fast and out of everyone's way:

- **Its own simulators.** Each checkout makes its own iPad and iPhone simulators the first time ("Porchlight <checkout> ipad", "... iphone"), so runs from different worktrees never share or wait on one, and nobody passes a simulator id.
- **Locks that cannot go stale.** A run holds its simulators with kernel file locks in `/private/tmp/porchlight-simulator-locks`, which the system releases the moment the run ends, however it ends; the old lock folder (`/private/tmp/porchlight-sim.lock`) could outlive a killed run and stall every other run for hours, and the script no longer uses it.
- **Test slots for memory.** A booted simulator under test takes 1.5 to 3 GB, and with more of them than the Mac can hold everything swaps: queries time out, the test runner fails to start ("Timed out while loading Accessibility"), and tests fail that pass alone.
  So the Mac has one test slot per 8 GB of memory (two on a 16 GB Mac, or `PORCHLIGHT_TEST_SLOTS`), a run boots simulators only into slots, and it shuts them down however it ends.
  Before taking a slot it shuts down its own checkout's simulators that are booted but held by no run (ones a run of this checkout left behind when it was killed outright), and only those.
  Every other booted simulator that no run holds takes a slot of its own, whoever booted it: one opened by hand, another project's, or another checkout's test simulator that someone is driving by hand.
- **Never another checkout's simulator.** A run waits for a slot other people's simulators hold, says which ones it is waiting for, and never shuts them down: a simulator with no test run holding it is not evidence that nobody is using it (on November 21, 2026 a run shut down another agent's two simulators in the middle of its work, under the rule before this one).
  To drive this checkout's own simulator by hand while its tests may run, hold it: `scripts/sim-hold.sh ipad` (or `iphone`, or both) boots it, holds it and a test slot, and lets go when it ends.
  `scripts/sim-clear.sh` lists the booted test simulators that nothing holds, from every checkout, and `scripts/sim-clear.sh --yes` shuts them down: the one explicit way to clear abandoned ones, for a person, or an agent that has asked whose they are.
  `zsh scripts/ci/check-simulator-rules.sh` checks these rules with stand-ins for the simulators, in a second, and runs with every build on GitHub.
  A run takes two slots when both are free and the memory free right now has room for two simulators (4 GB each), and runs the iPad and the iPhone side by side; otherwise it runs them one after the other, and with no slot free it waits, and says for whom.
  Two simulators with too little memory are slower than one after the other and fail besides: their apps' main threads stall for 30 seconds and more while the system pages them in, and the test runner can fail to start ("Timed out while loading Accessibility"), which `scripts/test.sh` then tries once more.
  It never holds one slot while waiting for a second, so two runs can't wait on each other.
- **One build.** `build-for-testing` once, then `test-without-building` for each suite, so the suites never rebuild.
- **Fewer waits in the tests.** The idle-timer test runs on twelve-second minutes (`-debugIdleSecondsPerMinute`) instead of waiting out real ones, the first-run test resets the calendar permission itself, and toasts stay up for 30 seconds in UI tests (`PORCHLIGHT_TOAST_SECONDS`), since a busy simulator can spend 5 seconds between a tap and the next look at the screen.

Measured on the 16 GB M4 with nothing else running, the same commit and the same simulators, on November 17, 2026:

| | Before (old script) | After |
|---|---|---|
| Unit tests | 1.5 min | 1.6 min |
| Wall UI suite (54 tests) | 17.2 min | 23.7 min, beside the phone's |
| Phone UI suite (61 tests) | 25.8 min | 24.6 min, beside the wall's |
| Whole run | 44.8 min | 26.3 min |
| Smoke set | none | 5.8 min |

Both columns ran the same tests, so both include the shorter idle-timer test, which on its own took about 2 minutes off the wall's suite (160 seconds to 50).
Side by side each suite runs slower than alone, since the two share the CPU, but the whole run takes the longer of the two instead of their sum.
Most of a suite's time is the tests' own steps: each look at the screen takes about a second on these large accessibility trees, and each launch with the sample household 3 to 4 seconds.
The phone suite's food tests are much slower than on November 16 (the meal page test 131 seconds, from 40), with the app slow to quit between tests; that slowness is in the app, not in the setup.

#### On GitHub (CI)

Pushes run on GitHub's hosted Macs (`.github/workflows/tests.yml`), on iOS 27.2 with Xcode 27.2, so runs leave the development Mac alone, in two tiers ([docs/design/testing.md](docs/design/testing.md), "Tiers").
A push that changes only `docs/` or this README runs nothing.
A push to a working branch runs the unit tests and the smoke set (`scripts/test.sh --smoke`'s 13 UI tests) on three Macs; a push to `integration/next` or `main`, and any run by hand, runs the unit tests and both whole UI suites on five.
A newer push to the same branch cancels the run before it; a run by hand is never cancelled by, and never cancels, another run.
Each job is a small Mac (3 cores, 7 GB) that holds one simulator, and the plan runs five at once:

- **Build** builds once (`scripts/test.sh --build-only`) and hands the build to the test jobs as the `products` artifact.
- For a working branch's push, **Unit, Wall smoke and Phone smoke** start once the build is done, each on its own Mac.
- For the full suite, **Unit and Wall UI 1 of 2, Wall UI 2 of 2, Phone UI 1 of 3, 2 of 3, 3 of 3** start once the build is done (`needs: build`), boot their simulator (2 to 8 minutes for a new iOS 27 simulator), and run the unit tests or a share of a UI suite's test classes (`--shard`) on that build (`--no-build`).
  They used to boot while the build ran, which saved those minutes, but with several branches pushing, a test job then held a Mac for as long as the build waited in the queue for one.

The shares are of about equal time, from each class's measured seconds in `scripts/lib/ui-test-seconds`; when a class grows, update its line from a run's log, where each test prints its seconds.
The suites take about 35 minutes of tests for the wall and 75 for the phone on these Macs, about one and a half times the development Mac's, since a 7 GB Mac swaps 2 to 3 GB with a simulator up.

The jobs go through `scripts/test.sh` like a local run; the steps around it live in `scripts/ci`.
A UI test that failed only because XCTest could not start the app, or quit the one before it ("Failed to launch", "Failed to get launch progress", "does not have a process ID", "Failed to terminate"), and left no crash report, which a busy hosted Mac does now and then, runs once more on its own, locally too; the summary names it ("passed on a second launch"), its second run is the `-retry` bundle and log, and any other failure stands (`scripts/lib/launch_retry.py`).
The log prints each test as it ends (`--progress`), and every two minutes a heartbeat line with the free memory, so a hang or a Mac out of memory shows.
To run the full suite on a working branch, which every branch does once before asking to merge, use Actions, Tests, Run workflow, on that branch, with "only" left empty (`gh workflow run Tests --ref <branch>`).
To run only some tests, use Actions, Tests, Run workflow, with "only" set as for `--only` (for example `FirstRunTests PhoneTests/testCheckingChores`): one job builds and runs just those.

**A run in which no test started is run once more.** When the test runner crashes before any test has started ("The test runner crashed while preparing to run tests", or it never loads Accessibility), on a Mac short of memory, `scripts/test.sh` runs that suite again, locally too, and a second time fails saying the runner crashed before any test, twice; a runner that dies after a test has started is a real failure and is not run again (`scripts/lib/runner-start.sh`).

**A boot that stalls fails by name.** Each stage of booting a job's simulator has a limit of its own (booting, then the first uninstall answering), a stage that stalls is named in the log and the simulator is erased and booted once more, and a second stall fails the job saying which stages stalled and that no test ran (`scripts/ci/boot-simulator.sh`); before that, a stalled boot sat until GitHub cancelled the job with "The operation was canceled".

**A build that arrives corrupted is not a red test run.** The build job records its packed build's size and SHA-256, and each test job checks its download against them, downloads again up to twice when they differ, and only then fails, saying "The build's download was corrupted" (`scripts/ci/unpack-build.sh`; `zsh scripts/ci/check-unpack-build.sh` checks that script with a stand-in for the download).

**Reading a failure.** The job's log lists the failed tests and their messages under `[ui-wall]`, `[ui-phone]` or the unit summary.
Each job uploads an artifact, `results-<job name>` (for example `results-Wall UI 2 of 2`), kept for a week, with the job's `.log` files and, when the job failed, each `.xcresult` bundle zipped.
Unzip one and open it in Xcode, or export its screenshots with `xcrun xcresulttool export attachments --path ui-wall.xcresult --output-path shots`.
A failed UI test also keeps a screen recording of itself in its bundle, which `ffmpeg -ss <seconds> -i <recording>.mp4 -frames:v 1 frame.png` turns into a still at any moment.
The UI tests turn the iPad to landscape before each launch (`XCUIApplication.porchlight()`): a new simulator boots in portrait, and on iPadOS 27 the landscape-only wall then draws sideways under a portrait keyboard.

**What stays local.** The hosted Macs have only iOS 27 simulators, so the iOS 17.5 run, the wall iPad's own OS, stays on the development Mac: run `scripts/test.sh` before a build goes to TestFlight, since the wall takes it too.

## Install on the wall iPad by cable

The wall iPad and the phones are all updated through TestFlight (see "TestFlight" below), since November 21, 2026.
Installing by cable is kept as a developer's option, for trying a build on the wall before it is uploaded, or for the Debug build the device tour and the idle CPU check need:

```bash
scripts/deploy-ipad.sh
```

This installs a Release build, which costs less CPU and power on a screen that is always on.
Before installing, it copies the wall's database and photos to `~/Library/Application Support/Porchlight/Backups` and stops if that copy fails.
A TestFlight update makes no such copy, so `scripts/backup-ipad.sh` is the way to copy the wall's data by hand, and `scripts/restore-ipad.sh <backup folder>` puts a copy back.

A scheduled reinstall by cable is optional too, and the household's own schedule was removed on November 21, 2026.
For a wall kept on cable installs, `scripts/schedule-deploy.sh` sets up a launchd job that reinstalls every Sunday and Wednesday at 3:00 am from a private git mirror of `main` (macOS does not let background jobs read ~/Documents), which keeps it on the latest commit and backed up twice a week; `scripts/schedule-deploy.sh --remove` takes the job, its git hook and the mirror's remote away again, from the main checkout or from a worktree.
An install signed with a paid Apple Developer team lasts a year; with a free Apple ID it expires after 7 days, which the schedule also covers.

## On iPhone

The app is universal.
The iPad keeps the wall, landscape only; an iPhone gets the pocket shell, portrait only: Today (with a companion's week, Pitch in and the next 7 days), Food (the week's plates, the diary and snapping a meal), Lists, Glow, and the You sheet with this phone's calendars and notifications.
It starts a household on its own, or joins one from an invite link or the code on the shared screen; You sets the household up (people, companions, chores, rewards, lists, the food diary), invites people, shows what the household stores, and leaves it (see [docs/design/households.md](docs/design/households.md)).
The layout follows the available width, and whether logging asks "who did it?" follows the device's role (shared screen or personal), kept on the device.
See [docs/design/phone-shell.md](docs/design/phone-shell.md).

```bash
scripts/sim-shot.sh <iphone-udid> /tmp/phone.png -sampleHousehold -me James
scripts/test.sh --phone --ui-only   # the phone's UI tests on an iOS 17.5 iPhone 15 simulator
```

## TestFlight

The wall iPad and the family's phones all get builds through TestFlight, without a cable.
A cable install (`scripts/deploy-ipad.sh`, a developer's option) is a Release build in the same CloudKit Production environment as a TestFlight build, so a wall installed either way shares one household with the phones.

One-time setup:
- The App Store Connect app is "Porchlight Homes", bundle id `com.mingyucao.porchlight`.
- Create an App Store Connect API key (App Store Connect › Users and Access › Integrations), keep the `.p8` file outside the repository (for example in `~/.appstoreconnect/`), and copy `Config/AppStoreConnect.example.env` to `Config/AppStoreConnect.env` with its path, key id and issuer id.
  That file is git-ignored; never commit the key or its ids.
- Exporting for App Store Connect signs with a distribution certificate: either the key has the Admin role, which lets it use Apple's cloud-managed distribution certificate, or this Mac has an Apple Distribution certificate of its own (Xcode › Settings › Accounts › Manage Certificates › +).
  A key without either archives fine and then fails to export with "Cloud signing permission error".
- The scripts that sign pass this key to `xcodebuild` (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`), because `xcodebuild -allowProvisioningUpdates` in a terminal may not see the account Xcode is signed in to ("No Accounts").

Each build:

```bash
scripts/testflight.sh --no-upload   # archive, export for App Store Connect, validate: a validated .ipa
scripts/testflight.sh --upload-only # upload that .ipa
scripts/testflight.sh               # both
```

It builds from a clean working tree only, so every build is a commit.
The version is `MARKETING_VERSION` in `project.yml`; the build number is the commit's time in UTC (`YYYYMMDD.HHMMSS`, `scripts/lib/version.sh`), so each later commit uploads higher without editing anything, a commit can be uploaded once, and a cable install of the same commit shows the same version.
Settings on the wall and the bottom of You on a phone show the version a device runs.

Testers:
- Internal testers (up to 100 people on the App Store Connect team) get a build as soon as Apple has processed it, with no review.
- External testers (anyone with an email address or a public link) need the build to pass a short Beta App Review first, once per version.
- Each build expires 90 days after upload; upload a new one before then, and TestFlight updates the wall and the phones.

## Layout

- `Porchlight/App` - app entry, live stores, kiosk behavior, debug launch hooks
- `Porchlight/Data` - SQLite (GRDB) core schema: household and people
- `Porchlight/Shared` - contracts between features (DayKey, TimelineItem, TimelineTarget, CalendarLane), shared components, weather
- `Porchlight/Shell` - the wall: side rail, destinations, idle switch to Ambient
- `Porchlight/Phone` - the pocket shell, its Today and the You sheet; `Phone/Kit` holds the phone's shared pieces
- `Porchlight/Screens`, `Onboarding`, `Settings` - Today, setup and settings
- `Porchlight/Features/{Calendar,Companions,Food,Home}` - each feature owns its schema, store, views and sample data
- `PorchlightTests` - Swift Testing suites, one folder per feature

Fonts (Fraunces, DM Sans, Caveat) are bundled under the SIL Open Font License; see `Porchlight/Resources/Fonts`.
