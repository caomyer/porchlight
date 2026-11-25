import { readFileSync } from "node:fs";
import { join } from "node:path";

import { beforeAll, describe, expect, it, vi } from "vitest";

import { config } from "../../src/config";
import { gifFrames, pngSize } from "../../src/images";
import { newId, pngBase64 } from "../support";

/**
 * The two callables as an app reaches them, over HTTP, in the functions emulator, where
 * the image model is a stand-in. Run through `npm test`, which starts the emulators.
 *
 * What the emulator can show about App Check: a call with no token is turned away. It
 * accepts any token without verifying it, so a forged token being refused is Firebase's
 * own behaviour in production and is not something these tests can see.
 */
vi.setConfig({ testTimeout: 90_000 });

const ports = JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "firebase.json"), "utf8")).emulators;
const base = `http://127.0.0.1:${ports.functions.port}/demo-porchlight/${config.deploy.region}`;
const withToken = { "X-Firebase-AppCheck": "a-token-the-emulator-does-not-verify" };

interface Answer {
  status: number;
  result?: Record<string, unknown>;
  error?: { status: string; message: string; details?: { code?: string; reason?: string } };
}

async function call(name: string, data: unknown, headers: Record<string, string> = withToken): Promise<Answer> {
  const response = await fetch(`${base}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify({ data }),
  });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: Answer["error"] };
  return { status: response.status, result: body.result, error: body.error };
}

let cutout: string;
beforeAll(async () => {
  if (!process.env.FUNCTIONS_EMULATOR_HOST && !process.env.FIREBASE_EMULATOR_HUB) {
    throw new Error("These tests need the functions emulator: run `npm test`.");
  }
  cutout = await pngBase64(512, 512);
});

const ids = () => ({ householdId: newId(), companionId: newId() });

describe("App Check", () => {
  it("turns away a call with no token, before anything else is looked at", async () => {
    for (const name of ["drawCharacter", "characterAllowance"]) {
      const answer = await call(name, { ...ids(), species: "dog", step: "tries", cutout }, {});
      expect(answer.status).toBe(401);
      expect(answer.error?.status).toBe("UNAUTHENTICATED");
      expect(answer.result).toBeUndefined();
    }
  });

  it("lets a call with a token through", async () => {
    const answer = await call("characterAllowance", ids());
    expect(answer.status).toBe(200);
    expect(answer.result).toEqual({ roundsLeft: 3 });
  });
});

describe("drawCharacter", () => {
  it("draws three tries, then a mood, then its animation", async () => {
    const pet = ids();
    const tries = await call("drawCharacter", { ...pet, species: "dog", step: "tries", cutout });
    expect(tries.status).toBe(200);
    const images = tries.result?.images as string[];
    expect(images).toHaveLength(3);
    expect(pngSize(Buffer.from(images[0]!, "base64"))).toEqual({ width: 512, height: 512 });
    expect(tries.result?.roundsLeft).toBe(2);

    const mood = await call("drawCharacter", { ...pet, species: "dog", step: "mood", mood: "waiting", cutout, reference: images[0] });
    expect(mood.status).toBe(200);
    expect(pngSize(Buffer.from(mood.result?.image as string, "base64"))).toEqual({ width: 512, height: 512 });

    const animation = await call("drawCharacter", { ...pet, species: "dog", step: "animation", mood: "waiting", cutout, reference: mood.result?.image });
    expect(animation.status).toBe(200);
    expect(animation.result?.frames).toBe(9);
    expect(gifFrames(Buffer.from(animation.result?.gif as string, "base64"))).toBe(9);

    expect((await call("characterAllowance", pet)).result).toEqual({ roundsLeft: 2 });
  });

  it("draws an animation from the still alone, with no cut-out sent, and counts it", async () => {
    const pet = ids();
    const still = await pngBase64(512, 512);
    for (let draw = 0; draw < 3; draw += 1) {
      const animation = await call("drawCharacter", { ...pet, species: "cat", step: "animation", mood: "asleep", reference: still });
      expect(animation.status).toBe(200);
      expect(animation.result?.frames).toBe(9);
      expect(gifFrames(Buffer.from(animation.result?.gif as string, "base64"))).toBe(9);
    }
    // The same limit as with a cut-out: three draws of one mood's animation.
    const fourth = await call("drawCharacter", { ...pet, species: "cat", step: "animation", mood: "asleep", reference: still });
    expect(fourth.error?.details).toEqual({ code: "limit-reached", reason: "animation-redraws" });
    // A mood and the tries still need theirs.
    const mood = await call("drawCharacter", { ...pet, species: "cat", step: "mood", mood: "asleep", reference: still });
    expect(mood.error?.details).toEqual({ code: "invalid" });
    const tries = await call("drawCharacter", { ...pet, species: "cat", step: "tries" });
    expect(tries.error?.details).toEqual({ code: "invalid" });
  });

  it("says limit-reached and why, in details, after the third round", async () => {
    const pet = ids();
    for (let round = 0; round < 3; round += 1) {
      expect((await call("drawCharacter", { ...pet, species: "cat", step: "tries", cutout })).status).toBe(200);
    }
    const fourth = await call("drawCharacter", { ...pet, species: "cat", step: "tries", cutout });
    expect(fourth.status).toBe(429);
    expect(fourth.error?.status).toBe("RESOURCE_EXHAUSTED");
    expect(fourth.error?.details).toEqual({ code: "limit-reached", reason: "rounds" });
    expect((await call("characterAllowance", pet)).result).toEqual({ roundsLeft: 0 });
  });

  it("refuses input outside the contract, and says nothing of why beyond its code", async () => {
    const answer = await call("drawCharacter", { ...ids(), species: "dog", step: "tries", cutout, prompt: "a dragon" });
    expect(answer.status).toBe(400);
    expect(answer.error?.status).toBe("INVALID_ARGUMENT");
    expect(answer.error?.details).toEqual({ code: "invalid" });
    expect(answer.error?.message).toBe("invalid");
  });
});
