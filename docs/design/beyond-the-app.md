# Beyond the app: widgets, Siri and Shortcuts (C3, C4)

This is the technical design for the second half of milestone M4 (see `docs/proposals/companion-ux.html`, journeys C3 and C4).
Its gate: a widget log reaches the wall without opening the app.
It builds on `phone-shell.md` (Today, one tap, reminders) and `sync-icloud.md` (the engine and `SyncController`).

## Shape

```
Widget extension ── reads ──▶ widget-summary.json (app group)
      │                               ▲
      │ Button(intent:)               │ writes when something changed
      ▼                               │
App process (woken in the background) ── AppDatabase.launched ── SyncEngine ──▶ iCloud
      ▲
Siri, Shortcuts ── App Intents ┘
```

- The database stays in the app's own container, opened once per launch (`AppDatabase.launched`).
  No other process opens it.
- Widgets only read a small summary the app writes for them into the app group container `group.com.mingyucao.porchlight`.
- Every action (a widget's button, Siri, Shortcuts) is an App Intent that runs in the app's process.
  The widget's intents conform to `LiveActivityIntent`, which iOS 17 runs in the app's process even when a widget starts them; the Siri and Shortcuts intents live in the app target, which runs them in-process too.
  So the one database instance, the restore guard and `SyncController` are all in play, and the change syncs without the app ever coming to the front.

## The summary

`WidgetSummary` is Codable JSON in `widget-summary.json`, with a `version` (1 today).
A widget that finds a version it doesn't know shows the "open Porchlight" state rather than guessing.
It holds only what the widgets draw, for today and tomorrow in the household's time zone, a few kilobytes at most and never a photo:

- when it was written, the household's name and time zone, and who "me" is (name and color);
- each companion: its name, its face's emoji, its routines with their emoji and kind, and every slot of today and tomorrow with its window (start and end minutes), its name ("evening walk") and who logged it and when, if anyone did;
- the last time the companion's main routine was done, for "time since the last walk";
- my chores for today and tomorrow, with whether each is done and its stars;
- my stars this week and the household's nearest reward goal (title, earned, target);
- the groceries list's count and its first three items.

The app writes it only on a personal device: a shared screen asks who did something, which a widget or Siri can't.
A shared screen writes nothing, starts nothing and pays nothing for widgets; its widgets say so ("Porchlight widgets are for your own phone").

### When it is rewritten

`WidgetSummaryKeeper` builds the summary from the live stores and writes it when it differs from the last one written, ignoring the time it was written.
It looks again:

- after the stores change, coalesced into one look a second after the last change: a log here, a widget or Siri log, and anything sync delivers (sync writes the database, and the stores observe it);
- when "me" changes, and at the start of each day in the household's time zone;
- when iOS gives the app background time (`BGAppRefreshTask`, asked for near the next midnight), so tomorrow becomes today even if the app wasn't opened.

After a write it asks `WidgetCenter` to reload every widget's timeline.
When nothing changed it writes nothing and reloads nothing.

### Timelines

The summary carries the windows, so a widget is right without the app running.
`WidgetTimeline.entries` plans an entry for now, for every slot window's start and end today and tomorrow, for midnight, and for every hour (so "9h since the last walk" keeps counting), at most 48.
Each entry works out what is open, done or next at its own time from the summary alone.

### Stale, missing, nobody

- No summary, or a version this widget doesn't know: "Open Porchlight once to see today here."
- No household: "Join or start a household in Porchlight."
- No "me" on this phone: "Open Porchlight and say who you are."
- A summary written more than six hours before the entry: the widget still shows it, with "As of 5:40 pm" under it, since another device may have logged meanwhile.
- An entry after the summary's last day (tomorrow): "Open Porchlight to see today."

A log button is shown only for a slot whose window is open and that the summary says nobody has logged.
The log itself still checks the slot again (rule 10), so a stale widget never doubles a walk.

### Privacy on the Lock Screen

Chore titles, grocery items and people's names are marked `privacySensitive`, so a locked phone shows them redacted when the Lock Screen hides notification previews.
Companion names, counts and times stay visible: they are what a Lock Screen glance is for.

## Intents

| Intent | Who uses it | What it does |
|---|---|---|
| `LogSlotIntent` | the companion widget's button | Logs one slot of one day for "me", by `AppDatabase.logCare(routineId:slot:on:)` |
| `CheckChoreIntent` | the Today widget's check box, Siri, Shortcuts | Checks a chore off for "me" today, by `AppDatabase.completeChore` |
| `LogCareIntent` | Siri, Shortcuts ("I walked Yo-Yo") | Picks the slot one tap on Today would log for that companion and routine, then logs it like `LogSlotIntent` |
| `AddListItemIntent` | Siri, Shortcuts ("Add oat milk to groceries") | Adds an item to a list, added by "me" |
| `WhatsNextIntent` | Siri, Shortcuts ("What's on at home today?") | Says what care is open and which of my chores are left |

- Every write is the same write path as one tap on Today: it checks before logging (rule 10), stamps the row with this device's id, and credits "me".
  When someone got there first, nothing is added and the answer says so ("Mia walked Yo-Yo at 5:40pm").
- Results are spoken and shown as Siri's dialog.
- Without a household, or without "me", an intent from Siri asks to continue in the app, which opens on "Which one is you?" or the welcome.
- On a shared screen (role shared), intents answer that this iPad asks who did it, so care is logged on it directly.
- App Shortcuts (`PorchlightShortcuts`) give phrases that work without setup: "Log a walk in Porchlight", "I walked \(companion) in Porchlight", "Check off a chore in Porchlight", "Add to my list in Porchlight", "What's next in Porchlight".
  Each intent is also visible in the Shortcuts app, with its parameters (which companion, which routine, which chore, which list).
- Companions, routines, chores and lists are App Entities; in the app their queries read the database, in the widget extension they read the summary (to configure which companion a widget shows).

### How a log from a widget or Siri reaches iCloud

1. The intent runs in the app's process; if the app wasn't running, iOS launches it in the background.
   Launching opens the database the usual way: the restore check, the sync engine, then `AppDatabase.launched`.
2. The write goes through that instance, so the engine's triggers record it as a pending change.
3. The engine sends pending changes on its own schedule while the process lives; the intent also asks it to send right away (`SyncController.sendSoon`) and waits a few seconds for that, so a background launch that ends quickly still delivers.
4. The wall receives it by push, like any other change, and shows "from Mia's phone" with its glow (D1).

When sync waits for a decision, or the phone is offline or signed out, the log is still written and the widget updates; it is pending in the engine and goes up the next time sync runs.
Nothing is ever lost or doubled: the row's id is stable and the write checked the slot first.

## The widgets (C3)

| Widget | Families | Shows |
|---|---|---|
| Companion | small; Lock Screen circular | One companion (configurable, the first by default): the open slot and a log button, or who did the last one and when, or the next slot. The circular one is the time since its main routine was last done ("🐶 9h"). |
| Today for you | medium | The open care slot with Log, and my chores today with check boxes, then "+N stars today". |
| Groceries | small | The list's count and first items; "+ Add" opens Lists in the app (a widget can't take typing). |
| Glow | Lock Screen rectangular | My stars this week and the family goal ("✨ Glow 23 · Pizza 72/80"). |
| Chores left | Lock Screen circular | How many of my chores are left today ("☑️ 1"). |

Two households and per-widget household choice are for M5's switcher; the summary is for the household on screen.

## Tests

- Unit: the summary builder from a test database (contents, today and tomorrow, me missing, no household, a shared screen writes nothing), the keeper writing only on change, the timeline planner (entries at window edges, the hourly count, the cap), the staleness rules, and each intent's work on a test database (logs once, stamps, respects rule 10, handles no "me" and no household).
- Widgets can't be driven by XCUITest reliably, so a unit test renders every widget family from summaries to PNG for review (light, dark, largest text, redacted, stale, empty household).
- What only a real phone can prove is listed at the end of the implementation notes.

## Implementation notes

Filled in as it is built.
