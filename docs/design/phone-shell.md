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
"More…" opens `PocketCareSheet`, and so does catching up: Today's banner and a missed row in a companion's week open it for that slot and day (`PocketCareSheet.Request.catchUp`), at the slot's usual time, with you picked as who went, so Save works at once.
There is one care sheet on the phone, and it asks what the wall's does: when, how long, who, business, vibe and a note.

Never confidently out of date (rule 10): one tap and catch-up call `AppDatabase.logCare(routineId:slot:on:_:now:)`, which reads the slot again inside the write.
The care sheet writes before it closes (`PocketLogging.save`): a log the rules turn down keeps the sheet open with the reason, and one that saves closes it with its toast.
No care write fails quietly: Undo, "I went too" and its Undo, a fix and a removal each say "That didn't save" when they are turned down, on the wall a removal keeps its sheet open with the reason, and the wall's diary says when a log couldn't be deleted.
If someone already logged it, nothing is added; the toast says who and when ("Mia walked Yo-Yo at 5:40pm") and offers "I went too", which adds me to their log (with its own Undo).
Chores do the same with `AppDatabase.completeChore`: a chore someone just checked off is never unchecked by a stale tap, and the toast says who did it.

The wall's care form logic moved out of its view into `CareLogFields` and `CareLogDay`, and the time pill's day math into `LogTimeDay`, so the wall's log sheet and the phone's care sheet share one implementation.

### A log that names nobody

A log always has someone on it: the rules refuse one with nobody (`CareRules.validatedNote`), and every sheet keeps Save off until someone is picked.
One can still show up with nobody this household knows, when its people haven't arrived from the device that wrote it, or name someone the household doesn't have.
It is never hidden: Today's tile, the week's diary, the wall's diary and Paw trail say "Who? Tap to say" in place of a name, and tapping it opens the fix with nobody picked, so it saves only once someone is (`CompanionSnapshot.namesNobody`, `knownPeople(of:)`).
The wall's form behaves exactly as before.

### Fixing a log (B2, `b2fix`)

The phone fixes a log as the wall does, so nothing logged is stuck as it was saved.
A done slot tile on Today's companion card ("Morning 9:39am") and every row of the week page's diary open `PocketCareSheet` on that log.
The sheet in this mode is the wall's edit form at phone size: "Edit walk" (by the routine's kind: "Edit feed", "Edit water"), "Fix who, when or how it went", every field filled in as logged, "Save changes", and "Remove", which asks once more with "Remove walk" and "Keep it".
The words live in `CareLogWording` and the log's day in `CareLogDay.forSheet`, which the wall's sheet uses too, so the two can't drift.
Saving calls `CompanionStore.updateLog` and removing `deleteLog`, the wall's own writes.
A fix the rules turn down keeps the sheet open with the reason; one they accept closes the sheet at once and is written right after (`PocketLogging.saveFix`), so a busy moment never holds the sheet up, and a write turned down after all (the log removed on another device meanwhile) says "That didn't save" in a toast.
Anyone in the household can fix any log, as on the wall; a shared-screen phone shows names instead of "You".

What follows from the writes, with nothing phone-specific:

- Stars: a log earns its routine's stars once, when it is added, for each person on it. Fixing keeps them on the log; taking someone off takes theirs, adding someone gives them theirs, and removing the log takes them all back.
- Reminders and widgets watch the store, so an edit or a removal reaches them like any log: a removed log, or one moved to another day, leaves its slot open, and that slot reminds again.
- Sync sends the change like any write; the log keeps the device that first wrote it.
- Households: the write checks that everyone credited lives in the log's own household (`CareValidationError.notInHousehold`), whichever household the phone is showing, for fixes and for "I went too" as for new logs.

A slot holds one log; when two logs fall in one slot's window, the slot shows the one it was given (`CareLogic` assigns each log to the nearest free slot) and the tile opens that one, as on the wall.

### A log made for a slot fills that slot

A log made for a slot remembers it (`careLog.slot`): a tap on a slot, catching up, a widget, Siri and a reminder's action all write one.
`CareLogic.assign`, which Today, the week, the widgets, the wall and the write that checks a slot is free all use, puts such a log in its slot first, whatever time of day it was written, and places the rest by their time as before.
Before, only the time placed a log, so a slot logged late, nearer the next slot's window than its own, filled the next slot instead: a cat's breakfast logged from a widget after 1 pm showed as dinner, breakfast stayed "not logged", and dinner looked done.
A fix keeps the slot unless its new time lies in another slot's window; a log from the care sheet, or from an older build, has no slot and is placed by its time.
Every log is in the week page's diary, so any of them can be fixed from there.
There is no Undo toast for a fix or a removal, as on the wall: the removal asks first instead.

## A companion's week (B3)

Tapping a companion's card (its face and name, or the whole card when it is all set) opens `PocketCompanionWeek`.
It has everything the wall's companion page has, laid out for a phone held in one hand, in one scrolling column:

1. The hero: the face, "Yo-Yo's week", what the companion is and how old ("Toy poodle · 4 yrs"), the week in a line, and the wall's mood meter.
2. The routines, "🦮 Walk", "🥣 Feed", "💧 Water", when there is more than one. Everything below follows the one picked, and the page opens on the primary routine, the wall's.
3. The wall's four numbers (the streak, the average walk or the meals this week, slots on time, the business log or the stars) and "Log a walk" (by the routine: "Log a meal").
4. Paw trail, with the day's letter and number over each column.
5. The diary ("Walk diary", "Meal diary"), with the routine's missed slots in their place.
6. The podium ("Walker of the week", "Chef of the week"), second, first and third, the leader crowned.
7. The little milestones.

The wall's page shows only the primary routine's week; the phone shows each routine's, so meals and water have their trail, diary, numbers and podium too.
`CompanionReport` now holds a `RoutineWeek` per routine (`weeks`); the fields the wall reads (`trail`, `diary`, `weekStats` and the rest) are the first one's, so the wall's page and Today read exactly what they did.

Paw trail's dots do what the wall's do (`RoutineWeek.tap`): a logged one opens its log to fix in `PocketCareSheet`, one still open or to come today starts a new log in it, and one whose window closed without a log (earlier this week, or today's late one, as Today's banner offers) opens it to catch up on that slot, for its own day.
Every catch-up, from the trail or the diary, goes through one function, `logMissed`, which opens the care sheet for that slot, so the log fills the slot tapped however late it is made (`CareLogic.slot`).
A slot that was never owed (one that closed before the companion was added) is a plain dot that asks nothing, on the wall too; the diary never listed it either.
A logged diary row opens it to fix (above).

### One implementation for the wall and the phone

The pieces of the page are shared, in `CompanionWeek.swift` (pure, `CompanionWeekTests`) and `CompanionWeekViews.swift`:

- `RoutineWeek`: a routine's trail, numbers (`tiles`), streak, standings, diary rows (`DiaryRow`), missed slots and milestones, the week in a line (`summary`), what a trail slot does (`tap`) and what VoiceOver reads for it (`trailLabel`).
- `CareLogic.podium` and `leader`: the podium's order and its crown.
- `CompanionWeekWords`: every heading and sentence ("Paw trail" and "who walked, each slot", "Walk diary" and "captions: Cheeky", "Feed Yo-Yo · Dinner wasn't logged" and "Fri · usually 5-7pm", "No walks yet this week. The podium is wide open.").
- `CompanionReport.aboutLine` and `moodText`.
- The views: `MoodMeter`, `StatTileGrid`, `PawTrailGrid` and `PodiumView`. Their type is `sharedFont`, so they keep the wall's fixed sizes over the wall and grow with Dynamic Type on a phone; the trail takes the phone's metrics (30 pt dots, columns sharing the width) and shows a routine's emoji where the wall shows a paw.

The wall's page is built from the same pieces and looks as it did.
Wording comes from the routine's kind, so a plant gets "who watered" and "Gardener of the week"; a kind without a verb of its own (litter, meds, cleaning) says "who did it", as the wall did for anything but a walk.

A first week shows "The first week together", "Waiting for first walk" under the mood meter, and a trail of open slots, never a zero.

At the largest text sizes the routines go one under another, the numbers one per row, the hero's face above its words, a missed row's "Log it" under it, and the podium becomes bars, which keep every name whole.
The trail's letters stop growing at the extra-large size, like the Food tab's week; every slot in it is also a row in the diary, whose words grow all the way.

## Pitch in (B4)

"See all" on "Yours today" (or on its banner once everything is done) opens `PocketPitchIn`.
The header counts this week's chore days, done of all, from the wall's week marks.
A segmented control picks Yours (today's, then what I did earlier this week), Open (shared chores nobody has done today) or Everyone (every person's column, kids included, then Anyone).
Someone else's chore is shown, not checkable: it is theirs to check off on their phone or the wall.
"+ Add a chore" opens the wall's `ChoreEditor` in a phone sheet (`PhoneEditorSheet`), with its repeat picker and start day; the editor now stacks its time hints and buttons at a compact width, and starts a new chore as mine.

## Food (B5)

The Food tab (`PocketFoodScreen`) is the wall's week of plates at phone size (`b5week`).
Its header says the week and how many meals it holds ("Nov 10 to 16 · 20 meals"), and the week is the wall's: the seven days ending today.
The grid has a column per day and a row per meal; a logged meal is its cover's thumbnail (a "+1" when the slot has more dishes), and an empty slot up to today is a dashed square that opens the camera for that meal.
"On this day" follows, as on the wall, then the diary: the week's days newest first, each meal with its cover, its name in the diary's hand, where it came from, who ate it ("You and Mia") and who added it ("added by you", from the device stamped on the row).
"Snap a meal" stays at the bottom of the tab, above the tab bar.
When the household hasn't turned the diary on, the tab says so and turns it on (rule 6).

Snapping (`PocketSnap`) opens the camera first (`b5cam`): a polaroid whose photo is the live camera, captioned with the meal it is for ("Sunday dinner", guessed from the time), the shutter, and "From Photos" and "No photo" as the other ways in.
A shot or a pick goes straight to the details (`b5details`): the new polaroid, what it was, when and which meal, where it came from (and the restaurant, with the wall's `RestaurantField`), who ate it and "Would eat again?", then "Save to Sunday dinner".
Who ate starts as me (rule 1).
Under the polaroid, the new meal's photos sit in the wall's own photo row (`MealPhotoRow`, "Photos · 2 of 6"): tap one for Make cover or Reframe, × to take it off, and the dashed + goes back to the camera for another, up to the wall's limit.
Photos are made by `MealPhotoImaging.prepare` off the main actor and held in memory until Save; the meal is written by `FoodStore.addMeal`, which stamps this device, so the rows are the wall's: one 2048 px whole shot and a 360 px square thumbnail per photo.
Back on the tab, the toast says where it went ("Saved to Sunday dinner · Pho Huynh · you and Mia") with Open, and the new plate is ringed for a moment (`b5saved`).

The camera says what it is for before iOS asks ("Allow camera"), and with access off it says how to turn it on, with Open Settings; Photos and saving without a photo work either way.
`-cameraAccess notDetermined|denied|allowed` pretends a state, and `-debugCamera sample` stands a generated dish in for the camera, which the simulator doesn't have; its shots go through `MealPhotoImaging.prepare` like a real one.

A meal's page (`PocketMealDetail`, `b5entry`) is the big polaroid, swiped for its other photos and tapped for the whole shot, then where it came from, the verdict with who ate and who added it, the day's handwritten page when anyone wrote on it, and the slot's other dishes.
Edit opens the same fields in a sheet, with the same photo row as the wall's editor: Make cover and Reframe from a tap on a photo, × to take one off, and + to take or pick more, which attach on Save; Add photo on the page takes one or picks from Photos and adds it at once; Remove asks first, since a meal's photos can't come back.

### Photos, the same on the wall and the phone

The photo row (`MealPhotoRow`), the reframe screen (`ReframeSheet`) and the add tile (`AddPhotoTile`) are one implementation for both shells, in `FoodPhotoViews.swift`; what the row does to the photos is `MealPhotoOrder`, unit-tested, and adding them is `MealPhotoAdding`.
In a compact width they lay out for the phone: the squares, the cover tag and the hint grow with Dynamic Type (the squares up to half again), the × is a 44-point target, Reframe opens as a full-height sheet whose window is the screen's width, with the wall's drag, pinch, zoom row and thirds grid, and the add tile's "Take a photo" opens the phone's camera step.
Over the wall nothing changed: the same sizes, the reframe sheet over the wall and the wall's camera sheet.
The reframe sheet can't be swiped away, so a drag on the photo never closes it; Cancel and Done do.
All three go through `FoodStore` (`updateMeal`, `addPhotos`, `deleteMeal`), as on the wall.

Lists never decode a whole shot: the grid, the diary and "On this day" ask `PhotoImages` for thumbnails, and only a meal's own page asks for the whole shot.
While that loads, or before it has arrived by sync (thumbnails can arrive first), the polaroid shows the thumbnail, which is already decoded; this is `MealIllustration`'s, so the wall's big polaroids do the same.
Measured on the iPhone 15 simulator with every meal of the sample week photographed (`-samplePhotoMeals`, 20 meals, two photos each): the app's footprint is 35 MB on Today, 46 MB on the Food tab and 58 MB on a meal's page with two whole shots.

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
Once it exists, shared screens can show calendars set to Household in full and Busy only as "Busy", and never one set to Just me.
The page itself only says what the choices mean on this phone: Household and Just me show events in full, Busy only shows them as "Busy".

## Reminders (C1) and notification choices (E2)

Reminders are local notifications, planned and scheduled on the phone from the data it already has; there is no server and no push.
`ReminderPlanner` is pure: from the household's care and chores, "me", this phone's choices and the time, it returns every notification that should be pending, with stable ids (`porchlight.reminder.care.<routine>-<slot>-<day>`, `porchlight.reminder.chores.<day>`).
`ReminderScheduler` makes iOS's pending list match: it removes what is no longer planned, adds what is new, and leaves the rest, comparing a fingerprint of each reminder's time and words.
It also takes reminders that already showed off the Lock Screen once their slot is done.
It runs when the app comes to the front, when care or chores change in the database (a log here now, from another device once sync delivers it), and when a choice changes, coalesced into one run a second after the last change (`keepsRemindersScheduled`).
Only a personal device reminds: a shared screen never asks for permission and never schedules, and the planner returns nothing for someone removed from the household.
It plans the next 7 days and keeps the nearest 64, iOS's limit.

A care reminder has three actions, as in `c1open`: the log action ("I walked Yo-Yo"), "Remind me in an hour" and "Someone else is on it".
Logging goes through `AppDatabase.logCare(routineId:slot:on:)`, the same check-before-log write as one tap on Today, so a reminder acted on late never doubles a log; it then posts a short confirmation ("Logged: evening walk", or "Mia walked Yo-Yo at 5:40pm").
Actions work with the app closed: when iOS launches the app in the background, it opens its data the usual way (the restore check, then the sync engine), and `ReminderNotifications` uses that same instance (`AppDatabase.launched`), never a second connection.
If that launch finds a restored copy and sync waits for someone to decide, the restore check only marks the decision as pending; it never blocks opening.
So the action still logs on this phone, stamped with this device, and nothing is sent while the decision waits.
That log shares the restored copy's fate: "Use what is in iCloud" replaces the copy, log included, and keeping the copy without sync keeps it on this phone only.

The Notifications page under You says what reminders are before iOS asks, offers Open Settings when they are turned off, and lists each routine's slots ("Yo-Yo · evening walk") with Off, When it opens or Only if missed, and "Your chores" on or off.
The choices, snoozes and hand-offs are device-local (`ReminderSettings`, in `UserDefaults`), never synced.

Delivery itself can't be asserted reliably in the UI suite, so `PhoneRemindersTests.testDeliveryByHand` runs only when asked (see the README).
It was run on the iOS 17.5 iPhone 15 simulator: with real permission, a reminder scheduled 20 seconds out (`-debugReminderIn`) was delivered with the app closed, a long press showed its three actions, and "I fed Yo-Yo" launched the app in the background, logged dinner and posted "Logged: dinner".
Not verified: delivery on a real iPhone, "Remind me in an hour" and "Someone else is on it" from a delivered notification (the planner side of both is unit-tested), and timing across a time-zone change or a reboot.
A DEBUG sample launch marks its reminders, so an action handled with the app launched without arguments reaches the sample data, not the real household.

## You (E1)

The sheet shows my avatar and name, the household and this phone's role, then the household (which opens its setup), iCloud storage (which says where it lives), Invite someone, the people, this phone, "This iPhone is James", Calendars, Notifications, the sync switch, and leaving.
A tab can open it on one of its pages (`OpenYouAction` takes a page), which is how an empty tab offers to set itself up.

## Starting a household on a phone (A2)

A phone with no household shows the welcome's two doors (`a2welcome`): "Start a household" and "Join one", which says how joining works (an invite, or the code on a shared screen).
A fresh install signed in to iCloud first looks for a household there, as the wall does (`HouseholdSearchView`); while it looks, the welcome says so and "Start a household" waits the same four seconds the wall's "Start fresh instead" does, then ends the search when tapped.

Starting takes four steps (`PocketSetupView`): you and the household (its name, your name, your color), who else lives here, anyone to look after, and ready.
The household is created after "Who else lives here" through `HouseholdSetup`, the model the wall's first run now edits too, so both make the household with the same call (`AppModel.createHousehold`) and end setup with the same one (`AppModel.finishSetup`, which also makes the food diary, on, unless the wall's journals step turned it off).
This phone is personal and belongs to the first person, set with the household, so it never asks "Which one is you?".
A companion is saved by `CompanionStore.save` with its species' preset routines, as the wall's companion step saves it.
"Ready" says where the household lives in `HouseholdHome`'s words, offers to invite each person (or says why it can't yet), and mentions a spare iPad as a shared screen.
A household whose setup was interrupted (the app quit after the household was made) opens again at "Anyone to look after".

## Setting up the household from the phone (F1, F2)

You › Household (`PocketHouseholdHub`, `f1hub`) holds the household's name, its people (with + Add), companions, chores, rewards, lists, and the food diary's switch and meals.
Each pushes a page inside the You sheet rather than stacking sheets on it.
A person's page (`f2person`) changes their name and color, shows their phone (with Remove for the owner, or an invite if they have none), and archives them; archiving keeps their history and is never offered for yourself or the last person.
Chores and rewards open the wall's own `ChoreEditor` and `RewardEditor` as pages (`PocketEditorPage`, which closes them by going back).
A companion opens the wall's `CompanionEditSheet`, which now lays itself out in one column at a compact width, on both devices: the kinds as a grid of four, then name, look, routines, caption personality and details, without the preview; its routine editor becomes a system sheet in one column.
Lists can be added (grocery or to-do) and deleted, after asking.

## Leaving, and removing someone (A6)

The last row in You is "Leave The Lake House".
A member gets `a6leave`: it goes from this phone, their reminders for it stop, and what they logged stays with the household.
Leaving goes through `HouseholdSharing.leave`, which takes this iCloud user off the share; the engine then removes the household's rows from this phone, as it does when the owner removes someone.
`HouseholdSharingModel.leave` forgets the household first (as the device's other removals do), so its going isn't shown as "You're no longer in …".
If leaving fails (offline), nothing changes and the sheet says so.
The owner gets `a6owner`: the household is in their iCloud, so leaving would delete it for everyone; "Manage members" opens Household, where a joined person's page offers "Remove Mia's iPhone" with the wall's own words (`RemoveDevicesWords`, shared with the wall's sheet).

## Storage (E4)

You › iCloud storage (`PocketStoragePage`, `e4storage`) says where the household lives (`HouseholdHome`), then a meter and a line of what it takes up: photos (meal photos' whole shots and thumbnails, and companion photos, from their rows' byte counts), Pencil pages (the drawings' lengths), and everything else (what the database file holds in use, less those).
Every number is summed from this phone's rows (`AppDatabase.storage`); every device has every row, so every device sees the same sums.
It says whose iCloud it counts against, how much photo was added in the last 30 days, and "Your photos here", the meal photos added from this person's devices.
When the owner's iCloud is full, a banner says sync is paused and nothing is lost; the owner is told where in Settings to free space or change plan, and a member that it sends once the owner does.

## Accessibility

All phone text uses `phoneFont`, so it follows Dynamic Type to the largest accessibility size.
At accessibility sizes, rows with a trailing action, banners and the toast stack instead of squeezing, the slot grid becomes one column, and buttons keep their full width and wrap their label.
Every control is at least 44 pt; small pills keep their look and get a 44 pt tap area.
Buttons read their result: "Log Yo-Yo's evening walk", "Check off Fix the leaky faucet", "Check off Vacuum the living room as yours".
Rows that put two pieces of text side by side (a reward and its count, a person's bar and number, a chore and its stars, an event and its time, a dinner and its day) become columns at accessibility sizes (`AdaptiveRow`, `PersonBarRow`, decided by `dynamicTypeSize.isAccessibilitySize`).
Star counts always agree in number ("+1 star", "2 stars") through `StarWords`.

## Tests

- Unit: `PocketTodayTests` (which slot one tap logs, card order, freshness, catch-up, my chores and the shared ones, stars, the words), `PocketWritesTests` (the already-logged path, joining and its undo, undo of a log, catching up from the care sheet, a log the rules turn down keeping the sheet open, a log that names nobody, chores that are already done), `DeviceSettingsTests` (role defaults, stored role, "me" per household, forgetting) and `CareLogFieldsTests` (including fixing a log: its day, its fields and the shared words).
- Unit, fixing a log: `TwoHouseholdsTests` (a fix in the log's own household while the other shows, never crediting the other household, stars on fixing and removing, a removed or moved log reminding again).
- UI, fixing a log: `PhoneTabsTests.testFixingAWalkFromToday`, `testFixingAWalkFromTheWeek`, `testFixingAWalkOnASharedScreen` and `testFixingAWalkLooks` (night look and the largest text), mirroring the wall's `LoggedEntryTests`.
- Unit, a companion's week: `CompanionWeekTests` (a week per routine with the primary's as the wall's, what a trail slot does and reads, the numbers, the podium and the words).
- UI, a companion's week: `PhoneWeekTests` (the trail's dots, a meal logged from the trail showing in the trail and the diary, water, the night look and the largest text with walks, meals and water, and a first week). `-sampleWater YES` gives Yo-Yo a water bowl and `-sampleCompanions 4` adds Pip, a rabbit added just now with nothing logged.
- Unit, everyday screens: `PocketTabsTests` (grocery sections, dinners to groceries, Glow for me and who earned a reward, the next 7 days, Pitch in's week, the calendar choices).
- Unit, reminders: `ReminderPlannerTests` (only chosen slots, done slots removed, if missed, snooze and hand-off, archived "me", chores the evening before, the 64 cap, pruning).
- Unit, households: `HouseholdSetupTests` (a household started on a phone is the one the wall's first run makes, drafts, an invalid name, a member leaving on the fake and the owner who can't) and `HouseholdStorageTests` (the sums come from the rows).
- UI: `PhoneTests`, `PhoneTabsTests`, `PhoneWeekTests`, `PhoneCatchUpTests` (catching up from Today's banner and from the week, in the care sheet), `PhoneHouseholdTests`, `PhoneRemindersTests`, `PhoneFoodTests` and `PhoneSetupTests` (A2 from a fresh install to Today, every tab empty, setup edits, a companion in the wall's editor, leaving, removing someone, storage), which run only on an iPhone; `scripts/test.sh --phone --ui-only` runs them on the iOS 17.5 iPhone 15 simulator, and the iPad run skips them.
  Each test attaches a screenshot of every screen it visits.

## Judgment calls

Where the atlas was silent, or didn't fit the code:

- **Which slot one tap logs.** The atlas shows the button while a window is open. The phone uses the wall's own rule for where a log belongs (`CareLogic.windowIndex`): the button logs the slot a log made now would fill, as long as that slot is still waiting and its window hasn't closed. So at 2 pm it logs the coming evening walk (as the wall would), at 11 am, with the morning done, there is no button, and a slot whose window closed is caught up on at its real time instead of being logged "now".
- **Rule 10 checks the slot, not the time.** The write re-reads the slot it was asked to fill. The full care sheet (More…) is a deliberate, detailed log and adds a log like the wall's sheet does, so two people can still each log a walk ("both entries kept").
- **"I'll do it" checks the chore off.** There is no way to claim a chore in the data, and adding one is a schema change best made with B4. Taking a shared chore checks it off, credited to me, with Undo, and the button says "I did it" so it doesn't promise a claim.
- **Done rows stay where they are.** Chores keep the board's order and a done row stays, crossed out, so nothing jumps under your thumb. A done row is not a button; Undo on the toast takes a check-off back, and fixing older ones stays on the wall for now.
- **A finished card.** A companion whose day is done shows "✓ Logged" for 15 minutes after its last log (the `b2tap` frame), then folds to "Yo-Yo is all set" (`b1clear`). The time comes from the data, so it survives a relaunch.
- **One missed slot at a time, and only once.** The banner shows the newest missed slot, today's or earlier in the week the wall lets you catch up on. It has a "Not now" button; a dismissed slot is remembered on the device and never shown again.
- **Catching up is the care sheet.** It used to be a sheet of its own that asked only the time and credited me; James wanted one way to log a walk everywhere. It opens prefilled for the slot and its usual time, with me picked, so it is still one tap to save.
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
- **The week page is one column, with the wall's content.** The wall's hero, trail, diary, podium and milestones sit side by side; the phone stacks them, with the stat tiles and the log button in their own card under the routines, since they follow the routine picked.
- **A week per routine, picked at the top.** The wall's page is the primary routine's week. Stacking every routine's trail, diary and podium would make a page several screens long per companion, so the phone shows one routine's at a time, opening on the wall's. The hero (the face, the mood, the week in a line) stays the companion's, as on the wall.
- **Missed slots in their own routine's diary.** The wall's diary lists every routine's missed slots under "Walk diary"; on the phone each routine's diary lists its own, so a missed dinner is under "Meal diary", beside the dinners that were logged. Today's banner still offers the newest missed slot of any routine.
- **Today's slots aren't repeated.** The wall's hero has today's slot tiles; on the phone they are on Today's card, and the trail's last column is today, its dots tappable the same way.
- **No long-press delete.** The wall's diary rows have "Delete this log" on a long press, which removes at once; the phone removes from the care sheet, which asks first ("Remove walk", "Keep it"), since a removal has no Undo.
- **The trail's tap areas.** Seven days across a phone leaves about 43 pt per column, a little under 44; each dot's tap area is 44 pt tall and the column's full width, and every dot is also a row in the diary.
- **Pitch in segments.** The atlas's Yours, Open and Everyone. "Open" is today's shared chores not done yet. Someone else's chore can't be checked off from my phone, because checking off an owned chore credits its owner. "took it Friday" in the atlas is a claim, which the data doesn't have, so it isn't shown.
- **One chore editor.** The wall's `ChoreEditor` adapts to a compact width instead of a second phone editor; its fonts are the wall's fixed sizes, so it doesn't grow with Dynamic Type yet.
- **A dinner's needs are typed.** Dinners have no ingredients in the data, so "Needs: tortillas, limes" is something you type for a dinner; each item goes on the groceries in its aisle, credited to you.
- **List rows check with a plain box.** Like the wall's list rows, not the accent box chores use.
- **Glow without Lately.** The phone shows my week, saving for and everyone; the feed and the porch sparks stay on the wall.
- **Cash-in words.** The sheet names the reward's price and who earned it; it doesn't promise that the shared screen celebrates, since the wall-side celebration for a cash-in from another device is a later task.
- **What a cash-in spends.** The wall's cash-in records every star of the round, and the round can earn more than the price (21 for a reward of 20, the bar showing "20 of 20"). The phone keeps that rule and says it plainly: the celebration shows the price ("20 stars from you"), and the sheet says when the extra goes with it ("It costs 20 stars, and you earned 21, so the 1 extra star goes with it. Then it starts again from zero.").
- **The celebration covers the page.** It is opaque paper in both looks, so nothing of Glow is legible behind the title; the tab bar stays.
- **Toasts wait for sheets.** A toast from a sheet (the care sheet, catch-up, a dinner's needs) is held until the sheet has finished closing (`ToastCenter.showAfterSheet`, flushed by the sheet's `onDismiss`), and the cash-in celebration waits the same way; shown at once, they sat behind the closing sheet and could be gone before anyone saw them.
- **Which routines are "yours".** Care routines belong to the household, not to a person, so the phone can't tell which are yours; every slot starts Off and you turn on the ones you look after. My own chores start On, since they are mine in the data. ("Mia's this week" in `e2notif` would need a rota, which the data doesn't have.)
- **When a slot reminds.** "When it opens" fires at the window's start and "Only if missed" at its end, each only if nobody has logged it by then. A slot set to remind after its window has already opened today waits for tomorrow rather than firing late. An all-day slot reminds at 9 am, or at 7 pm if missed.
- **Chores the evening before, at 7 pm**, one reminder for all of a day's chores, and never for chores that repeat every day: an every-evening buzz is noise (rule 3).
- **No quiet hours.** The atlas has none; reminders only come at the household's own routine times and 7 pm for chores, so there is nothing to silence.
- **Snooze and hand-off are per day.** "Remind me in an hour" moves that day's reminder; "Someone else is on it" drops it for that day. Both are kept on the phone and pruned after the day.
- **No "When someone asks you".** That is C2, later; the page doesn't list it.
- **The async notification delegate methods aren't used.** UIKit asserts when the async form of `didReceive` completes off the main thread, which it does when iOS launched the app for an action; the completion-handler forms call back on the main actor.
- **Notification settings link.** Open Settings goes to Porchlight's notification settings (`openNotificationSettingsURLString`).
- **Food's week is the wall's.** The atlas heads the grid "Nov 9 to 15", a Monday-to-Sunday week; the wall shows the seven days ending today, so today is always the last column and the week is always full. The phone follows the wall, so both screens show the same plates.
- **A diary under the grid.** `b5week` shows only the grid, whose cells are too small for names; who ate a meal and who added it, and its name in the diary's hand, are in a day-by-day list under it, the newest day first. Only days with meals are listed.
- **No "This week" stats card.** The wall's card (the split, the theme, the streak) isn't in `b5week`, so the phone leaves it out; the header's meal count is the week's summary. "On this day" is in the atlas and is shown.
- **"Snap a meal" floats.** The atlas puts it under "On this day"; with the diary below, it would scroll away, so it sits at the bottom of the tab above the tab bar.
- **No Food on Today.** The atlas's Today frames (`b1due` and the rest) have no meals, so Today has no entry point.
- **Nearby restaurants aren't first.** `b5details` lists restaurants "40 ft" away, which needs the phone's location, a permission the app doesn't ask for anywhere else. The phone uses the wall's restaurant search (Apple Maps around home, and places eaten at before); nearby-first is a later improvement.
- **The wall's words.** The verdict is "Would eat again?" with the wall's four faces (😐 🙂 😋 🤩), and where it came from is the wall's four (home-cooked, delivery, dine out, company), not the atlas's 😬 and its home and delivery pills.
- **No writing on the day's page.** Handwriting is the wall's (Apple Pencil on paper); a meal's page on the phone shows the day's page, read-only, when anyone wrote on it.
- **Remove asks first.** Logging never asks (rule 2), but a removed meal takes its photos with it and Undo couldn't bring them back, so Remove confirms, as on the wall.
- **The back camera.** The wall's viewfinder starts on the front camera, which faces the room; a phone points at the plate, so it starts on the back one, with no switch.
- **One shot, then the details.** The wall's camera stays live for more angles; the phone goes to the details after each shot, which is where "Another photo" brings it back for more.
- **Small grid cells.** Seven days across a phone leaves cells of about 36 pt, under the 44 pt target (rule 8). Every meal in them is also a full-width row in the diary below, so nothing is reachable only through a small cell.
- **The week's grid grows only so far.** Its day letters and meal names stop growing at the extra-large text size; at accessibility sizes they squeezed the plates to slivers. Every meal in the grid is also a row in the diary, whose words grow all the way.
- **The wall's restaurant field and time pill keep their fixed sizes.** They are shared with the wall and don't grow with Dynamic Type; everything else on the Food tab does.
- **Starting waits for the iCloud search.** The atlas's welcome has no search; a fresh phone signed in to the family's iCloud would otherwise make a second household before the first one arrived. The wall already waits, so the phone waits the same four seconds, saying why.
- **Who else lives here doesn't ask about phones.** `a2people` says "Has an iPhone" or "No phone needed" per person; nothing in the data records that before an invite, so the step only names people, and "Ready" offers to invite each one.
- **Companions on A2 are one, with presets.** The step adds one pet or plant with its species' routines (the wall's presets); more, and changing routines, are in Household. The atlas's "Baby" isn't a species in the data, so the kinds are the wall's.
- **iCloud on the phone isn't a question.** Sync is on by default on a fresh install, as on the wall; "Ready" says where the household lives in `HouseholdHome`'s words, including "on this iPhone until you sign in" when signed out, and the sync switch stays in You.
- **Pages, not sheets, for Household's editors.** The atlas draws them as sheets over Household; inside the You sheet, a sheet on a sheet is cramped and the sharing sheet showed that stacking them misbehaves, so each editor is a page with the way back in the corner. The routine editor, a third level, is a system sheet.
- **The companion editor has no preview on a phone.** At the wall's size the live preview sits beside the form; on a phone it would push the routines a screen down, so it's left out at a compact width.
- **No photo frame settings on the phone.** What the frame shows, its photos and its night hours are the wall's own device settings, not the household's, so there's nothing for a phone to set.
- **Archived people aren't listed.** Household lists the people who live here; bringing an archived person back stays on the wall's Settings for now.
- **The owner can't delete the household from the phone.** `a6owner` shows "Delete The Lake House for everyone…"; deleting every member's data can't be proven without devices and isn't needed for the M4 gate, so the phone explains why the owner can't leave and points to removing someone instead.
- **Leaving needs to be online.** Leaving is a change to the share in iCloud; offline, the sheet says to try again rather than hiding the household and leaving the share in place.
- **No "Keep originals on this iPhone".** `e4storage` offers it, but there is no original to keep: the stored 2048 px photo is the photo (docs/design/sync-icloud.md), and saving originals to Photos at capture time isn't built. The owner's "shrink older photos" (D2) isn't built either.
- **"Everything else" is measured, not estimated.** It is the database's pages in use less the photos and pages counted, on this phone, so it includes indexes and any other household this phone holds.
- **Empty tabs offer setup.** Right after A2, Today says there's nothing to do yet and opens Household; Glow says stars come from chores and opens Chores (or Rewards once there are chores); Food's empty diary and Lists' default lists already read as intended.
- **"Just me" is stored, not yet enforced.** Nothing leaves the phone today, so it can't change what others see; the choice is kept so it's right when calendar mappings sync.

## Fixed on the wall along the way

Nothing on the wall looked broken while working here.
The paper under the status bar was never painted: `paperUnderStatusBar` read the top inset from a reader that ignored the top safe area, where it is 0, so scrolled text showed under the clock on every tab (it was plainest on Food and Lists, whose content scrolls furthest). It now measures where the view starts on screen and paints paper above it, and `PhoneTabsTests.testPaperUnderTheStatusBar` and the `PhoneFoodTests` status bar tests scroll each tab and Food's pages, in light, dark and the largest text, and check that the band under the Dynamic Island is one flat color.
Settings › Photo frame sometimes kept the photo list and "Add photos" under "Porch view" after switching to it (PhotoFrameTests failed 2 runs in 4): the picker showed the new choice while the rows read an older `@AppStorage` value. The settings now hold the choice in `@State` and write it through to the same UserDefaults key, and the test passed 6 runs in 6.
A big polaroid used to show its bare tablecloth while the whole shot loaded; it now shows the photo's thumbnail until then, on the wall too.
A companion added in the evening was told its dinner "wasn't logged" minutes after it arrived, on the wall's companion page and the phone's Today banner: the routine starts that day, and every window that had already closed counted as missed. `CareCatchUp.isOwed` now leaves out slots on a routine's first day whose window closed before the companion was added.
For M4 the wall's first run now edits `HouseholdSetup` instead of its own fields, `AppModel.finishSetup` also makes the food diary, the wall's companion and routine editors lay themselves out for a compact width, and the remove sheet's words moved to `RemoveDevicesWords`; on the wall each looks and behaves as before.
The wall's companion page is now built from the pieces it shares with the phone's week (`CompanionWeek.swift`, `CompanionWeekViews.swift`) and looks as before, with two small changes: Paw trail says what the routine's kind did ("who fed, each slot" for a cat whose first routine is feeding, where it said "who did it"; a walk still says "who walked"), and a slot that was never owed (it closed before the companion was added) is a plain dot instead of a missed one that opened the catch-up.
Wall code changed only to share it: "On this day"'s sentence (`FoodMemoryWords`), the care form's logic and the time pill's day math, `Color.wash` resolving its colors explicitly, the companion page's week line, the grocery sections, `HomeStore.cashIn` returning the cash-in, and the chore editor's compact layout (its regular layout is unchanged).
The wall's UI tests cover all of them.

Seeding the sample household used to spend about 4 seconds (6.4 the first time, on a loaded Mac) on the sample day pages: each line of sample text is rendered at 5x, thinned pixel by pixel and traced into PencilKit strokes, which is slow in a debug build, and it ran on every sample launch before the first frame.
The traced pages are now cached in Caches (`SampleHandwriting.cachedPage`), keyed by their words, inks and tracing settings, outside the sample sandbox; the same strokes come back, so the wall's Food page looks exactly as before.
That brought seeding to about 1.8 seconds, of which 1.6 went on drawing, resizing and encoding the six sample meal photos; their stored files are cached the same way (`SamplePhoto.stored`) and copied in.
Measured on the iPhone 15 simulator with the Mac under load: seeding took 4.1 seconds a launch before (6.7 on the first), and 0.26 seconds after, once the caches are filled by a first launch.

The app icon was a solid black square, on the wall and the phone alike (its source PNG was all black since M0), and showed as such on notifications and the Home Screen.
It is now the rail's logo, a white house on the accent, drawn by `scripts/app-icon.swift` as a single 1024 px image the asset catalog makes every size from.

The phone's dinner editor (the wall's `MealEditor`) now tints the chosen emoji in the night look too; the wall, always light, is unchanged.

Sample and reset launches (`-sampleHousehold`, `-resetData`) now start from an empty sandbox folder.
A simulator is shared by every checkout of the app, and the iPad suite failed almost entirely when another branch's build had migrated the sandbox database to a schema this build doesn't know ("table companion has no column named photoFile").
Real data is never in the sandbox, so nothing else changes.
