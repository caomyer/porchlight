# Companion characters

A pet's photo becomes a character of that pet: a pixel sticker in one house style, with four moods (doing fine, waiting, zoomies, asleep), each a still and a short animation.
It shows wherever the companion appears, on the phone and the wall, in place of the photo circle.
A companion with no character keeps its photo or drawn face everywhere, and a character is never needed for anything.

The approved proposal set the journey and the look; these decisions are taken:

- One house style for every pet: pixel sticker. No picker.
- Free, limited to three rounds of tries per pet. The relay enforces the limit; the app only shows what is left.
- Every mood is animated. Motion plays once when a character appears, then about once a minute, never in a loop, and not at all under Reduce Motion.
- Dogs and cats first. Other species keep today's faces.
- The drawing is OpenAI's, reached only through Porchlight's relay, never directly from the app.

It ships in three slices, each shippable alone: the photo sticker (no server), the character journey against a protocol, and moods that follow the day.

## Nothing changes on update

A household that updates and does nothing sees no change to any companion's face.
A companion with no sticker and no character draws exactly as in the release before characters, on every screen of the phone and the wall: its photo in a circle, its drawn face, or its emoji.
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

## Choosing the face, and going back

A companion's face is one choice for the whole household, shown everywhere on the phone and the wall: its character, its photo sticker, its photo, or the drawn face (the emoji for species without one).
The choice offers only what exists for that companion, and is made in two places: the companion editor's "Face" row, and the face sheet that the companion page's quiet link opens ("Change Yo-Yo's character or photo"), on the phone and on the wall.
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

An animation that fails (the model's animated output is a preview feature) never holds a mood back: the still stands, "Done" doesn't wait for animations, and an animation can be made another time.
A mood whose still fails says "Couldn't draw this one. Tap to try again."; "Done" waits for every mood's still, and a redraw that fails keeps the still it had.

Every failure has words and a way on (`CharacterWords.failure`):

- No network: "Porchlight can't reach the internet. Yo-Yo keeps the photo; try again once you're online." Try again, or use the photo sticker.
- The relay or the model down: "Drawing isn't working right now. Try again in a little while; Yo-Yo keeps the photo meanwhile."
- The model refused the picture: "OpenAI wouldn't draw this photo. Try another one, where Yo-Yo is clearly the subject." Another photo, or the sticker.
- App Check said no: "Porchlight's drawing service couldn't check this device. Try again later, or draw Yo-Yo from another device."
- A request outside the contract, which is a bug: "Something went wrong in Porchlight, not on your side. Try again; if it keeps happening, tell us."
- A limit: no rounds left for this pet ("Yo-Yo has had all three rounds of tries."), the household's calls for the day ("Your household has drawn a lot today. Try again tomorrow."), or a mood redrawn as often as it can be ("That mood has been redrawn as many times as it can be. The one before stays."). The relay now names the limit in its details; until the client reads it, the step and the rounds left from the relay's last answer tell them apart.

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

## Tests

`PhotoStickerTests` finds subjects in masks drawn in code, draws the sticker from a photo drawn in code and checks its square, its clear corners and its white outline, and covers no subject, several, one cut by the edge, a huge photo, an unreadable one, a device that can't and one too slow.
It runs Vision itself on a drawn picture and accepts a sticker, "unavailable" or "no subject", never a crash or a hang, since the simulator may not lift subjects.
It also covers the steps of making one, where it is kept, switching faces (nothing deleted or redrawn), removing a character, pictures from a newer build, the offer's rule in every case, and the faces offered.
`CharacterScreenTests` draws the companion page with the photo and with the sticker, Today with it, the offer card asking for a photo and offering to draw, the face sheet with a photo, a sticker and a character, and the sticker's steps, in light, dark and at the largest text.
`PhoneWeekTests.testMakingThePhotoStickerAndSwitchingFaces` and the wall's `StickerTests` make a sticker and switch faces in the app, with a drawn stand-in for the cut-out (`-debugStickerSubject`) and a photo drawn in code (`-samplePhoto`, `-sampleSticker`).
The repository holds no real pet's picture: the sample photo and sticker are drawn in code (`CharacterPlaceholders`).
