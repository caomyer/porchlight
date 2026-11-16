# The phone shell and its everyday screens

This is how the iPhone screens are built (milestones M2 and M3 in `docs/proposals/companion-ux.html`).
It covers the universal app, the device role and "me", the phone kit, the pocket shell, Today (B1), logging care (B2), a companion's week (B3), Pitch in (B4), Lists and dinners (B6), Glow (B7), the next 7 days (B8), the You sheet (E1) and the calendars on the phone (E3).
Joining a household, sync and the Food tab are later work.

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
Food shows its header and "Coming to the phone soon", nothing else, until the next milestone.
Every tab's header has the "You" avatar at the top right, and so does every page pushed under Today; it opens `YouSheet`.
Each tab paints paper under the status bar (`paperUnderStatusBar`), so scrolled content never shows through the clock.
Today has its own navigation stack: a companion's week, Pitch in, the next 7 days and the calendars are pushed onto it, with the system back button.
The toasts are drawn over the whole shell.
`-startScreen today|food|lists|glow|you|week|pitchIn|nextWeek|calendars` opens a tab, the You sheet or one of Today's pages.

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
6. "At home today": today's calendar events with "Next 7 days ›".
   Without calendar access, or with no calendar chosen, it is one row, "No calendars chosen", to the Calendars page.

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

## A companion's week (B3)

Tapping a companion's card (its face and name, or the whole card when it is all set) opens `PocketCompanionWeek`.
It is the wall's companion page in one column, built from the same `CompanionReport`: the hero with the week in a line (`CompanionReport.weekSummary`, moved out of the wall's page so both use it) and the mood, Paw trail, the diary with missed slots in their place, the walker of the week and the little milestones.
Wording comes from the routine's kind, so a plant gets "who watered" and "Gardener of the week".
A first week shows "The first week together" and an empty trail of dashed rings, never a zero.
A missed slot in the diary opens the phone's catch-up sheet.

## Pitch in (B4)

"See all" on "Yours today" (or on its banner once everything is done) opens `PocketPitchIn`.
The header counts this week's chore days, done of all, from the wall's week marks.
A segmented control picks Yours (today's, then what I did earlier this week), Open (shared chores nobody has done today) or Everyone (every person's column, kids included, then Anyone).
Someone else's chore is shown, not checkable: it is theirs to check off on their phone or the wall.
"+ Add a chore" opens the wall's `ChoreEditor` in a phone sheet (`PhoneEditorSheet`), with its repeat picker and start day; the editor now stacks its time hints and buttons at a compact width, and starts a new chore as mine.

## Lists and dinners (B6)

The Lists tab picks a list, or this week's dinners, with chips at the top.
A grocery list is grouped by aisle (`GrocerySections.group`, now shared with the wall), each item with who added it; the field on top adds an item credited to me, and checking one crosses it out until someone taps "Clear checked".
The same item added twice shows twice.
Dinners are the wall's meal plan for the week; a dinner opens the wall's `MealEditor` as a phone sheet, and its cart button asks what it needs and puts each item, split at commas, on the grocery list in its aisle (`DinnerIngredients`).

## Glow (B7)

The Glow tab shows my stars this week and all time under the porch light, what I'm saving for (shared goals first, then my own treats), and everyone's week as bars, all from the wall's `GlowSummary` and `RewardProgress`.
A reached reward has "Cash in 🎉"; the sheet names everyone who earned this round (`PocketGlowLogic.earners`) before anything is spent.
Cashing in uses the wall's `cashInReward` with its derived id (one cash-in per round, whichever device does it), and `HomeStore.cashIn` now returns the cash-in so the phone knows it happened.
The phone that cashed in shows the celebration: the reward, who earned it and confetti that falls once and stays; it waits for Done and nothing loops.

## The next 7 days (B8)

`PocketNextWeek` reads the calendar store's events for the next seven days, skips empty days and puts all-day events first (`PocketAgendaLogic`).
Each row has the person's color and avatar; busy-only calendars say "Busy".
Tapping an event opens the Calendar app at that time (`calshow:`); nothing is stored.

## Calendars on this iPhone (E3)

`PocketCalendars` is reached from the You sheet and from Today's "No calendars chosen" row.
Before access it says why Porchlight wants the calendars and only then shows the system prompt; when access is off it explains how to turn it on and links to Settings.
With access, each of the phone's calendars has a check (shown on Today or not) and a choice of Household, Busy only or Just me (`CalendarSharing`).
Household and Busy only are the calendar's existing visibility; Just me is a new device-local flag, `calendarSource.isPersonal`, added by the migration "calendar v2: just me" after the sync rebuild.
Calendar ids and these choices stay on the device: `calendarSource` is device-local.
Today every calendar is read only on the device that has it, so Just me changes nothing visible yet; sharing a calendar-to-person mapping between devices is a later sync task, and nothing here builds it.

## You (E1)

The sheet shows my avatar and name, the household and this phone's role, then four rows: the household (its name and people), this phone (its role), "This iPhone is James", which opens "Which one is you?" to change it, and Calendars.
Nothing else is listed until it works.

## Accessibility

All phone text uses `phoneFont`, so it follows Dynamic Type to the largest accessibility size.
At accessibility sizes, rows with a trailing action, banners and the toast stack instead of squeezing, the slot grid becomes one column, and buttons keep their full width and wrap their label.
Every control is at least 44 pt; small pills keep their look and get a 44 pt tap area.
Buttons read their result: "Log Yo-Yo's evening walk", "Check off Fix the leaky faucet", "Check off Vacuum the living room as yours".

## Tests

- Unit: `PocketTodayTests` (which slot one tap logs, card order, freshness, catch-up, my chores and the shared ones, stars, the words), `PocketWritesTests` (the already-logged path, joining and its undo, undo of a log, chores that are already done), `DeviceSettingsTests` (role defaults, stored role, "me" per household, forgetting) and `CareLogFieldsTests`.
- Unit, everyday screens: `PocketTabsTests` (grocery sections, dinners to groceries, Glow for me and who earned a reward, the next 7 days, Pitch in's week, the calendar choices).
- UI: `PhoneTests` and `PhoneTabsTests`, which run only on an iPhone; `scripts/test.sh --phone --ui-only` runs them on the iOS 17.5 iPhone 15 simulator, and the iPad run skips them.
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
- **Empty households.** Without companions or chores, Today shows one calm line saying they appear once set up on the shared screen; it offers no setup actions, since the editors aren't on the phone yet.
- **"This iPhone".** Sentences name the device with `UIDevice.current.model`; that only picks words and never decides behavior.
- **Sample time.** The sample household's care depends on the hour. `-debugCompanionNow` already pinned "now" for care screens; the phone's writes and the sample's chore check-offs now use it too, so the UI tests pin 5:20 pm and always find the evening walk and dinner open, whatever the hour they run. Today's sample check-offs happen through the morning (breakfast at 7:40, and so on), or at "now" when that is earlier.
- **More sample companions.** `-sampleCompanions 2|3` adds Miso the cat and a fiddle fig due for water today, so the grid of two has something to show.
- **The week page is one column.** The wall's hero, podium and tiles don't fit side by side; the phone keeps the hero line and the mood, draws the podium as bars (crown on the leader) and leaves out the stat tiles, whose numbers are in the hero line. Paw trail rings are read-only; the diary's missed rows are the way to catch up from the week.
- **Pitch in segments.** The atlas's Yours, Open and Everyone. "Open" is today's shared chores not done yet. Someone else's chore can't be checked off from my phone, because checking off an owned chore credits its owner. "took it Friday" in the atlas is a claim, which the data doesn't have, so it isn't shown.
- **One chore editor.** The wall's `ChoreEditor` adapts to a compact width instead of a second phone editor; its fonts are the wall's fixed sizes, so it doesn't grow with Dynamic Type yet.
- **A dinner's needs are typed.** Dinners have no ingredients in the data, so "Needs: tortillas, limes" is something you type for a dinner; each item goes on the groceries in its aisle, credited to you.
- **List rows check with a plain box.** Like the wall's list rows, not the accent box chores use.
- **Glow without Lately.** The phone shows my week, saving for and everyone; the feed and the porch sparks stay on the wall.
- **Cash-in words.** The sheet says who earned the stars and that Glow starts saving again; it doesn't promise that the shared screen celebrates, since the wall-side celebration for a cash-in from another device is a later task.
- **"Just me" is stored, not yet enforced.** Nothing leaves the phone today, so it can't change what others see; the choice is kept so it's right when calendar mappings sync.

## Fixed on the wall along the way

Nothing on the wall looked broken while working here.
Wall code changed only to share it: the care form's logic and the time pill's day math, `Color.wash` resolving its colors explicitly, the companion page's week line, the grocery sections, `HomeStore.cashIn` returning the cash-in, and the chore editor's compact layout (its regular layout is unchanged).
The wall's UI tests cover all of them.

Sample and reset launches (`-sampleHousehold`, `-resetData`) now start from an empty sandbox folder.
A simulator is shared by every checkout of the app, and the iPad suite failed almost entirely when another branch's build had migrated the sandbox database to a schema this build doesn't know ("table companion has no column named photoFile").
Real data is never in the sandbox, so nothing else changes.
