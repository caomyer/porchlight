import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onCall, type CallableOptions, type CallableRequest } from "firebase-functions/v2/https";

import { config } from "./config";
import { RelayError, statusFor } from "./errors";
import { fakeModel } from "./fake";
import { firestoreLedger } from "./ledger";
import { log } from "./log";
import { openAIModel } from "./model";
import { relay, type Relay } from "./service";

initializeApp();

/** The image model's key: in Secret Manager, read only here, never logged. */
const openAIKey = defineSecret("OPENAI_API_KEY");

/** The whole project stops drawing for the day past this many dollars. */
const dailyCeiling = defineString("DAILY_SPEND_CEILING_DOLLARS", {
  default: String(config.cost.defaultDailyCeiling),
  description: "The most the relay may spend on drawings in one UTC day, in US dollars.",
});

const emulated = process.env.FUNCTIONS_EMULATOR === "true";

const options: CallableOptions = {
  region: config.deploy.region,
  timeoutSeconds: config.deploy.timeoutSeconds,
  memory: config.deploy.memory,
  concurrency: config.deploy.concurrency,
  minInstances: config.deploy.minInstances,
  maxInstances: config.deploy.maxInstances,
  // Only a genuine copy of the app, on a real device, may call.
  enforceAppCheck: true,
  // Each token is good for one call, so a captured one cannot be replayed. The emulator
  // has no App Check service to spend a token with.
  consumeAppCheckToken: !emulated,
  cors: false,
};

let made: Relay | undefined;

/** One relay per instance, made on first use, when the secret can be read. */
function theRelay(): Relay {
  if (made) return made;
  const ceiling = Number.parseFloat(dailyCeiling.value());
  made = relay({
    // The emulator never draws for real: no key, no cost.
    model: emulated ? fakeModel() : openAIModel(() => openAIKey.value()),
    ledger: firestoreLedger(getFirestore()),
    log,
    now: () => new Date(),
    dailyCeiling: Number.isFinite(ceiling) && ceiling >= 0 ? ceiling : config.cost.defaultDailyCeiling,
  });
  return made;
}

/** Runs a call and turns its failure into the contract's codes; nothing else gets out. */
async function answered<T>(name: string, work: () => Promise<T>): Promise<T> {
  try {
    return await work();
  } catch (error) {
    const failure = error instanceof RelayError ? error : new RelayError("unavailable", "internal");
    if (!(error instanceof RelayError)) log.error(`${name} failed`, { errorClass: "internal" });
    else if (failure.code === "invalid") log.warn(`${name} refused its input`, { errorClass: "invalid", reason: failure.reason });
    throw new HttpsError(statusFor[failure.code], failure.code, { code: failure.code });
  }
}

export const drawCharacter = onCall({ ...options, secrets: [openAIKey] }, (request: CallableRequest) =>
  answered("drawCharacter", () => theRelay().draw(request.data, { installationId: request.auth?.uid })),
);

export const characterAllowance = onCall({ ...options, timeoutSeconds: 30, memory: "256MiB" }, (request: CallableRequest) =>
  answered("characterAllowance", () => theRelay().allowance(request.data)),
);
