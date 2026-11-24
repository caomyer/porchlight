# The character relay

Porchlight draws a pet as a character by asking an image model.
The model's key cannot ship inside the app, so the app calls this relay and the relay calls the model.
The relay holds the key, the prompts and the limits, and keeps nothing but counters.

The design and its reasons are in `docs/design/companion-characters.md`, "The relay".
This file is how to set it up, test it and deploy it.

## What is here

- `functions/`: two callable Cloud Functions (2nd generation, Node.js 22, TypeScript).
- `firestore.rules`: no app may read or write the relay's counters.
- `evaluation/`: a script that draws characters from real photos, to judge them by eye and measure the cost. It spends money and is not part of CI.
- `scripts/deploy.sh`: lint, every test, then deploy.

## The contract

Both functions are callables in `us-central1`, and both refuse a call without a valid App Check token.

`drawCharacter` takes:

```
{ householdId, companionId, species: "dog" | "cat",
  step: "tries" | "mood" | "animation",
  mood?: "fine" | "waiting" | "zoomies" | "asleep",
  cutout: <base64 PNG, longest side at most 1024>,
  reference?: <base64 PNG> }
```

- `tries` takes the cut-out alone and returns `{ images: [three base64 PNGs, 512 square], roundsLeft }`.
- `mood` needs `mood` and `reference` (the chosen character) and returns `{ image }`, a 512 square PNG.
- `animation` needs `mood` and `reference` (that mood's still) and returns `{ gif, frames }`, a 512 square GIF and the number of frames it really holds.

`characterAllowance` takes `{ householdId, companionId }` and returns `{ roundsLeft }`.

The ids are the app's own UUIDs.
Any other field, a prompt included, is refused.

A failure carries one of these in `details.code`, which is the only thing the app should read:

| `details.code` | Sent under the callable status | Meaning |
|---|---|---|
| `limit-reached` | `resource-exhausted` | A limit below stands in the way. |
| `refused` | `failed-precondition` | The model will not draw from this picture. |
| `unavailable` | `unavailable` | The model or the relay failed, or the day's spending ceiling is reached. Try later. |
| `invalid` | `invalid-argument` | The request is outside the contract. A bug in the app. |
| (none) | `unauthenticated` | No valid App Check token. Firebase answers this itself, before the relay runs. |

A callable's status is one of a fixed set, which is why the relay's own codes ride in `details`.

The app calls `drawCharacter` with a limited-use App Check token, because the relay spends each token it accepts:

```swift
let options = HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)
let draw = Functions.functions(region: "us-central1").httpsCallable("drawCharacter", options: options)
```

`characterAllowance` takes an ordinary App Check token.

## Limits

All in `functions/src/config.ts`.

- Three rounds of tries for one companion, for life. A round is one `tries` call.
- Each mood's still may be drawn three times for one companion, and each mood's animation three times.
- Six companions in one household.
- 40 calls in one UTC day for a household, and 40 for one signed-in installation.
- The whole project stops drawing for the day at 5 dollars, set by the `DAILY_SPEND_CEILING_DOLLARS` parameter.

A drawing that fails or is refused uses up no round and no redraw.
It still counts toward the day's 40 calls, because that ceiling is there to stop a runaway app.

The installation ceiling only applies when the app signs in (Firebase Anonymous Authentication is enough).
App Check proves a call comes from a genuine copy of the app, but it does not say which device, so without sign-in only the household ceiling applies.

## What it costs to run

- A whole character is 8 calls and about 55 cents of model use: a round of tries (about 9 cents), three more moods (about 6 cents each) and four animations (about 7 cents each).
- The function has no instance kept warm, so it costs nothing while idle.
- The first call after a quiet spell starts an instance, which adds a few seconds. That figure is an expectation, not a measurement.
- Each call holds an instance for 8 to 15 seconds while the model draws.

## Why it is built this way

This section belongs in `docs/design/companion-characters.md` as "The relay", and moves there when that file exists.

- **The key stays on the server.** A key inside an app can be read out of it. The relay reads the key from Secret Manager at run time and nowhere else.
- **Only the real app may call.** App Check with App Attest proves a call comes from a genuine copy of Porchlight on a real device. `drawCharacter` also spends each token, so a captured token cannot be used twice.
- **The app sends no words.** It picks a step, a mood and a species; every prompt is on the server. A stolen session cannot make the relay draw anything else, and any unknown field is refused.
- **Limits are transactions.** A call first takes what it needs from the counters, all or nothing, in one Firestore transaction; then the model is asked; then the real cost replaces the estimate, or everything is given back if nothing was drawn. Calls that arrive together cannot pass a limit between them.
- **Spending has a ceiling.** Every call reserves its estimated cost against the day's ceiling before the model is asked. Past the ceiling the relay answers `unavailable` and logs an error, whatever the per-household limits say.
- **Nothing is kept.** The relay stores counters under one-way hashes of the app's ids. No photo, no drawing, no prompt and no id is stored or logged; a log line holds hashed ids, the step, the time taken, token counts and the class of an error, and anything longer than a short word is cut before it is written.
- **One model call per step.** The three tries are one call for three pictures at the cheap quality. A mood is drawn from the chosen character with the photo's cut-out beside it. An animation is drawn from that mood's still alone, so the character cannot change while it moves.
- **A still is drawn at 1024 and handed back at 512**, because the model will not draw a still smaller than about 800 square. An animation is asked for at 512 a frame: its nine frames are laid on one sheet, and a larger frame does not fit the model's size limit.
- **One retry.** A rate limit, a timeout or a server error gets one more attempt. A refusal, or a request the model will not take as written, gets none.

## Set up, once

These steps are the project owner's, in the Firebase and Google Cloud consoles.
They are not scripted, and the relay's code never does them.

1. Create the Firebase project.
2. Put it on the Blaze (pay as you go) plan. Cloud Functions need it.
3. Set a budget alert on the billing account, for example at 10 dollars a month.
4. Register the iOS app with the bundle id `com.mingyucao.porchlight`, and download its `GoogleService-Info.plist`.
5. In App Check, register that app with the App Attest provider.
6. Create the Firestore database in native mode. A US location such as `nam5` pairs with the functions' region, `us-central1`.
7. In the Google Cloud console, under IAM, give the Default compute service account the "Firebase App Check Token Verifier" role. Without it `drawCharacter` cannot spend a token and refuses every call.
8. Create an OpenAI key for production, restricted to image generation, with a monthly budget on the OpenAI account.
9. Store that key as the relay's secret. The command asks for the value and does not show it:

```
npx --prefix firebase/functions firebase functions:secrets:set OPENAI_API_KEY --project <project-id>
```

The project id is never committed, because this repository is public.
Give it to each command, or copy `.firebaserc.example` to `.firebaserc`, which is git-ignored, and put it there.

## Test

```
cd firebase/functions
npm ci
npm run lint
npm test
```

`npm test` builds, runs the unit tests, then starts the Firestore and Functions emulators and runs the limit tests and the callable tests in them.
The image model is a stand-in throughout: no key is needed and nothing is spent.
The emulators use the made-up project `demo-porchlight`, so they can never touch a real one.
They need Java.

The emulators listen on ports 5417, 8417, 4417 and 4517 (`firebase.json`).

What the emulator cannot show: it turns away a call with no App Check token, but it accepts any token without verifying it.
A forged token being refused, and a token being spent once, are Firebase's own behaviour in production.

CI runs the same commands in `.github/workflows/relay.yml`, on Linux, when `firebase/` changes and on every push to `integration/next` or `main`.

## Deploy

```
zsh firebase/scripts/deploy.sh <project-id>
```

It installs, lints, runs every test, checks the secret is set (without reading it), then deploys the two functions and the Firestore rules.
The first deploy asks for `DAILY_SPEND_CEILING_DOLLARS` if it is to differ from 5; the answer is kept in `functions/.env.<project-id>`, which holds no secret.

After a deploy, check in the Firebase console that both functions show App Check as enforced.

To take the relay out of service at once, delete the functions or set the ceiling to 0 and deploy again:

```
npx --prefix firebase/functions firebase functions:delete drawCharacter characterAllowance --region us-central1 --project <project-id>
```

## Evaluate the prompts on real photos

```
npm --prefix firebase/functions run build
node firebase/evaluation/run.mjs --photos <folder> --out <folder> --key-file <file> --budget 5 --animations fine
```

- Each photo is named `<name>.<dog|cat>.jpg`.
- `--key-file` is a file outside the repository with an `OPENAI_API_KEY=` line. The key is never printed.
- The script cuts each pet out as the app does (Vision, on a Mac), then uses the relay's own prompts and request code.
- It stops before a call that would pass the budget.
- It writes one contact sheet per pet, every image, `usage.tsv` with the tokens and cost of each call, and `summary.json`.

Use photos you may use: your own, or ones in the public domain.
Do not commit them.
