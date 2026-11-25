import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { beforeAll, describe, expect, it, vi } from "vitest";

import { config, moods, type Mood } from "../../src/config";
import { hashed } from "../../src/contract";
import { RelayError } from "../../src/errors";
import { fakeModel } from "../../src/fake";
import { firestoreLedger, type Claim, type Ledger } from "../../src/ledger";
import { relay } from "../../src/service";
import { memoryLog, newDay, newId, pngBase64 } from "../support";

/**
 * Beta testing: the three lifetime limits (rounds of tries, mood redraws, animation
 * redraws) are counted and not enforced. Against a real Firestore (the emulator), with
 * the switch off, and then the same counts read with it on.
 */
vi.setConfig({ testTimeout: 90_000 });

let db: Firestore;
let ledger: Ledger;

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("These tests need the Firestore emulator: run `npm test`.");
  if (getApps().length === 0) initializeApp({ projectId: "demo-porchlight" });
  db = getFirestore();
  ledger = firestoreLedger(db);
});

function claim(overrides: Partial<Claim> = {}): Claim {
  return { household: newId(), companion: newId(), step: "tries", day: newDay(), estimate: 0.09, ceiling: 1000, enforceLifetime: false, ...overrides };
}

async function outcome(work: Promise<unknown>): Promise<string> {
  try {
    await work;
    return "ok";
  } catch (error) {
    if (error instanceof RelayError) return `${error.code}: ${error.reason}`;
    throw error;
  }
}

const use = async (base: Claim) => (await db.collection("households").doc(base.household).collection("companions").doc(base.companion).get()).data();

describe("rounds of tries, counted and not enforced", () => {
  it("go on past three, each one counted, and the app is never told fewer than 1 left", async () => {
    const base = claim();
    const seen: { roundsLeft: number; over?: string }[] = [];
    for (let round = 0; round < 6; round += 1) {
      const reservation = await ledger.reserve({ ...base, day: newDay() });
      seen.push({ roundsLeft: reservation.roundsLeft, over: reservation.over });
    }
    expect(seen.map((entry) => entry.roundsLeft)).toEqual([2, 1, 1, 1, 1, 1]);
    // The third round is the last one within the limit; the fourth is the first past it.
    expect(seen.map((entry) => entry.over)).toEqual([undefined, undefined, undefined, "rounds", "rounds", "rounds"]);
    expect((await use(base))?.rounds).toBe(6);
    expect(await ledger.roundsLeft(base.household, base.companion, false)).toBe(1);
  });

  it("are enforced again, from the real count, the moment the switch is turned on", async () => {
    const base = claim();
    for (let round = 0; round < 5; round += 1) await ledger.reserve({ ...base, day: newDay() });
    expect(await ledger.roundsLeft(base.household, base.companion, true)).toBe(0);
    expect(await outcome(ledger.reserve({ ...base, day: newDay(), enforceLifetime: true }))).toBe("limit-reached: rounds");
    // And a companion that stayed within the limit is not affected by the change.
    const fresh = claim();
    await ledger.reserve(fresh);
    expect(await ledger.roundsLeft(fresh.household, fresh.companion, true)).toBe(2);
    expect(await outcome(ledger.reserve({ ...fresh, enforceLifetime: true }))).toBe("ok");
  });

  it("still come back when a drawing past the limit fails", async () => {
    const base = claim();
    for (let round = 0; round < 4; round += 1) await ledger.reserve({ ...base, day: newDay() });
    const failed = await ledger.reserve({ ...base, day: newDay() });
    expect((await use(base))?.rounds).toBe(5);
    await ledger.release(failed);
    expect((await use(base))?.rounds).toBe(4);
  });

  it("are all counted when eight calls arrive at once", async () => {
    const base = claim();
    const results = await Promise.all(Array.from({ length: 8 }, () => outcome(ledger.reserve(base))));
    expect(results.filter((result) => result === "ok")).toHaveLength(8);
    expect((await use(base))?.rounds).toBe(8);
  });
});

describe("mood and animation redraws, counted and not enforced", () => {
  it("go on past three for a mood, and say which limit was passed", async () => {
    for (const [step, limit] of [["mood", "mood-redraws"], ["animation", "animation-redraws"]] as const) {
      const base = claim({ step, mood: "waiting" });
      const over: (string | undefined)[] = [];
      for (let draw = 0; draw < 5; draw += 1) over.push((await ledger.reserve({ ...base, day: newDay() })).over);
      expect(over).toEqual([undefined, undefined, undefined, limit, limit]);
      const counted = (await use(base))?.[step === "mood" ? "moods" : "animations"] as Record<string, number>;
      expect(counted.waiting).toBe(5);
      // Another mood has its own count, and is within its limit.
      expect((await ledger.reserve({ ...base, mood: "asleep" })).over).toBeUndefined();
      // Enforced again, the mood that is past its limit is turned down and the other is not.
      expect(await outcome(ledger.reserve({ ...base, day: newDay(), enforceLifetime: true }))).toBe(`limit-reached: ${step}`);
      expect(await outcome(ledger.reserve({ ...base, day: newDay(), mood: "asleep", enforceLifetime: true }))).toBe("ok");
    }
  });
});

/** Every call one companion makes in three full characters: 3 rounds, 12 moods, 12 animations. */
function everything(base: Claim): Claim[] {
  const claims: Claim[] = [];
  for (let draw = 0; draw < 3; draw += 1) {
    claims.push({ ...base, step: "tries", mood: undefined });
    for (const mood of moods as readonly Mood[]) claims.push({ ...base, step: "mood", mood }, { ...base, step: "animation", mood });
  }
  return claims;
}

describe("what stays enforced with the switch off", () => {
  it("the household's calls in a day, even when every one of them is for one companion", async () => {
    const base = claim();
    const results: string[] = [];
    // One companion, round after round: nothing but the day's ceiling stands in the way.
    for (let call = 0; call < config.limits.callsPerHouseholdPerDay + 2; call += 1) results.push(await outcome(ledger.reserve(base)));
    expect(results.filter((result) => result === "ok")).toHaveLength(config.limits.callsPerHouseholdPerDay);
    expect(results.slice(-2)).toEqual(["limit-reached: household day", "limit-reached: household day"]);
    // The calls that were turned down were not counted as rounds.
    expect((await use(base))?.rounds).toBe(config.limits.callsPerHouseholdPerDay);
    expect(await outcome(ledger.reserve({ ...base, day: newDay() }))).toBe("ok");
  });

  it("the installation's calls in a day", async () => {
    const installation = newId();
    const day = newDay();
    const results: string[] = [];
    for (const household of [newId(), newId()]) {
      for (const call of everything(claim({ household, installation, day })).slice(0, 21)) results.push(await outcome(ledger.reserve(call)));
    }
    expect(results.filter((result) => result === "ok")).toHaveLength(config.limits.callsPerInstallationPerDay);
    expect(results.filter((result) => result === "limit-reached: installation day")).toHaveLength(2);
  });

  it("six companions in a household", async () => {
    const base = claim();
    for (let pet = 0; pet < 6; pet += 1) expect(await outcome(ledger.reserve({ ...base, companion: newId() }))).toBe("ok");
    expect(await outcome(ledger.reserve({ ...base, companion: newId() }))).toBe("limit-reached: companions");
  });

  it("the day's spending", async () => {
    const day = newDay();
    const make = () => claim({ day, estimate: 0.09, ceiling: 0.2 });
    expect(await outcome(ledger.reserve(make()))).toBe("ok");
    expect(await outcome(ledger.reserve(make()))).toBe("ok");
    expect(await outcome(ledger.reserve(make()))).toBe("unavailable: spend ceiling");
  });
});

describe("the whole relay with the switch off", () => {
  it("draws a fourth and a fifth round, logs them as over the limit, and reports 1 round left", async () => {
    const log = memoryLog();
    const service = relay({ model: fakeModel(), ledger, log, now: () => new Date(), dailyCeiling: 1000, enforceLifetimeLimits: false });
    const ids = { householdId: newId(), companionId: newId() };
    const request = { ...ids, species: "dog", step: "tries", cutout: await pngBase64() };
    const left: number[] = [];
    for (let round = 0; round < 5; round += 1) {
      const response = await service.draw(request, {});
      if (!("images" in response)) throw new Error("expected images");
      expect(response.images).toHaveLength(3);
      left.push(response.roundsLeft);
    }
    expect(left).toEqual([2, 1, 1, 1, 1]);
    expect(await service.allowance(ids)).toEqual({ roundsLeft: 1 });
    const drew = log.entries.filter((entry) => entry.event === "drew");
    expect(drew.map((entry) => entry.fields.overLimit)).toEqual([undefined, undefined, undefined, true, true]);
    expect(drew[3]!.fields).toMatchObject({ limit: "rounds", household: hashed("household", ids.householdId) });
    // The same companion, read by an enforcing relay: its real count stands.
    const enforcing = relay({ model: fakeModel(), ledger, log: memoryLog(), now: () => new Date(), dailyCeiling: 1000, enforceLifetimeLimits: true });
    expect(await enforcing.allowance(ids)).toEqual({ roundsLeft: 0 });
    await expect(enforcing.draw(request, {})).rejects.toMatchObject({ code: "limit-reached", shared: "rounds" });
  });

  it("reports 3 rounds left for a companion nothing was drawn for", async () => {
    const service = relay({ model: fakeModel(), ledger, log: memoryLog(), now: () => new Date(), dailyCeiling: 1000, enforceLifetimeLimits: false });
    expect(await service.allowance({ householdId: newId(), companionId: newId() })).toEqual({ roundsLeft: 3 });
  });
});
