# Porchlight

A family wall calendar for an iPad you already own.
The household, its people, companions and journals are all set up in the app; nothing about one family is hard-coded.

The product plan and UX mocks live in [.lavish/porchlight.html](.lavish/porchlight.html).

## What it does

- **Today**: big clock, local weather, one timeline mixing calendar events, care logs (walks, feeding), meals and chores done, plus companion cards, a Pitch in card with today's chores to check off, today's plates and countdowns.
- **Calendar**: Week, Month and Day views of every calendar on the iPad (via EventKit), colored by person.
  Walks, feeds and meals sit in the week and day grids at their times, chores in a Pitch in lane, and each opens the same sheet as on Today.
- **Companions**: pets, plants or anything cared for; routines with time windows, logging who did it and when with a celebration, tap any logged walk to fix or remove it, a weekly page with paw trail, podium, mood meter and cheeky captions.
- **Food diary**: snap a meal with the camera or pick from Photos (up to 6 photos per dish, the first as its cover; the shutter only takes a photo, and the meal saves on Save), with a square viewfinder that is exactly the polaroid; the whole shot is kept, any photo can be reframed by dragging and zooming, and tapping a meal's polaroid shows the whole photo; add photos to a saved meal any time, home-cooked, delivery, dining out (with the restaurant picked from live Apple Maps search) or company food, several dishes per meal, a polaroid week where any meal can be fixed or removed, and a handwritten paper month written with Apple Pencil (one fixed-ratio page per day, zoomed for writing). Times on meals and care logs show as a pill; tapping it opens a ruler of the day with the usual meal times or routine windows shaded, ±5 min nudges, and later than now out of reach.
- **Pitch in**: what everyone does for the household on one board, a column per person plus "Anyone" for shared chores and companion care. Tap a box to check it off, a row to fix who did it, undo, edit or archive it. Chores and routines share one repeat rule (every day, some weekdays, every few days, monthly, just once) with a start day.
- **Glow**: everyone's stars in one place. Every chore and every walk or feed earns stars, the week shows as sparks around the porch light, and rewards are saved up for and cashed in.
- **Lists and meal plan**, and an **Ambient** photo frame with a night clock.

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
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Porchlight-main CODE_SIGNING_ALLOWED=NO
```

Screenshot a screen with sample data:

```bash
scripts/sim-shot.sh <simulator-udid> /tmp/today.png -sampleHousehold -startScreen today
```

Debug-only launch arguments:
- `-resetData` (start at onboarding), `-sampleHousehold` (seed a sample household with a week of everything)
- `-startScreen today|calendar|companion-1|food|chores|glow|lists|photos|settings`
- Feature previews: `-calendarMode month|day`, `-debugCompanionSheet log|celebrate|onboarding|editor|routine`, `-debugFoodView month|write|capture|saved|detail` (with `-debugCaptureShots N` to start the capture with N generated photos), `-homeSheet newChore|whoDidIt|week|ambient|...`

Review the real iPad's rendering (sample data lives in a separate storage sandbox, so the household's data is never touched):

```bash
scripts/device-tour.sh /tmp/porchlight-device-tour
```

UI tests (screen tour, handwriting round trip, meal editing, fixing who did a chore, care from the board, cashing in a reward, several dishes per meal, several photos per meal, dining out with restaurant search, editing a companion and adding a routine, fixing logged walks and meals from Today, picking times on the day ruler, chores on Today and in the calendar, walks and meals in the week grid, keyboard placement, scrolling, the idle timer, and a first run that grants real calendar access and assigns a calendar) run with the `PorchlightUI` scheme on a simulator.
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

With a free Apple ID the install expires after 7 days. `scripts/schedule-deploy.sh` sets up a launchd job that reinstalls every Sunday and Wednesday at 3:00 am from a private git mirror (macOS does not let background jobs read ~/Documents).

## Layout

- `Porchlight/App` - app entry, live stores, kiosk behavior, debug launch hooks
- `Porchlight/Data` - SQLite (GRDB) core schema: household and people
- `Porchlight/Shared` - contracts between features (DayKey, TimelineItem, TimelineTarget, CalendarLane), shared components, weather
- `Porchlight/Shell` - the wall: side rail, destinations, idle switch to Ambient
- `Porchlight/Screens`, `Onboarding`, `Settings` - Today, setup and settings
- `Porchlight/Features/{Calendar,Companions,Food,Home}` - each feature owns its schema, store, views and sample data
- `PorchlightTests` - Swift Testing suites, one folder per feature

Fonts (Fraunces, DM Sans, Caveat) are bundled under the SIL Open Font License; see `Porchlight/Resources/Fonts`.
