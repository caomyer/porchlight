# Companion characters

A pet's photo becomes a character of that pet: a pixel sticker in one house style, with four moods (doing fine, waiting, zoomies, asleep), each a still and a short animation.
It shows wherever the companion appears, on the phone and the wall, in place of the photo circle.
A companion with no character keeps its photo or drawn face everywhere, and a character is never needed for anything.

The approved proposal set the journey and the look; these decisions are taken:

- One house style for every pet: pixel sticker. No picker.
- Free, limited to three rounds of tries per pet. The relay keeps the count; the app only shows what is left.
  During beta testing the relay counts the rounds and does not enforce them ("What the relay counts and what it enforces", below).
- Every mood is animated. Motion plays twice when a character appears, then twice about every ten seconds and twice on a tap, never in a loop, and not at all under Reduce Motion. (It was once a minute until James's first live test, where it was missed.)
- Dogs and cats first. Other species keep today's faces.
- The drawing is OpenAI's, reached only through Porchlight's relay, never directly from the app.

It ships in three slices, each shippable alone: the photo sticker (no server), the character journey against a protocol, and moods that follow the day.

## Nothing changes on update

A household that updates and does nothing sees no change to any companion's face itself.
A companion with no sticker and no character draws exactly as in the release before characters, at any size it is drawn: its photo in a circle, its drawn face, or its emoji.
Where it stands did change for every household on the phone, by design: a companion's page opens on center stage with the face at 168 points, and its Today card shows the face at 84 points, both in the same round frame as before ("Where it stands").
The wall's screens are as they were.
Widgets and notifications never drew a companion's face and still don't.
Nothing is generated, cut out, uploaded or migrated on update: the "characters v1" migration only adds the two empty tables.
No call goes to Firebase, not even for an App Check token, until someone taps Draw; Firebase is configured then, not at launch.
The only new thing a household may see is the offer card on a pet's page, which closes for good on that device.

It is tested, not only intended (`FaceUnchangedTests`):

- Each kind of face (photo, drawn dog awake and asleep, cat, bird and plant emoji, a photo whose bytes are missing), in light and dark, at three sizes, draws the same pixels as a verbatim copy of the release's face, both with no face chosen and with a face chosen that has nothing to show.
- The migration, run on a household with care and a photo, leaves every row of every existing table as it was, and adds no face and no picture.
- Browsing a companion's page and its care sheet starts no cut-out and stores nothing (`PhotoStickerTests.browsingCutsNothing`); the relay's client counts its calls the same way, and the same browse makes none.

## The photo sticker

The phone or the wall cuts the companion out of its photo on the device and draws it as a sticker: the subject at 80% of a clear square, a white outline and a soft shadow (`PhotoSticker`).
Nothing leaves the device, so it needs no consent and costs nothing.
It is offered as the free path beside drawing a character, and on its own until the relay exists.

The cut-out is Vision's subject lifting, `VNGenerateForegroundInstanceMaskRequest` (iOS 17).
Each subject Vision finds is read at a small size, and the largest is used.
Others at least a fifth of its size are counted, and the sheet says "There's more than one subject in this photo, so Porchlight used the biggest."
A subject that covers a stretch of the photo's edge is cut by it, and the sheet says "Part of Yo-Yo is outside the photo, so the sticker is cut off there too."
A subject smaller than 1% of the photo is no subject: "Porchlight couldn't find Yo-Yo in this photo. Try one where Yo-Yo stands out from the background."
A photo is read no larger than 2048 pixels on its long side, upright, so a 48 megapixel original never goes to Vision whole; a companion photo is stored at 800 already.

Subject lifting needs an A12 chip or later, and the old wall iPad has an A10X.
Where Vision can't run, it throws, and where it takes longer than 15 seconds the cut is given up: either way the sheet says "This iPad can't cut a photo out, so Yo-Yo keeps the photo. A phone can make the sticker, and it shows here too."
The photo stays; a sticker made on a phone syncs to the wall and shows there like any other.
This has not been tried on the A10X itself, only reasoned from Apple's requirements and tested with a finder that never answers.

The sheet shows the photo and the sticker side by side, says it was made on this device and that nothing is sent, and offers "Use the photo sticker", "Choose another photo" and "Not now".
A photo picked there becomes the companion's photo too when its sticker is used, so choosing the photo again shows the one the sticker came from.
A slow cut overtaken by another photo is dropped, so the sheet never shows the sticker of a photo no longer chosen (`StickerMaking`).

## Where it stands

A character or a photo sticker is drawn on clear with its own white edge, so it stands on the card itself: no tinted disc behind it, and it fills the disc's whole frame.
A photo or a drawn face keeps its disc and its size exactly as before, pixel for pixel.
One view decides (`DiscFace`, by `CompanionLook.standsOnCard`); every place that put a disc behind a face (the phone's badge on Today and a companion's page, the wall's Today tile, the editor's preview) draws through it.
In James's first live test the character sat on a tan disc, which made a clear, edged picture look pasted on.

A character or a sticker standing on the card casts a soft ground shadow, so it stands rather than floats (`StageFace`, the one face both the wall's hero and the phone's page draw).

On the phone a companion's page opens on center stage, as the wall's hero does: the face at 168 points on every phone, then the week's name, what the pet is and the week so far, the mood and the way to change the face, all centred.
Under the name, one line of who the pet is and the week so far, in few words ("Toy poodle · 4 yrs · 12 walks · 5h 50m out · 24 stars"), the same on past weeks with their dates: a size smaller if it must, and wrapped rather than cut or shortened by dropping anything.
The mood's track has no names at its ends on the phone, as the mock drew it; the mood under it says where the marker is, and VoiceOver still reads the ends.
The face does not shrink on short screens, so "Log a walk" moved down by about 100 points.
It is on the first screen of the largest phone; on an iPhone 15 (393 by 852 points) it ends about 32 points below the tab bar's top, and on the smallest phone (375 by 667) it is a scroll away, as it already was before.
To give back what could be given honestly, the week pager no longer keeps a row of its own for "Back to this week": the link sits under the week's name, in the arrows' row, which is always as tall as the two need, so nothing moves when stepping away (on Food's diary and Glow too).

On Today a companion's card shows the face at 84 points, inside the card, beside the name, with no rise over the card's edge and no extra margin.
The name, the last walk's line and the streak sit one under another beside it, so the line keeps one line ("Walked 23h ago by Carol" included) and the card grows by only the face's extra height.
A photo or a drawn face keeps its round frame at that size.
A tap on a character that moves plays its mood's animation and does nothing else: no hop, no sparkles, no words.
A tap on any other face, or on a character under Reduce Motion, opens the companion's page, as the rest of the card's header does.

## Choosing the face, and going back

A companion's face is one choice for the whole household, shown everywhere on the phone and the wall: its character, its photo sticker, its photo, or the drawn face (the emoji for species without one).
The choice offers only what exists for that companion, and is made in two places: the companion editor's "Face" row, and the face sheet that the companion page's quiet link opens ("Change Yo-Yo's character or photo"), on the phone and on the wall.
On the phone the link sits in the page's header, under the lines beside the face, as it sits under the name in the wall's hero; it was at the very end of the page until James's first live test, where he didn't find it.
Switching away from the character or the sticker deletes nothing, and switching back costs nothing and redraws nothing (`AppDatabase.chooseFace`).
The face sheet also makes the photo sticker ("Make a photo sticker", or "Make a new photo sticker" over an old one) and, once there is a character, removes it.
"Remove character" asks first, "Remove Yo-Yo's character for everyone?", says its moods are deleted on every device and that drawing another uses a round of tries again, with the rounds left when the relay has said; the rounds used are not given back.
If the character was showing, the sticker shows instead when there is one, else the photo; a face chosen over it stays chosen.
Changing the companion's photo never changes or deletes a character or sticker: they were drawn from the photo before, and stay until replaced.
Once drawing exists, a new photo will offer to draw a new character when rounds are left.

The stored choice is a face, not "whatever is newest": nil until someone chooses (the photo, or the drawn face without one), and a chosen face that isn't there (a character not yet arrived by sync) shows the photo meanwhile (`CharacterLook.shown`).

## The offer

On the phone, a card under the companion page's hero: "Give Yo-Yo a character", what it does, and "Draw Yo-Yo", with a close control.
One pure rule decides it for every screen (`CharacterOffer.card`):

- It shows only for species drawn so far (dogs and cats).
- It doesn't show while drawing is unavailable: no Firebase configuration in this build, or the allowance says no rounds are left and there is no character.
- It goes by itself as soon as the companion has a character or a photo sticker, even one not showing, and while one is being drawn.
- On a companion with no photo, it asks for a photo first ("Add a photo"), and offers to draw once there is one.
- Closing it hides it on this device for this companion, like the catch-up banner's dismissal: kept in this device's preferences, never synced.

After it is closed, the face row in the editor and the page's link are the way in.
Until the relay ships in a build, the card never shows, and the photo sticker is made from the face sheet.

## The character journey

Four steps, from the offer card, the face sheet's "Draw Yo-Yo", or the editor's "Draw a new character from this photo" (`CharacterJourneyContent`, its steps in `CharacterDrawing`):

1. The device cuts the pet out of its photo, as for the sticker; with no photo, it asks for one first.
2. Consent, shown rather than described: "This is what we'll send", the photo and the cut-out side by side, and "Only the cut-out of Yo-Yo goes to OpenAI to be drawn. The rest of the photo stays on this phone. OpenAI doesn't train on it and deletes it within 30 days." It offers "Draw Yo-Yo", "Keep it on this phone: use the photo sticker" (the free path, which sends nothing) and "Choose another photo". Nothing is sent before "Draw Yo-Yo".
3. "Drawing Yo-Yo", honest about the wait ("It takes about half a minute, sometimes more"), then "Which one is most Yo-Yo?": three tries, "This one", and "None of these: try again (2 left)" while rounds are left.
4. "Meet Yo-Yo": the four moods, each arriving as it is drawn to match the try picked (doing fine is the try itself); tapping a mood redraws just that one. "Done" saves the character in one transaction and shows it for the whole household.

What the consent shows is, byte for byte, what is sent: the tries, every mood and every animation get the cut-out the sheet showed and nothing else (`CharacterDrawingTests.shownIsSent`).
When no cut-out can be made (no subject, a device that can't lift one, an unreadable photo), the journey stops there with the sticker's words and offers another photo; nothing is sent, neither a crop nor the whole photo (`noCutoutSendsNothing`).
Sending the whole photo instead was considered and left out: "only the cut-out leaves this phone" stays true without a second kind of consent, and another photo is the better way on.
On a phone the face sheet opens at full height, since the journey's steps differ in height and a sheet fitted to each would leave the page behind cut at a different line each time.

"Done" comes once every mood is settled: its still drawn, and its animation come or failed (`CharacterDrawing.isSettled`), so nothing the relay has drawn and counted is still on its way when the character is saved.
Until then a mood's tile says "Drawing...", the still dimmed under the spinner, as while its still is drawn.
In James's first drawing "Done" came with the last stills, ten seconds before three of the animations, and those were dropped for good: waiting, zoomies and asleep never moved.
An animation that fails (the model's animated output is a preview feature) settles its mood all the same: the still stands on its own, and "Done" comes.
A redraw unsettles only its own mood, until its new still and movement come; a drawing closed mid-way and resumed draws the movements that hadn't come.
A mood whose still fails says "Couldn't draw this one. Tap to try again."; "Done" waits for every mood's still, and a redraw that fails keeps the still it had.

Every failure has words and a way on (`CharacterWords.failure`):

- No network: "Porchlight can't reach the internet. Yo-Yo keeps the photo; try again once you're online." Try again, or use the photo sticker.
- Unavailable, by the relay's reason: the project's spending for the day ("Porchlight has drawn all it can for everyone today. Try again tomorrow; Yo-Yo keeps the photo meanwhile."), the model ("OpenAI isn't drawing right now. Try again in a little while; ..."), or the relay itself and no reason ("Drawing isn't working right now. Try again in a little while; Yo-Yo keeps the photo meanwhile.").
- The model refused the picture: "OpenAI wouldn't draw this photo. Try another one, where Yo-Yo is clearly the subject." Another photo, or the sticker.
- App Check said no: "Porchlight's drawing service couldn't check this device. Try again later, or draw Yo-Yo from another device."
- A request outside the contract, which is a bug: "Something went wrong in Porchlight, not on your side. Try again; if it keeps happening, tell us."
- A limit, by the relay's reason (`details.reason`):
  - `rounds`: "Yo-Yo has had all three rounds of tries."
  - `household-day`: "Your household has drawn a lot today. Try again tomorrow."
  - `installation-day`: "This device has drawn a lot today. Try again tomorrow, or from another device."
  - `companions`: "Your household has characters for as many pets as it can have. A photo sticker is always free."
  - `mood-redraws`: "That mood has been redrawn as many times as it can be. The one before stays."
  - `animation-redraws`: "That mood's movement has been redrawn as many times as it can be. It stays as it is."
  - With no reason (an older relay, or one this build doesn't know), the step and the rounds left from the relay's last answer tell the limits apart.

A drawing the app closed mid-way is kept on this device, never synced (`CharacterDraftStore`, a file per companion in Application Support): the cut-out, the tries, the one picked and the moods so far.
Coming back, the face sheet says "Finish drawing Yo-Yo", and the journey offers "Finish drawing" (back to the tries, or to the moods so far, without drawing again) or "Throw it away".
Nothing of a drawing shows anywhere until "Done", and while one waits to be finished the offer card stays away.
The rounds the relay last reported are remembered per companion on the device, so the offer and "Remove character" can say them without asking the relay, which is never called before "Draw".

The relay is reached through `CharacterService` (`allowance`, `tries`, `mood`, `animation`); tests, previews and UI tests use `FakeCharacterService`, which draws placeholder pixel sprites in code, counts its calls and fails as scripted (`-debugCharacterService draws|noAnimations|limit|refused|unavailable|offline|slow`).

## Storage and sync

Two synced tables under the companion ("characters v1"):

- `companionCharacter`, one per companion that has chosen, keyed by it: the face chosen (`character`, `sticker`, `photo` or `drawn`), the character's style (`pixel`), who chose and when.
- `companionCharacterImage`, one per companion, set (`sticker` or `character`), mood and kind of picture (`still`, or `frames` for an animation's strip), keyed by an id derived from those four, with its frame count, byte count and bytes.

A companion can have a sticker and a character at once, so switching between them redraws nothing.

Both hang off the companion, which every device already has, never the pictures off the character row: an updating device puts new tables' rows in, table by table, in no set order (docs/design/dishes.md, "Updating"), and a picture that arrived before its character row must not be refused for want of a parent.
The derived id makes a picture redrawn on two devices at once one record, not two.
Saving a sticker or a character writes its set of pictures in one transaction and deletes any picture left from the set before, so a half set is never stored; unchanged pictures are not written, so sync sends nothing for them.
Screens read sizes only (`AppDatabase.characterLooks`); the bytes load when a face is drawn, through `PhotoImages`, keyed by byte count so a changed picture is never shown from the cache.
A character whose still for doing fine hasn't arrived yet isn't drawn: the photo stays until it has.
A face, set, mood or picture kind a newer build adds is skipped, not an error.

A sticker is one still, a 512 pixel PNG, shown for every mood; on the sample's drawn photo it is about 120 KB.

Older builds keep the new records waiting in the sync engine's metadata and show the photo, which still syncs; on updating they show the sticker (`OlderBuildSyncTests.olderBuildAndCharacters`).
The CloudKit schema gains both record types (`Config/cloudkit-schema.ckdb`, checked by `SchemaFileTests`); they must be deployed to Production before a build that writes them ships.

## Moods follow the day

A character's mood is one pure rule, `CharacterMoodRule.mood(for:now:)`, read from what the app already knows about today: the slots owed, what was logged and when, and the time of day in the household's calendar.
Every face that has the companion's report passes it on as `mood:` (`report.characterMood`); a face without a report keeps reading its expression, sleepy for asleep and doing fine otherwise.
The log celebration is always the zoomies.

When more than one mood applies, the first of these wins:

1. Waiting, overdue: a slot that is late, or open past its routine's nudge time, and still owed.
2. Zoomies: something was logged within the last hour.
3. Waiting: a slot is open now.
4. Asleep: it is night (9 PM to 6 AM), or everything owed today is done.
5. Doing fine: anything else.

The reasons for the order:

- Care that is owed and running late is the one thing a face must never hide, so it comes first, even over a walk logged a minute ago.
- The zoomies are the thanks for logging, and they only last the hour, so they show over a slot that has merely opened; the card's own words still say that slot is open.
- Waiting comes before asleep, so at 9 PM a companion whose walk is still owed waits up for it.
- Night runs to 6 AM, not to midnight, so a companion is asleep at 2 AM though the new day's slots are all ahead of it.

A slot that was never owed (its window closed before the companion arrived) never makes it wait, by the same rule the paw trail uses (`CareLogic.isOwed`).
An all-day slot waits from midnight but is never late; only its nudge makes it overdue.
A log set in the future is not "just now".
Asked about a moment on another day than the report's, the report's slots say nothing, and only the hour and the last log speak.
The widgets draw no face, so they have no mood.

## A mood's animation

The relay sends an animation as a GIF: nine frames, 512 pixels square, on clear.
`CharacterAnimationCodec.strip(fromGIF:)` turns it into what `CharacterImage` stores: one PNG strip of square frames side by side, each 512 pixels, the relay's own size, so a character on center stage (168 points, 504 pixels on the phone) is as sharp moving as at rest.
Strips stored before frames were 512 have 256 pixel frames; they stay as they are, with no migration and no redraw, and are read the same way.

On screen every frame, and the first frame at rest, is scaled by one rule (`CharacterPixels`): without smoothing when the picture is enlarged, so a 256 pixel frame at 168 points has about two screen pixels to each of its own and stays crisp; smoothed when it is reduced, so a 512 pixel frame at 84 points drops no row or column.
A strip is one picture to store, sync and decode, and a frame is drawn by sliding the strip, so nothing is decoded while it plays.

- Frames are read as they would show: a GIF whose later frames hold only what changed is composed first, which ImageIO does and `CharacterAnimationTests.partialFramesAreComposed` pins.
- A frame that isn't square is fitted inside its square and centred, on clear.
- More than 16 frames are sampled evenly down to 16, first and last kept.
- Bytes that are not an animation (a still, an error page, a GIF of one frame or cut short) make no strip, and the mood's still stands on its own.
- The GIF's own frame delays are dropped: every frame shows for 0.12 seconds, so a play of nine frames is about a second, and nothing more needs storing.

The strip is a palette PNG (`PalettePNG`): each pixel one byte, an index into at most 256 colours, each with its clearness.
A GIF is itself a palette picture, so a strip cut from its frames has no more colours than a palette holds, and the palette PNG is the same picture pixel for pixel at about a third of the bytes of a full-colour one.
ImageIO reads a palette PNG like any other but does not write one, so `PalettePNG` writes it with zlib.
It never changes a colour: a strip with more than 256 colours is stored as a full-colour PNG instead, with nothing lost.
Any PNG reads back the same way, so a strip stored either way plays.

Measured on nine of the relay's real drawings (four moods of one dog and the evaluation's five animals), every strip had 210 to 255 colours and came back with no pixel changed.
A strip is 0.10 to 0.22 MB as a palette PNG, where the full-colour one was 0.27 to 0.67 MB.
Four moods' animations of one pet measured 0.79 MB together, where they were 2.39 MB.
At 512 pixel frames, the size new animations are kept at, a strip holds four times the pixels: the same nine drawings measured 0.31 to 0.73 MB a strip, and one pet's four moods 2.57 MB together.
Every strip stays far under CloudKit's limit for an asset, and nothing in the app limits a picture's bytes; what grows is iCloud storage and the first sync of a household's pets.

The pictures travel to iCloud as assets, not record fields (`image` is an `ASSET` in `Config/cloudkit-schema.ckdb`), so a record's one megabyte limit does not apply to them at either size.

It plays by `CharacterPlayback`, a pure schedule, in turns of two plays back to back, about two seconds: a turn when the face appears, then it rests, then a turn about every ten seconds while it is on screen, and a turn whenever the face is tapped where the face is itself what is tapped.
A turn begins only once the strip is decoded and ready to show; bytes not there yet (still on their way by sync) are asked for again every ten seconds while the face is on screen.
In James's first live test (build 20261124.085813) he saw no movement at all: the one play began as the face appeared, while the strip's bytes were still being read, so it passed on the still, and the next play was a minute away.
A character that animates never bobs, on the wall's hero or anywhere, on a tap or on the minute: its animation is its life, and nothing is added to it (`CompanionFace.bobs`).
A photo, a sticker or a drawn face bobs on the wall's hero as before.
It never loops.
Under Reduce Motion it never moves.
It plays only while the app is in front, and its task ends when the face leaves the screen.
A face smaller than 40 points stays still, since nine frames in a small dot are only a flicker.
At rest a character is one picture and no timer, so a page of pets costs what their stills cost; a turn runs a timeline for about two seconds and then the timeline is gone.
A frame stands in for the still, never over it, so the still never shows through where a frame is clear.

At rest a face shows its animation's first frame, not its still, wherever the mood has a strip: at every size, on the phone and the wall, including faces too small to animate.
The still is a separate drawing with its own pose and outline, so resting on it made every play begin and end with a jump.
It is drawn by the very view that draws a play's frames (`CharacterFrame`, at frame 0), so it is the very pixels a play starts and ends on, and `CharacterPresenceScreenTests.restIsFirstFrame` proves the two identical.
While the strip is being read nothing shows, never the still first, since that would swap the still for the frame a moment later on a cold open.
The still shows only when the mood has no strip, or the strip's bytes are gone or can't be read.
A new mood plays its own animation at once.

### Where a tap plays

A face listens for a tap only where the face is itself what is tapped (`CharacterTap`): the phone page's center stage and the wall's hero play on a tap; the phone's Today card face is its own Button, and its action plays a character that moves and opens the page for any other face.
Everywhere else a character is a picture inside something that is tapped (the wall's rail entry, the phone's grid and all-set cards, the companions list, the face sheet's choices, the calendar's moments), and the face has no tap of its own.
In build 20261124.220829 every face carried a tap gesture, and inside a Button it took the touch from the Button: the wall's rail entry for a character and the phone's grid card did nothing at all when tapped, and the all-set card nothing when tapped on the face.
`PhoneCharacterTapTests` and `WallCharacterTapTests` touch each of those faces on its own pixels, real touches rather than accessibility activations, which would go round the gesture.

## The relay's client

`RelayCharacterService` is the real `CharacterService`: it knows the contract (what is sent, what comes back, which error is which) and nothing of Firebase.
The transport behind it is `CharacterRelayBackend`; the real one, `FirebaseRelayBackend`, is the only file that imports Firebase.

What is sent, as firebase/README.md has it:

- `characterAllowance` with the household's and the companion's ids, with an ordinary App Check token.
- `drawCharacter` with those ids, the species, the step, the cut-out as base64, and for a mood or an animation the mood and the picture to match; with a limited-use App Check token, which the relay spends.
- Ids go in lower case, as the app writes them.
- The app sends no prompt and no text of its own.

An answer outside the contract (a picture that is not base64, a still that is not a PNG, an animation that is not a GIF, a count that is not a number) is the relay being unavailable, never a broken picture on a screen.

Failures are read in this order: no network, then the relay's own `details.code`, then a caller that could not be checked (`unauthenticated`), and anything else is unavailable.
`CharacterServiceError` carries the code as `kind` and, beside it, the relay's `details.reason`: which limit was reached (`rounds`, `mood-redraws`, `animation-redraws`, `companions`, `household-day`, `installation-day`) or why it is unavailable (`spend-ceiling`, `model`, `relay`).
A reason that is unknown, missing or belongs to another code is no reason, and the kind alone speaks.
Screens decide by kind and word by reason.

With no network nothing is sent: the system's path monitor says so before a call that could otherwise wait three minutes.
A drawing may take 180 seconds, the function's own limit (one model attempt of up to 75 seconds and one retry); asking what is left, 30.
Cancelling the task ends the wait at once.
The request cannot be taken back, so the relay may still finish the drawing and count it.

### What the relay counts and what it enforces

The relay counts everything it draws, per companion, for life, and per household and installation, per day.
Which counts turn a call down depends on one switch, the relay's `ENFORCE_LIFETIME_LIMITS` parameter (`firebase/functions/.env`).

Counted and enforced always, because they protect the bill:

- 40 calls in a UTC day for a household, and 40 for a signed-in installation.
- Six companions with characters in a household.
- The whole service's spending in a day, 5 dollars.

Counted always, enforced only when the switch says `true`:

- Three rounds of tries for a companion.
- Three draws of each mood's still.
- Three draws of each mood's animation.

During beta testing the switch is `false`.
A call past one of these three is drawn like any other, counted like any other, and its log line carries `overLimit: true` and `limit` naming which was passed.
The counts stay true, so turning the switch to `true` and deploying enforces the limits again from what was really used, with nothing to repair: a companion past three rounds is then turned down, and one within them is unaffected.

What the app is told while the switch is `false`:

- `roundsLeft`, from `characterAllowance` and from each round of tries, is the real number left until it would reach 0, and from then on it is 1.
  A companion nothing was drawn for reads 3; after one round 2; after two rounds 1; after three, four or ten rounds, still 1.
  It never reads 0, because a build stops offering "Draw a new character" at 0.
- So the app states a count only above one: "None of these: try again (2 left)", then "None of these: try again"; removing a character says "2 rounds are left.", then says nothing of rounds.
  "1 left" would be untrue for good during the beta, and with the limits enforced the last round goes unannounced, which is still true.
- The app remembers none left only when the relay answers `limit-reached` with the reason `rounds`; the household's or a device's calls for the day used up are gone tomorrow, and are never remembered as none left (`CharacterDrawingTests.roundsDuringBeta`).
  The app has no cap of its own on rounds or redraws.
- No `limit-reached` with the reason `rounds`, `mood-redraws` or `animation-redraws` is sent.
  The reasons `companions`, `household-day` and `installation-day`, and `unavailable` with `spend-ceiling`, are sent as before.

What can still stop a tester: the household's 40 calls in a day.
A whole character is 8 calls, so a household that draws five characters in one day, or redraws a great deal, meets "household-day" and waits for the next UTC day.

### Nothing until asked

A household that never asks for a character makes no call to Firebase and configures none of it.
At launch `CharacterRelay.install` only reads the build's four ids and puts the service in `CharacterServices.live`.
Reading `isConfigured` makes no backend.
The first drawing or allowance call makes the backend, which configures Firebase for the process, once.
`CharacterRelayClientTests.nothingUntilAsked` and `firebaseNotConfiguredAtLaunch` hold the app to it; the second runs inside the launched app, as every unit test does.

### Firebase in the build

The app links three Firebase libraries, pinned to an exact release in project.yml: Core, App Check and Functions.
It uses no Analytics, no Auth, no Firestore and no messaging, and Firebase never wraps the app delegate (`FirebaseAppDelegateProxyEnabled` is off).
App Check fetches a token only when a call needs one, never on its own in the background (`FirebaseAppCheckTokenAutoRefreshEnabled` is off).

The project's ids are not secrets, but the repository is public, so they are never committed.
The owner's `GoogleService-Info.plist` stays outside the repository, at `~/.config/porchlight/GoogleService-Info.plist`.
`scripts/firebase-config.sh` writes four of its values to `Config/Firebase.xcconfig`, which is git-ignored and which `Config/Base.xcconfig` includes when it is there; they reach the app through its Info.plist.
The plist itself is never bundled, so a build needs no file that may be missing.
A build without the ids, CI's among them, builds, launches and passes every test, has no relay, and never offers to draw.
`scripts/testflight.sh` runs that script first and stops loudly without the plist: a release that silently could not draw would only be found out on someone's phone.

### App Check

Every build people run uses App Attest, so the relay knows a call comes from a genuine copy of Porchlight on a real device.
The entitlement's environment is production in Release builds, as CloudKit's is, and development in Debug.
A debug build may use App Check's debug provider, and only when it is handed a debug token for that run, as the environment variable `FIRAAppCheckDebugToken` or the launch argument `-debugAppCheckToken`.
The token is registered in the Firebase console by the project's owner and is never in the repository.
On a simulator there is no App Attest, so without a debug token the relay refuses a debug build as unauthenticated.

Not yet seen on a real device: App Attest attesting and the relay accepting its token, a limited-use token being spent once, and whether the wall's old iPad can attest at all.

## Tests

`PhotoStickerTests` finds subjects in masks drawn in code, draws the sticker from a photo drawn in code and checks its square, its clear corners and its white outline, and covers no subject, several, one cut by the edge, a huge photo, an unreadable one, a device that can't and one too slow.
It runs Vision itself on a drawn picture and accepts a sticker, "unavailable" or "no subject", never a crash or a hang, since the simulator may not lift subjects.
It also covers the steps of making one, where it is kept, switching faces (nothing deleted or redrawn), removing a character, pictures from a newer build, the offer's rule in every case, and the faces offered.
`CharacterScreenTests` draws the companion page with the photo and with the sticker, Today with it, the offer card asking for a photo and offering to draw, the face sheet with a photo, a sticker and a character, and the sticker's steps, in light, dark and at the largest text.
`PhoneWeekTests.testMakingThePhotoStickerAndSwitchingFaces` and the wall's `StickerTests` make a sticker and switch faces in the app, with a drawn stand-in for the cut-out (`-debugStickerSubject`) and a photo drawn in code (`-samplePhoto`, `-sampleSticker`).
The repository holds no real pet's picture: the sample photo and sticker are drawn in code (`CharacterPlaceholders`).
`CharacterMoodRuleTests` covers each mood, the order when two apply, the all-day slot, a report's own mood through a day, another day than the report's, and a slot never owed.
`CharacterAnimationTests` covers the strip from the relay's GIF, a GIF of partial frames, other shapes and frame counts, everything that is not an animation, and the schedule of a play.
`CharacterAnimationScreenTests` draws a character at rest and a frame mid-play, and checks one frame shows, clipped to the face.
`CharacterRelayClientTests` covers the build's ids, what each call sends, answers outside the contract, every failure with its reason, no network, cancelling, the debug token, and that nothing is made, configured or sent until a character is asked for.
