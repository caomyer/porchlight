# The phone shell: B1, B2, E1 and the phone kit

This is how the first iPhone screens are built (milestone M2 in `docs/proposals/companion-ux.html`).
It covers the universal app, the device role and "me", the phone kit, the pocket shell, Today (B1), logging care (B2) and the You sheet (E1).
Joining a household, sync, and the Food, Lists and Glow tabs are later work.

## One app, two shells

The app is universal (`TARGETED_DEVICE_FAMILY: "1,2"`).
The iPad stays landscape only, the iPhone is portrait only.
`RootView` picks the shell by the available width: a regular width gets the wall (`WallRoot`: onboarding or `WallView`, the kiosk behavior and the forced light look), a compact width gets the pocket shell (`PocketRoot`).
Neither shell looks at the kind of device, so a personal iPad would still get the wall, as the atlas says it should.
The wall's view tree is unchanged; it only moved from `RootView` into `WallRoot`.

Info.plist keeps the wall's launch keys as they were and adds iPhone overrides: a launch color that follows dark mode and a visible status bar.
The phone shows its status bar, lets the screen sleep and has no Ambient mode, because the kiosk behavior belongs to the wall shell.

## Device role and "me"

`DeviceSettings` (in `App/DeviceSettings.swift`) holds what belongs to this device and never to the household, in `UserDefaults`.
`DeviceRole` is `.sharedScreen` (asks who did it) or `.personal` (credits its owner).
`DeviceRole.standard(for:)` is the only place that looks at the device idiom: shared on iPad, personal on iPhone.
Everything else reads `DeviceSettings.role`.
"Me" is stored per household id (`device.me.<household id>`), so a phone in two households can be a different person in each later.
A stored person who has been archived counts as nobody, so the phone asks again.

`PocketRoot` decides what the phone shows:

- no household that finished setup: `PocketWelcome`, which says that iPhone joins from an invite link and that invites arrive in a coming version, with no buttons;
- a personal phone that doesn't know who it is: `WhoAreYouView`, the atlas's `a4who` without the join steps around it;
- otherwise the four tabs, with the person in the environment as `\.me`.

## The phone kit

`Phone/Kit` holds the pieces every phone screen shares, built on `Theme.swift`, the bundled fonts and the avatar colors:

- `PhoneType`: `phoneFont`, the wall's faces at the atlas's sizes, scaled with Dynamic Type, and `PhoneMetric`, a length that grows with the text but only up to a cap (avatars, faces, check boxes).
- `PersonAvatar`: the wall's `Avatar` at the phone's three sizes; a missing person shows the household's heart.
- `CarePieces`: `CompanionBadge`, `CareSlotTile`, `PersonPill` (also went, who went) and `PhoneChoice` (a sheet's choices).
- `PhoneChoreRow`: a chore of yours, or one anyone can take.
- `StatusBanner`: the warn, good and info banners.
- `UndoToast` and `ToastCenter`: one toast at a time, five seconds (twelve with VoiceOver), announced to VoiceOver.
- `PhoneSheet`: the bottom sheet, as tall as its content.
- `PhoneCard`: the card, the full-width button style, the done capsule, the small tag and the card header.

### The night look

The theme's colors now have a night value, the warm dark palette of the atlas's `.sc.dark` frame, plus soft accent, good and warn tokens the phone needs.
The phone follows the system; the wall keeps forcing the light look with `.preferredColorScheme(.light)`, so it only ever sees the first value.
`Color.wash` mixes colors outside any view, where a dynamic color can't know its look, so it now resolves both colors in an explicit color scheme, light by default.
That keeps every wash on the wall exactly as it was, whatever the iPad's own setting, and the phone passes its environment's scheme.

## The shell

`PocketShell` is a system `TabView` with Today, Food, Lists and Glow, using the wall rail's SF Symbols and the DM Sans tab labels.
Food, Lists and Glow show their header and "Coming to the phone soon", nothing else.
Every tab's header has the "You" avatar at the top right; it opens `YouSheet`.
The toasts are drawn over the whole shell.
`-startScreen today|food|lists|glow|you` opens a tab or the You sheet.

## Today (B1)

`PocketToday` is the pure part and has its own tests.
It reads the same `CompanionReport`, `CareLogic`, `CareCatchUp` and `ChoreBoard` the wall uses, so counts match the wall's.

Top to bottom:

1. The header: the household's date and "Hi, James".
2. One catch-up banner: the newest slot whose window closed without a log, today or earlier in the wall's catch-up week.
3. The companions, the ones with a window open now first, then the household's order.
   One companion gets a full card; several go to a grid of two (back to full cards at accessibility text sizes).
4. "Yours today": my column of the wall's board for today, in board order, or a good banner, "Nothing else for you today", once nothing of mine is left.
5. "Anyone can take": the board's Anyone column for today.
6. "At home today": today's calendar events, only when calendar access is already granted.

The stores observe the database, and Today redraws every minute, so a log from anywhere shows up as soon as it is written.

## Logging (B2)

One tap logs care for me now, credited to me and anyone picked under "Also went".
`PocketLogging` writes it and shows a toast with Undo; Undo deletes the log.
"More…" opens `PocketCareSheet`, and the catch-up banner opens `PocketCatchUpSheet`.

Never confidently out of date (rule 10): one tap and catch-up call `AppDatabase.logCare(routineId:slot:on:_:now:)`, which reads the slot again inside the write.
If someone already logged it, nothing is added; the toast says who and when ("Mia walked Yo-Yo at 5:40pm") and offers "I went too", which adds me to their log (with its own Undo).
Chores do the same with `AppDatabase.completeChore`: a chore someone just checked off is never unchecked by a stale tap, and the toast says who did it.

The wall's care form logic moved out of its view into `CareLogFields` and `CareLogDay`, and the time pill's day math into `LogTimeDay`, so the wall's log sheet, the phone's care sheet and the phone's catch-up pad share one implementation.
The wall's form behaves exactly as before.

## You (E1)

The sheet shows my avatar and name, the household and this phone's role, then three rows: the household (its name and people), this phone (its role), and "This iPhone is James", which opens "Which one is you?" to change it.
Nothing else is listed until it works.

## Accessibility

All phone text uses `phoneFont`, so it follows Dynamic Type to the largest accessibility size.
At accessibility sizes, rows with a trailing action, banners and the toast stack instead of squeezing, the slot grid becomes one column, and buttons keep their full width and wrap their label.
Every control is at least 44 pt; small pills keep their look and get a 44 pt tap area.
Buttons read their result: "Log Yo-Yo's evening walk", "Check off Fix the leaky faucet", "Check off Vacuum the living room as yours".

## Tests

- Unit: `PocketTodayTests` (which slot one tap logs, card order, freshness, catch-up, my chores and the shared ones, stars, the words), `PocketWritesTests` (the already-logged path, joining and its undo, undo of a log, chores that are already done), `DeviceSettingsTests` (role defaults, stored role, "me" per household, forgetting) and `CareLogFieldsTests`.
- UI: `PhoneTests`, which runs only on an iPhone; `scripts/test.sh --phone --ui-only` runs it on the iOS 17.5 iPhone 15 simulator, and the iPad run skips it.
  Each test attaches a screenshot of every screen it visits.

## Judgment calls

Where the atlas was silent, or didn't fit the code:

- **Which slot one tap logs.** The atlas shows the button while a window is open. The phone uses the wall's own rule for where a log belongs (`CareLogic.windowIndex`): the button logs the slot a log made now would fill, as long as that slot is still waiting and its window hasn't closed. So at 2 pm it logs the coming evening walk (as the wall would), at 11 am, with the morning done, there is no button, and a slot whose window closed is caught up on at its real time instead of being logged "now".
- **Rule 10 checks the slot, not the time.** The write re-reads the slot it was asked to fill. The full care sheet (More…) is a deliberate, detailed log and adds a log like the wall's sheet does, so two people can still each log a walk ("both entries kept").
- **"I'll do it" checks the chore off.** There is no way to claim a chore in the data, and adding one is a schema change best made with B4. Taking a shared chore checks it off, credited to me, with Undo, and the button says "I did it" so it doesn't promise a claim.
- **Done rows stay where they are.** Chores keep the board's order and a done row stays, crossed out, so nothing jumps under your thumb. A done row is not a button; Undo on the toast takes a check-off back, and fixing older ones stays on the wall for now.
- **A finished card.** A companion whose day is done shows "✓ Logged" for 15 minutes after its last log (the `b2tap` frame), then folds to "Yo-Yo is all set" (`b1clear`). The time comes from the data, so it survives a relaunch.
- **One missed slot at a time, and only once.** The banner shows the newest missed slot, today's or earlier in the week the wall lets you catch up on. It has a "Not now" button; a dismissed slot is remembered on the device and never shown again.
- **Catch-up asks only when.** The pad is the wall's `TimeKeypadCard`, laid into the sheet. Its suggestions are the usual time and the slot window's start, middle and end. Who did it is me.
- **The care sheet's layout.** The atlas puts labels beside the choices; the phone puts each label above its choices, which wraps cleanly at large text sizes. The fields, durations and defaults are the wall's.
- **No celebration on the phone.** The wall's confetti is a moment for the room; the phone confirms with the toast.
- **Toast words.** "The wall shows it now" is left out: there is no sync on this branch, and the toast shouldn't promise it. The toast says what was logged, with whom, and the stars.
- **Icons.** The tab bar uses the wall rail's SF Symbols instead of the atlas's emoji placeholders, so a place looks the same on both.
- **Pending slots show the routine's emoji** (🦮, 🥣, 💧) instead of a paw for every kind.
- **"Which one is you?" has no subtitles.** The atlas says who has a phone or hasn't joined; there are no members yet, so the rows are just names.
- **The You sheet.** It shows the household's name and people, the role, and changing who you are. There is no owner yet, so "owner" isn't shown. The role is shown, not changed: a shared iPhone would need a who-picker throughout, which no journey asks for yet.
- **A shared screen in the pocket shell.** If a phone's role were shared, Today asks who did it in a confirmation dialog before logging, and lists every chore under "Anyone can take". Nothing sets that role on a phone today, but the shell reads the role rather than assuming.
- **No agenda link.** "Next 7 days ›" is B8 and isn't built, so the agenda card has no link.
- **Empty households.** Without companions or chores, Today shows one calm line saying they appear once set up on the shared screen; it offers no setup actions, since the editors aren't on the phone yet.
- **"This iPhone".** Sentences name the device with `UIDevice.current.model`; that only picks words and never decides behavior.
- **Sample time.** The sample household's care depends on the hour. `-debugCompanionNow` already pinned "now" for care screens; the phone's writes now use it too, so the UI tests pin 5:20 pm and always find the evening walk and dinner open, whatever the hour they run.

## Fixed on the wall along the way

Nothing on the wall looked broken while working here.
The only wall code that changed is the shared logic moved out of the care form and the time pill, and `Color.wash` resolving its colors explicitly; the wall's UI tests cover both.
