# Porchlight

A family wall calendar for an iPad you already own.
The household, its people, companions and journals are all set up in the app; nothing about one family is hard-coded.

The product plan and UX mocks live in [.lavish/porchlight.html](.lavish/porchlight.html).

## What it does

- **Today**: big clock, local weather, one timeline mixing calendar events, care logs (walks, feeding) and meals, plus companion cards, today's plates and countdowns.
- **Calendar**: Week, Month and Day views of every calendar on the iPad (via EventKit), colored by person, with paw and plate lanes.
- **Companions**: pets, plants or anything cared for; routines with time windows and turn rotation, logging with celebration, a weekly page with paw trail, podium, mood meter and cheeky captions.
- **Food diary**: snap a meal with the camera, home-cooked or delivery, a polaroid week where any meal can be fixed or removed, and a handwritten paper month written with Apple Pencil (one fixed-ratio page per day, zoomed for writing).
- **Chores and rewards**, **Lists and meal plan**, and an **Ambient** photo frame with a night clock.

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
- `-startScreen today|calendar|companion-1|food|chores|lists|photos|settings`
- Feature previews: `-calendarMode month|day`, `-debugCompanionSheet log|celebrate|onboarding|editor|routine`, `-debugFoodView month|write|capture|saved|detail`, `-homeSheet newChore|whoDidIt|week|ambient|...`

Review the real iPad's rendering (sample data lives in a separate storage sandbox, so the household's data is never touched):

```bash
scripts/device-tour.sh /tmp/porchlight-device-tour
```

UI tests (screen tour, handwriting round trip, meal editing, keyboard placement, scrolling, the idle timer, and a first run that grants real calendar access and assigns a calendar) run with the `PorchlightUI` scheme on a simulator.
The wall iPad runs iPadOS 17, so run them on an iOS 17.5 simulator too (`xcodebuild -downloadPlatform iOS -buildVersion 17.5`).
Reset the calendar permission first (`xcrun simctl privacy <udid> reset calendar com.mingyucao.porchlight`) so the first-run test sees the prompt.

## Install on the wall iPad

```bash
scripts/deploy-ipad.sh
```

With a free Apple ID the install expires after 7 days. `scripts/schedule-deploy.sh` sets up a launchd job that reinstalls every Sunday and Wednesday at 3:00 am from a private git mirror (macOS does not let background jobs read ~/Documents).

## Layout

- `Porchlight/App` - app entry, live stores, kiosk behavior, debug launch hooks
- `Porchlight/Data` - SQLite (GRDB) core schema: household and people
- `Porchlight/Shared` - contracts between features (DayKey, TimelineItem, CalendarLane), shared components, weather
- `Porchlight/Shell` - the wall: side rail, destinations, idle switch to Ambient
- `Porchlight/Screens`, `Onboarding`, `Settings` - Today, setup and settings
- `Porchlight/Features/{Calendar,Companions,Food,Home}` - each feature owns its schema, store, views and sample data
- `PorchlightTests` - Swift Testing suites, one folder per feature

Fonts (Fraunces, DM Sans, Caveat) are bundled under the SIL Open Font License; see `Porchlight/Resources/Fonts`.
