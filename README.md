# Porchlight

A family wall calendar for an iPad you already own.
The household, its people, companions and journals are all set up in the app; nothing about one family is hard-coded.

The product plan and UX mocks live in [.lavish/porchlight.html](.lavish/porchlight.html).

## Develop

`project.yml` is the source of truth; the Xcode project is generated.

```bash
brew install xcodegen
cp Config/Local.example.xcconfig Config/Local.xcconfig   # then set DEVELOPMENT_TEAM
xcodegen generate
open Porchlight.xcodeproj
```

Run the tests on an iPad simulator:

```bash
xcodebuild test -project Porchlight.xcodeproj -scheme Porchlight \
  -destination 'platform=iOS Simulator,name=iPad (10th generation)' CODE_SIGNING_ALLOWED=NO
```

Debug-only launch arguments: `-resetData` (start at onboarding), `-sampleHousehold` (seed two people), `-startScreen settings`.

## Install on the wall iPad

```bash
scripts/deploy-ipad.sh
```

With a free Apple ID the install expires after 7 days, so the Mac mini reruns this weekly.

## Layout

- `Porchlight/App` - app entry, live app state, kiosk behavior
- `Porchlight/Data` - SQLite (GRDB) schema, migrations, models and all writes
- `Porchlight/Design` - Sunday Paper tokens, fonts and shared components
- `Porchlight/Shell` - the wall: side rail and destinations
- `Porchlight/Screens`, `Onboarding`, `Settings` - screens
- `PorchlightTests` - Swift Testing suites

Fonts (Fraunces, DM Sans, Caveat) are bundled under the SIL Open Font License; see `Porchlight/Resources/Fonts`.
