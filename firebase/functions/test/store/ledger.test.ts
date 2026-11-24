import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { beforeAll, describe, expect, it, vi } from "vitest";

import { config, moods, type Mood, type Step } from "../../src/config";
import { hashed } from "../../src/contract";
import { RelayError } from "../../src/errors";
import { fakeModel } from "../../src/fake";
import { firestoreLedger, type Claim, type Ledger } from "../../src/ledger";
import { relay } from "../../src/service";
import { memoryLog, newDay, newId, pngBase64, strings } from "../support";

/**
 * The limits, against a real Firestore (the emulator): every rule is a transaction, so
 * it is tested where transactions really run, with calls arriving at the same moment.
 * Run through `npm test`, which starts the emulator.
 */
// Calls that arrive together wait on each other inside the emulator.
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
  return { household: newId(), companion: newId(), step: "tries", day: newDay(), estimate: 0.09, ceiling: 1000, ...overrides };
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

const count = (results: string[], value: string) => results.filter((result) => result === value).length;

async function spent(day: string): Promise<number> {
  return ((await db.collection("spend").doc(day).get()).get("micro") as number | undefined) ?? 0;
}

describe("rounds of tries", () => {
  it("are three for a companion, for life, and count down", async () => {
    const base = claim();
    expect(await ledger.roundsLeft(base.household, base.companion)).toBe(3);
    expect((await ledger.reserve(base)).roundsLeft).toBe(2);
    expect((await ledger.reserve({ ...base, day: newDay() })).roundsLeft).toBe(1);
    expect((await ledger.reserve({ ...base, day: newDay() })).roundsLeft).toBe(0);
    expect(await outcome(ledger.reserve({ ...base, day: newDay() }))).toBe("limit-reached: rounds");
    expect(await ledger.roundsLeft(base.household, base.companion)).toBe(0);
  });

  it("are never more than three, however many calls arrive at once", async () => {
    const base = claim();
    const results = await Promise.all(Array.from({ length: 8 }, () => outcome(ledger.reserve(base))));
    expect(count(results, "ok")).toBe(3);
    expect(count(results, "limit-reached: rounds")).toBe(5);
    expect(await ledger.roundsLeft(base.household, base.companion)).toBe(0);
  });

  it("come back when the drawing failed", async () => {
    const base = claim();
    const first = await ledger.reserve(base);
    await ledger.reserve(base);
    await ledger.release(first);
    expect(await ledger.roundsLeft(base.household, base.companion)).toBe(2);
  });

  it("belong to one companion: another has its own", async () => {
    const base = claim();
    for (let round = 0; round < 3; round += 1) await ledger.reserve(base);
    expect((await ledger.reserve({ ...base, companion: newId() })).roundsLeft).toBe(2);
  });
});

describe("moods and animations", () => {
  it("may each be drawn three times per mood, each mood on its own", async () => {
    for (const step of ["mood", "animation"] as Step[]) {
      const base = claim({ step, mood: "waiting" });
      for (let draw = 0; draw < 3; draw += 1) expect(await outcome(ledger.reserve(base))).toBe("ok");
      expect(await outcome(ledger.reserve(base))).toBe(`limit-reached: ${step}`);
      expect(await outcome(ledger.reserve({ ...base, mood: "asleep" }))).toBe("ok");
    }
  });

  it("do not use up rounds, nor rounds them", async () => {
    const base = claim({ step: "mood", mood: "fine" });
    for (let draw = 0; draw < 3; draw += 1) await ledger.reserve(base);
    expect(await ledger.roundsLeft(base.household, base.companion)).toBe(3);
    expect(await outcome(ledger.reserve({ ...base, step: "animation" }))).toBe("ok");
    expect(await outcome(ledger.reserve({ ...base, step: "tries", mood: undefined }))).toBe("ok");
  });

  it("hold at three when calls arrive at once", async () => {
    const base = claim({ step: "animation", mood: "zoomies" });
    const results = await Promise.all(Array.from({ length: 7 }, () => outcome(ledger.reserve(base))));
    expect(count(results, "ok")).toBe(3);
  });
});

describe("companions in a household", () => {
  it("are six at most", async () => {
    const base = claim();
    expect(await outcome(ledger.reserve(base))).toBe("ok");
    for (let pet = 0; pet < 5; pet += 1) expect(await outcome(ledger.reserve({ ...base, companion: newId() }))).toBe("ok");
    expect(await outcome(ledger.reserve({ ...base, companion: newId() }))).toBe("limit-reached: companions");
    // One already counted still draws.
    expect(await outcome(ledger.reserve(base))).toBe("ok");
  });

  it("are six at most when nine arrive at once", async () => {
    const base = claim();
    const results = await Promise.all(Array.from({ length: 9 }, () => outcome(ledger.reserve({ ...base, companion: newId() }))));
    expect(count(results, "ok")).toBe(6);
    expect(count(results, "limit-reached: companions")).toBe(3);
  });

  it("give their place back when nothing was ever drawn for them", async () => {
    const base = claim();
    const failed = await ledger.reserve(base);
    await ledger.release(failed);
    for (let pet = 0; pet < 6; pet += 1) expect(await outcome(ledger.reserve({ ...base, companion: newId() }))).toBe("ok");
  });

  it("keep their place once something was drawn", async () => {
    const base = claim();
    await ledger.reserve(base);
    const failed = await ledger.reserve({ ...base, step: "mood", mood: "fine" });
    await ledger.release(failed);
    for (let pet = 0; pet < 5; pet += 1) expect(await outcome(ledger.reserve({ ...base, companion: newId() }))).toBe("ok");
    expect(await outcome(ledger.reserve({ ...base, companion: newId() }))).toBe("limit-reached: companions");
  });
});

/** Every call one companion may ever make: 3 rounds, 12 moods, 12 animations. */
function everything(base: Claim): Claim[] {
  const claims: Claim[] = [];
  for (let draw = 0; draw < 3; draw += 1) {
    claims.push({ ...base, step: "tries", mood: undefined });
    for (const mood of moods as readonly Mood[]) claims.push({ ...base, step: "mood", mood }, { ...base, step: "animation", mood });
  }
  return claims;
}

describe("calls in a day", () => {
  it("stop at the household's ceiling, and start again the next day", async () => {
    const base = claim();
    const calls = [...everything(base), ...everything({ ...base, companion: newId() })];
    expect(calls.length).toBeGreaterThan(config.limits.callsPerHouseholdPerDay);
    const results: string[] = [];
    for (const call of calls) results.push(await outcome(ledger.reserve(call)));
    expect(count(results, "ok")).toBe(config.limits.callsPerHouseholdPerDay);
    expect(results[config.limits.callsPerHouseholdPerDay]).toBe("limit-reached: household day");
    const next = calls[config.limits.callsPerHouseholdPerDay]!;
    expect(await outcome(ledger.reserve({ ...next, day: newDay() }))).toBe("ok");
  });

  it("stop at the installation's ceiling, across households", async () => {
    const installation = newId();
    const day = newDay();
    const results: string[] = [];
    // Two households from one installation: each is under its own ceiling.
    for (const household of [newId(), newId()]) {
      for (const call of everything(claim({ household, installation, day })).slice(0, 21)) results.push(await outcome(ledger.reserve(call)));
    }
    expect(count(results, "ok")).toBe(config.limits.callsPerInstallationPerDay);
    expect(count(results, "limit-reached: installation day")).toBe(2);
  });

  it("count a call that failed too: the ceiling is against a runaway app", async () => {
    const base = claim();
    const failed = await ledger.reserve(base);
    await ledger.release(failed);
    const day = await db.collection("households").doc(base.household).collection("days").doc(base.day).get();
    expect(day.get("calls")).toBe(1);
  });
});

describe("the day's spending", () => {
  it("stops the project at its ceiling, as unavailable", async () => {
    const day = newDay();
    const make = () => claim({ day, estimate: 0.09, ceiling: 0.2 });
    expect(await outcome(ledger.reserve(make()))).toBe("ok");
    expect(await outcome(ledger.reserve(make()))).toBe("ok");
    expect(await outcome(ledger.reserve(make()))).toBe("unavailable: spend ceiling");
    expect(await spent(day)).toBe(180_000);
  });

  it("holds when calls from many households arrive at once", async () => {
    const day = newDay();
    const results = await Promise.all(Array.from({ length: 10 }, () => outcome(ledger.reserve(claim({ day, estimate: 0.09, ceiling: 0.4 })))));
    expect(count(results, "ok")).toBe(4);
    expect(count(results, "unavailable: spend ceiling")).toBe(6);
    expect(await spent(day)).toBe(360_000);
  });

  it("takes the real cost in place of the estimate, and gives a failed call's estimate back", async () => {
    const day = newDay();
    const first = await ledger.reserve(claim({ day, estimate: 0.09 }));
    await ledger.settle(first, 0.131);
    expect(await spent(day)).toBe(131_000);
    const second = await ledger.reserve(claim({ day, estimate: 0.06 }));
    expect(await spent(day)).toBe(191_000);
    await ledger.release(second);
    expect(await spent(day)).toBe(131_000);
  });

  it("uses nothing of a companion when the ceiling turns the call down", async () => {
    const day = newDay();
    const base = claim({ day, estimate: 0.09, ceiling: 0.05 });
    expect(await outcome(ledger.reserve(base))).toBe("unavailable: spend ceiling");
    expect(await ledger.roundsLeft(base.household, base.companion)).toBe(3);
  });
});

describe("the whole relay on a real ledger", () => {
  async function draw(options: { failure?: () => Error | undefined; delayMs?: number } = {}) {
    const service = relay({ model: fakeModel(options), ledger, log: memoryLog(), now: () => new Date(), dailyCeiling: 1000 });
    const ids = { householdId: newId(), companionId: newId() };
    const cutout = await pngBase64();
    return { service, ids, request: { ...ids, species: "dog", step: "tries", cutout } };
  }

  it("does not use a round on a drawing that failed or was refused", async () => {
    for (const code of ["refused", "unavailable"] as const) {
      const { service, ids, request } = await draw({ failure: () => new RelayError(code, "model") });
      expect(await outcome(service.draw(request, {}))).toBe(`${code}: model`);
      expect(await service.allowance(ids)).toEqual({ roundsLeft: 3 });
    }
  });

  it("gives three rounds and no more when five drawings overlap", async () => {
    const { service, ids, request } = await draw({ delayMs: 150 });
    const results = await Promise.all(Array.from({ length: 5 }, () => outcome(service.draw(request, {}))));
    expect(count(results, "ok")).toBe(3);
    expect(count(results, "limit-reached: rounds")).toBe(2);
    expect(await service.allowance(ids)).toEqual({ roundsLeft: 0 });
  });

  it("keeps counters under hashed ids, and no picture, no id, no name", async () => {
    const { service, ids, request } = await draw();
    const response = await service.draw(request, { installationId: "installation-7" });
    if (!("images" in response)) throw new Error("expected images");
    const household = hashed("household", ids.householdId);
    const home = db.collection("households").doc(household);
    const docs = [
      await home.get(),
      ...(await home.collection("companions").get()).docs,
      ...(await home.collection("days").get()).docs,
      ...(await db.collection("installations").doc(hashed("installation", "installation-7")).collection("days").get()).docs,
    ];
    expect(docs.length).toBeGreaterThanOrEqual(4);
    const kept = strings(docs.map((doc) => ({ id: doc.id, data: doc.data() })));
    for (const text of kept) expect(text.length).toBeLessThanOrEqual(40);
    const all = kept.join(" ");
    for (const secret of [ids.householdId, ids.companionId, "installation-7", request.cutout.slice(0, 40), response.images[0]!.slice(0, 40)]) {
      expect(all).not.toContain(secret);
    }
    expect((await home.collection("companions").doc(hashed("companion", ids.companionId)).get()).data()).toEqual({ rounds: 1, moods: {}, animations: {} });
  });
});
