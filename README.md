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
- `-debugFoodView snap|details|detail` on a phone (with `-startScreen food`): open the camera, the details of a new meal, or today's first meal; `-sampleFood none` with `-sampleHousehold` leaves the diary empty, and `-samplePhotoMeals` gives every meal of the sample week two photos (the first launch draws and caches them, which takes a while)
- `-debugReminderIn N` on a phone with notifications really allowed: the day's first care reminder arrives N seconds after launch, to try delivery and its actions by hand; `TEST_RUNNER_PORCHLIGHT_DELIVERY=1` with `-only-testing:PorchlightUITests/PhoneRemindersTests/testDeliveryByHand` runs that check
- `-me NAME` on a phone: this phone belongs to the person called NAME, so it skips "Which one is you?" (for example `-sampleHousehold -me James`)
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
`scripts/test.sh` runs the unit tests and then the UI tests on an iOS 17.5 iPad simulator, resetting the calendar permission so the first-run test sees the prompt.
It skips the screen tour, which only takes screenshots for review; add `--tour` before deploying.
Each checkout builds into its own DerivedData folder, so worktrees can test side by side, but two UI suites at once slow each other enough to time out.

```bash
scripts/test.sh
```

## Install on the wall iPad

```bash
scripts/deploy-ipad.sh
```

This installs a Release build, which costs less CPU and power on a screen that is always on.
Before installing, it copies the wall's database and photos to `~/Library/Application Support/Porchlight/Backups` and stops if that copy fails.
`scripts/backup-ipad.sh` makes such a copy on its own, and `scripts/restore-ipad.sh <backup folder>` puts one back.

`scripts/schedule-deploy.sh` sets up a launchd job that reinstalls every Sunday and Wednesday at 3:00 am from a private git mirror (macOS does not let background jobs read ~/Documents).
That keeps the wall on the latest commit and backed up twice a week.
An install signed with a paid Apple Developer team lasts a year; with a free Apple ID it expires after 7 days, which the schedule also covers.

## On iPhone

The app is universal.
The iPad keeps the wall, landscape only; an iPhone gets the pocket shell, portrait only: Today (with a companion's week, Pitch in and the next 7 days), Food (the week's plates, the diary and snapping a meal), Lists, Glow, and the You sheet with this phone's calendars and notifications.
It joins a household from an invite link or the code on the shared screen, and You lists the household's people and their devices and invites more (see [docs/design/households.md](docs/design/households.md)).
The layout follows the available width, and whether logging asks "who did it?" follows the device's role (shared screen or personal), kept on the device.
See [docs/design/phone-shell.md](docs/design/phone-shell.md).

```bash
scripts/sim-shot.sh <iphone-udid> /tmp/phone.png -sampleHousehold -me James
scripts/test.sh --phone --ui-only   # the phone's UI tests on the iOS 17.5 iPhone 15 simulator
```

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
