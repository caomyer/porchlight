# Release checklist

Everything a release to people outside our family needs, for milestone M5's gate ("the release checklist is complete").
TestFlight for the family already works; this list is what changes when a stranger installs Porchlight from the App Store, with their own household, their own iCloud and their own devices.

Each item says why it matters, where it stands, and the evidence.
States:

- **Done**: true today, with evidence anyone can check again.
- **To do**: work for us, in the repository.
- **Needs James**: a decision, an account, a legal text or a click only the developer account holder can make.

The list is checked again before every release that goes beyond TestFlight.

## Summary

| Area | Item | State |
|---|---|---|
| Privacy | App privacy manifest | Done |
| Privacy | Widget extension privacy manifest | Done |
| Privacy | App Store privacy answers ("nutrition label") | Needs James |
| Privacy | Privacy policy URL | Needs James |
| Privacy | Weather provider's terms for a public app | Needs James |
| Permissions | Usage strings for every permission | Done |
| Permissions | No permission asked before it is needed | Done |
| Compliance | Export compliance | Done |
| Compliance | Font licences shipped with the fonts | Done |
| Store | Support URL and contact | Needs James |
| Store | Name, subtitle, description, keywords, category, age rating | Needs James |
| Store | Screenshots for iPhone and iPad | To do |
| Store | App Review notes and a demo path | To do |
| iCloud | No iCloud account | Done |
| iCloud | iCloud full | Done |
| iCloud | The app's iCloud switched off, iCloud Drive off | To do |
| iCloud | A restricted account (Screen Time, managed) | To do |
| iCloud | CloudKit production schema before each release | Done |
| First run | A stranger with no household, on iPhone and iPad | Done |
| First run | Nothing from our family in a stranger's app | Done |
| Accessibility | Dynamic Type on the phone | Done |
| Accessibility | Text size on the wall | To do |
| Accessibility | VoiceOver labels | To do |
| Accessibility | Contrast | To do |
| Localisation | Ready to translate | To do |
| Localisation | Dates, times, units and first weekday follow the region | Done |
| Reliability | Crash and error reporting stance | Needs James |
| Data | Leaving a household and removing it from a device | Done |
| Data | Deleting a household from iCloud for good | To do |
| Builds | Versioning and build numbers | Done |
| Builds | Release build talks to CloudKit Production with production pushes | Done |
| Testing | What is tested on which OS versions | To do |
| Testing | UI suites fast enough to run before every release | Done |

## Privacy

### App privacy manifest

Why: since spring 2024 App Store Connect rejects an upload whose code calls a "required reason" API without declaring why, and the manifest is also where an app says it does not track.
State: done.
Evidence: `Porchlight/PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, no collected data, `UserDefaults` for this device's own settings (CA92.1), and file timestamp APIs for files in the app's own container (C617.1).
The timestamp entry covers `SyncTrace` reading its log file's attributes (`FileManager.attributesOfItem`), which returns the file's dates along with its size.
GRDB and swift-sharing ship their own manifests, and both are in the exported app (`GRDB_GRDB.bundle/PrivacyInfo.xcprivacy`, `swift-sharing_Sharing.bundle/PrivacyInfo.xcprivacy` in build 20261117.123733).
No other required-reason API is used: a search of the sources for disk space, system boot time, active keyboard and file timestamp calls finds only the one above.
The TestFlight uploads so far passed validation with no privacy manifest warning.

### Widget extension privacy manifest

Why: every bundle that ships code needs its own manifest; the extension is a separate bundle from the app.
State: done.
Evidence: `PorchlightWidgets/PrivacyInfo.xcprivacy` declares no tracking, no collected data and no required-reason APIs.
The extension reads one JSON file from the app group container and uses no `UserDefaults`, timestamps, disk space or boot time APIs (a search of `PorchlightWidgets` and `Porchlight/WidgetsShared`).

### App Store privacy answers

Why: App Store Connect asks what data the app collects before the first public release, and the answers show on the product page.
State: needs James.
The honest answers, from the code:

- No tracking, no ads, no analytics, no third-party SDK that collects anything.
- Household data (names, care logs, chores, meals, photos, calendar choices) lives on the devices and in the owner's iCloud private database, and people the owner shares it with read it through iCloud sharing; the developer never receives it, so Apple's definition counts it as not collected.
- Approximate location: the weather sends the coordinates rounded to about 1 km (two decimals) to api.open-meteo.com to get a forecast, and keeps no account or identifier there (`Porchlight/Shared/Weather.swift`).
  This is data sent to a third party, so the safe answer is "Coarse Location, used for App Functionality, not linked to the person, not used for tracking".
- Restaurant search goes through Apple's MapKit, which Apple covers.

### Privacy policy URL

Why: App Store Connect requires a privacy policy URL for every app.
State: needs James.
It needs a public page saying the above in plain words: what stays on the devices, what goes to the owner's iCloud and to whom it is shared, the weather request, no tracking, and how to delete everything (see "Deleting a household from iCloud for good").
A page on any domain James controls works; the App Store listing and the app's Settings should both link to it.

### Weather provider's terms

Why: Open-Meteo's free API is for non-commercial use; a public App Store app, even a free one, may need its commercial plan or another provider.
State: needs James.
Evidence: `OpenMeteo.url` calls `api.open-meteo.com` with no key.
The choices are Open-Meteo's paid API (a key and its customer endpoint), Apple's WeatherKit (500,000 calls a month included with the developer membership, and it needs the attribution Apple asks for), or no weather in public builds.

## Permissions

### Usage strings for every permission

Why: a missing usage string crashes the app the moment it asks, and App Review rejects vague ones.
State: done.
Evidence: `project.yml` sets `NSCalendarsFullAccessUsageDescription`, `NSCameraUsageDescription` and `NSLocationWhenInUseUsageDescription`, each saying what the app does with it.
Notifications need no string.
Siri and Shortcuts use App Intents, which need no `NSSiriUsageDescription`.
Every photo comes through `PhotosPicker`, which runs outside the app and needs no permission, so the app asks for no photo library string; nothing in the code reads the library itself (no `PHPhotoLibrary`, `PHAsset` or `UIImagePickerController`), and the photo flows pass without it (`CompanionEditorTests`, which opens the system picker, `MealPhotosTests`, `PhotoFrameTests`, `PhoneFoodTests.testSnappingAMeal`).

### No permission asked before it is needed

Why: App Review rejects apps that ask on launch, and people say no to prompts they don't understand.
State: done.
Evidence: calendars are asked for from "Allow calendar access" on the wall's calendar step and the phone's Calendars page (`FirstRunTests`, `PhoneTabsTests.testCalendarsFromYou`), notifications from the Notifications page after saying why (`PhoneRemindersTests.testSaysWhyBeforeAsking`), the camera from "Snap a meal" (`PhoneFoodTests.testCameraTurnedOff`), and location once for the weather.

## Compliance

### Export compliance

Why: every upload must say whether the app uses encryption beyond what the operating system provides.
State: done.
Evidence: `ITSAppUsesNonExemptEncryption` is `false` in the Info.plist, so uploads skip the question.
The app uses only HTTPS (URLSession, CloudKit) and CryptoKit hashes for ids and photo names, which are exempt.

### Font licences

Why: Fraunces, DM Sans and Caveat are under the SIL Open Font License, which allows bundling them in an app as long as the licence goes with them.
State: done.
Evidence: `Porchlight/Resources/Fonts/OFL-Fraunces.txt`, `OFL-DMSans.txt` and `OFL-Caveat.txt` sit beside the fonts.
An acknowledgements line in Settings would be kind but is not required.

## App Store listing

### Support URL and contact

Why: App Store Connect requires a support URL, and App Review needs a contact person with a phone number and email.
State: needs James.

### Name, subtitle, description, keywords, category, age rating

Why: required for the listing; the name must be free on the App Store.
State: needs James.
Suggested: category Lifestyle (second: Productivity); age rating 4+ (no user-generated content shared beyond the household, no web views, no purchases); the description should say an iPad wall and family iPhones, and that households live in the owner's iCloud.
Check that "Porchlight" is available as an App Store name before anything else is prepared.

### Screenshots

Why: the listing needs at least one set for the 6.9-inch iPhone and one for the 13-inch iPad.
State: to do.
The UI tests already draw every screen with sample data (`WallTourTests` with `--tour`, and the phone's tests at their snapshots), which is a good start, but App Store sizes and the sample household's names need a pass: the sample data should read as any family, not ours.

### App Review notes and a demo path

Why: a reviewer has one device and no household; the iPad wall and sharing between two Apple IDs are hard to see in a review.
State: to do.
The notes should say how to start a household on one device, what the wall is for, and that sharing needs a second Apple ID; a short screen recording of the wall and a phone helps.

## iCloud situations

### No iCloud account

Why: a stranger may not be signed in to iCloud, and the app must still work on that one device.
State: done.
Evidence: sync stays off and the app keeps working on the device; Settings and the phone's banner say "You're signed out of iCloud" (`SyncSettingsTests`, `PhoneHouseholdTests.testSyncBannersOnToday`, `HouseholdTests` with `-debugSyncStatus noAccount`).

### iCloud full

Why: the owner's iCloud fills up, and changes must keep saving on the devices.
State: done.
Evidence: sync pauses and says whose iCloud is full (`SyncSettingsTests.testAFullICloudPausesSync`, `PhoneSetupTests.testStorageWhenTheOwnersICloudIsFull`, `ArrivalsTests`).

### The app's iCloud switched off, iCloud Drive off

Why: people turn iCloud off per app in Settings, or turn iCloud Drive off, and CloudKit then answers differently from "signed out".
State: to do (app source).
Evidence: `SyncController.reconcile` treats every account status other than `.available` as "signed out", so a person who switched only Porchlight off is told they're signed out of iCloud, which they aren't.
CloudKit doesn't need iCloud Drive, so iCloud Drive off should change nothing; that needs one check on a real device.
To do: check on James's iPhone what `accountStatus` returns with Porchlight's iCloud switch off, and give it its own words ("iCloud is off for Porchlight in Settings").

### A restricted account

Why: Screen Time or a managed device can forbid iCloud, which CloudKit reports as `restricted`, and an account needing a new password reports `temporarilyUnavailable`.
State: to do (app source).
Evidence: both show as "signed out" today (`SyncController.reconcile`); neither is covered by a test.
To do: words for each ("iCloud isn't allowed on this device", "iCloud needs you to sign in again in Settings"), a `-debugSyncStatus` value for each, and a UI test.

### CloudKit production schema before each release

Why: Production only knows what was deployed to it, and a release with a new table or column fails on its first real value there.
State: done (the process); it runs again before every release that adds a table or column.
Evidence: `docs/design/sync-icloud.md`, "Deploying the CloudKit schema": `scripts/cloud-schema.sh seed`, `export`, review of `Config/cloudkit-schema.ckdb`, Deploy in the CloudKit Console, then `scripts/cloud-schema.sh check`.

## First run

### A stranger with no household

Why: the first minute decides whether a stranger keeps the app.
State: done.
Evidence: the iPad's onboarding (`FirstRunTests`, `HouseholdTests.testSetupAsksHowThisIPadIsUsed`), the phone's welcome with "Start a household" and "Join one" (`PhoneHouseholdTests.testTheWelcomeExplainsBothWaysIn`), starting a household on the phone (`PhoneSetupTests.testStartingAHouseholdOnThisPhone`), an empty Today that offers setup (`PhoneSetupTests.testAnEmptyTodayOffersSetup`), and a fresh install looking for a household in iCloud first (`SyncSettingsTests.testAFreshInstallLooksForItsHouseholdFirst`).

### Nothing from our family in a stranger's app

Why: a stranger must never see our names, our dog or our household.
State: done.
Evidence: the sample household (James, Mia, Ava, Yo-Yo, The Lake House) is only reachable through `-sampleHousehold` and the other debug launch arguments, which exist in Debug builds only (`DebugLaunch` and `DebugSharing` are wrapped in `#if DEBUG`, as are their callers in `PorchlightApp`); a Release build cannot load it.
The examples people see in empty fields name a place and a pet that could be anyone's: "e.g. The Maple Street house" for the household on the iPad and the phone (`OnboardingView`, `PocketSetup`), "e.g. Sam" for your name, and "e.g. Biscuit" or "e.g. Fiddle-leaf fig" for a companion, as the wall's companion editor already said.
Doc comments mention our names only as examples in code, which ship nowhere.

## Accessibility

### Dynamic Type on the phone

Why: many people use larger text; App Store review and real use both expect it.
State: done.
Evidence: every phone screen is checked at the largest accessibility size (`PhoneTests.testLargestText`, `PhoneTabsTests.testLargestText`, `PhoneFoodTests.testLargestText`, `PhoneHouseholdTests.testLargestText`, `PhoneRemindersTests.testLargestText`, `PhoneFoodTests.testPaperUnderTheStatusBarAtTheLargestSize`).

### Text size on the wall

Why: the wall is read from across a room, and its text is laid out at fixed sizes for that.
State: to do (decide).
The wall's sizes are fixed on purpose; what needs deciding is whether its Settings and sheets, which are read up close, should follow the system text size.

### VoiceOver labels

Why: people who use VoiceOver need every control named and every decorative image hidden.
State: to do.
Evidence: 158 `accessibilityLabel`s and the UI tests drive the app through its accessibility tree, so every tested control has a name; nothing yet walks every screen with VoiceOver itself.
To do: one pass on each phone tab and the wall's screens with VoiceOver on a device, and an Accessibility Inspector audit of each.

### Contrast

Why: muted text on the paper background must stay readable, in light and night looks.
State: to do.
To do: an Accessibility Inspector contrast audit of `Theme`'s muted and accent colors on both backgrounds, and Increase Contrast checked on the phone.

## Localisation

### Ready to translate

Why: a release outside our family may be in other languages; it is far cheaper to keep strings translatable than to retrofit.
State: to do (only when a second language is planned).
Evidence: there is no string catalog, and many sentences are built with string interpolation outside `Text`, which SwiftUI cannot pick up for translation.
English-only is a fine first release; this item becomes work when a second language is planned.

### Dates, times, units and first weekday

Why: a stranger may use 24-hour time, Celsius or a Monday week.
State: done.
Evidence: times and dates go through the household's `Calendar` and `Date.FormatStyle`, and the weather picks Fahrenheit only where the region measures in US units (`OpenMeteo.usesFahrenheit`); the household's time zone is its own (`Household.calendar`).

## Reliability

### Crash and error reporting stance

Why: once strangers use the app, we only learn of crashes from what Apple collects or from what we add.
State: needs James.
Today there is no third-party crash reporter and no analytics, which matches the privacy answers above; crashes reach App Store Connect and Xcode's Organizer from people who share analytics with developers, and TestFlight testers can send feedback.
Sync problems are explained on the device (Sync details, the sync log) rather than sent anywhere.
The decision is whether that is enough; adding a reporter changes the privacy answers.

## Data

### Leaving a household and removing it from a device

Why: people must be able to leave, and to take the household off a device they no longer use.
State: done.
Evidence: a member leaves from You (`PhoneSetupTests.testAMemberLeaves`); the owner is pointed to removing someone instead (`PhoneSetupTests.testTheOwnerIsPointedToRemovingSomeone`, `HouseholdTests.testTheOwnerRemovesSomeonesPhone`); a removed device says so once and starts over (`PhoneHouseholdTests.testARemovedHouseholdSaysSoOnce`); "Remove from this iPad" after an account change (`SyncSettingsSection`).

### Deleting a household from iCloud for good

Why: an owner must be able to delete everything, and the privacy policy has to say how.
State: to do (app source), needs James for the wording.
Today the owner cannot delete the household from the app: You says "It's yours, so it stays with you".
iOS can delete it from Settings, Apple Account, iCloud, Manage Account Storage, Porchlight, Delete Data, which removes the app's private database including the shared household; members then see the household as removed.
To do: decide between a "Delete household" button for the owner (delete the zone, which ends the share for everyone) and documenting the Settings path in the app and the privacy policy.

## Builds

### Versioning and build numbers

Why: every upload needs a higher build number, and people and support need to know which build they run.
State: done.
Evidence: `MARKETING_VERSION` in `project.yml` is the one version (0.1.0); signed builds take the commit's UTC time as the build number (`scripts/lib/version.sh`), so builds of later commits always sort later; the app shows its version and build in the wall's Settings and the You sheet (`AppVersion`, `AppVersionTests`).
Before the first public release, `MARKETING_VERSION` becomes 1.0.

### Release builds use CloudKit Production with production pushes

Why: TestFlight and App Store builds must meet the wall's Release build in the same CloudKit environment, and pushes must use the production APNs environment.
State: done.
Evidence: Release sets `com.apple.developer.icloud-container-environment` to Production (`project.yml`), and the exported TestFlight app's entitlements show `aps-environment` `production` and the container environment `Production` (`codesign -d --entitlements` on build 20261117.123733).

## Testing

### What is tested on which OS versions

Why: the deployment target is iOS 17.0, the wall runs iPadOS 17, and strangers' phones run iOS 17 through the latest.
State: to do.
Evidence: the unit tests and both UI suites run on iOS 17.5 simulators (`scripts/test.sh`); real-device checks are the wall (iPadOS 17) and James's iPhone.
Code paths that differ by version are the join code (iOS 18 and later, `LiveHouseholdSharing.supportsJoinSeats`) and restaurant details (iOS 18 and 26, `RestaurantSearch`).
To do: run the phone's UI suite on the newest iOS simulator before each release (`scripts/test.sh --phone --ui-only --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5`, which makes this checkout's simulator for that iOS), and one pass of the join code between two real devices on iOS 18 or later.
The first run of the phone's smoke set on iOS 26.5 (November 17) passed 4 of 6: `PhoneSetupTests.testStartingAHouseholdOnThisPhone` failed typing a name and `PhoneFoodTests.testSnappingAMeal` timed out waiting for the camera page.
Neither is the app: typing "Maple" a key at a time on iOS 26.5, with a moment between keys, kept the focus and the text every time, and the snapping failure's spindump shows the app's main thread stopped in the kernel, paging the iOS 26.5 runtime's disk image in, after a ten-minute launch.
On a slow simulator the field reports its focus a moment after each key, and a tap computed from a new layout can land on what is still drawn there, so the phone tests' `type` now waits for the focus before each key and leaves a field the app focused itself untapped.

### UI suites fast enough to run before every release

Why: a check that takes an hour gets skipped.
State: done.
Evidence: `scripts/test.sh` runs everything in 26 minutes on the 16 GB M4 with the two UI suites side by side (44.8 minutes before), and `scripts/test.sh --smoke` runs the unit tests and 13 UI tests across both shells in about 6 minutes (README, "Running the tests").

## Who does what

For us, in the repository, without a decision first:

- The phone's UI suite on iOS 26 on a quiet Mac, then fix what it finds ("What is tested on which OS versions").
- Words and a test for the app's iCloud switched off, a restricted account and an account needing a new password (`SyncController`, app source).
- A VoiceOver pass and an Accessibility Inspector audit, contrast included, on each phone tab and the wall's screens.
- App Store screenshots from a sample household that reads as any family.
- App Review notes and a short recording of the wall and a phone.

For James:

- The App Store privacy answers, the privacy policy and support URLs, and the contact for App Review.
- The listing: the name's availability first, then subtitle, description, keywords, category and age rating.
- The weather provider for a public app.
- The crash and error reporting stance.
- Deleting a household for good: a button for the owner, or the Settings path written into the app and the privacy policy.
- Whether the wall's Settings and sheets follow the system text size.
- Whether to plan a second language.
