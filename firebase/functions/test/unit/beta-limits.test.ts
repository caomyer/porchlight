import { beforeAll, describe, expect, it } from "vitest";

import { config } from "../../src/config";
import { fakeModel } from "../../src/fake";
import { reportedRounds } from "../../src/ledger";
import { safe } from "../../src/log";
import { relay } from "../../src/service";
import { enforced } from "../../src/settings";
import { memoryLog, newId, openLedger, pngBase64 } from "../support";

/**
 * During beta testing the three lifetime limits are counted and not enforced. These are
 * the rules that do not need a database; the counting itself is in test/store.
 */
let cutout: string;
beforeAll(async () => {
  cutout = await pngBase64();
});

describe("the switch", () => {
  it("is off unless it says true, and a slip is the default, not a guess", () => {
    expect(config.limits.enforceLifetimeByDefault).toBe(false);
    expect(enforced("true")).toBe(true);
    expect(enforced(" TRUE ")).toBe(true);
    expect(enforced("false")).toBe(false);
    expect(enforced("False")).toBe(false);
    for (const slip of [undefined, "", "yes", "1", "on", "treu"]) expect(enforced(slip)).toBe(config.limits.enforceLifetimeByDefault);
  });
});

describe("the rounds the app is told", () => {
  it("count down to 0 when the limit is enforced", () => {
    expect([0, 1, 2, 3, 4, 9].map((used) => reportedRounds(used, true))).toEqual([3, 2, 1, 0, 0, 0]);
  });

  it("never fall below 1 when it is not, so the app goes on offering a new character", () => {
    expect([0, 1, 2, 3, 4, 9].map((used) => reportedRounds(used, false))).toEqual([3, 2, 1, 1, 1, 1]);
  });
});

describe("a draw past a limit that is not enforced", () => {
  function made(options: { over?: "rounds" | "mood-redraws" | "animation-redraws"; enforce: boolean; roundsLeft?: number }) {
    const log = memoryLog();
    const { ledger, calls } = openLedger({ over: options.over, roundsLeft: options.roundsLeft });
    const service = relay({ model: fakeModel(), ledger, log, now: () => new Date(), dailyCeiling: 5, enforceLifetimeLimits: options.enforce });
    return { service, log, calls };
  }
  const tries = () => ({ householdId: newId(), companionId: newId(), species: "dog", step: "tries", cutout });

  it("is drawn, settled like any other, and logged as over the limit with the limit's name", async () => {
    const { service, log, calls } = made({ over: "rounds", enforce: false, roundsLeft: 1 });
    const response = await service.draw(tries(), {});
    if (!("images" in response)) throw new Error("expected images");
    expect(response.images).toHaveLength(3);
    expect(response.roundsLeft).toBe(1);
    expect(calls.settled).toHaveLength(1);
    expect(calls.released).toHaveLength(0);
    const drew = log.entries.find((entry) => entry.event === "drew")!;
    expect(drew.fields).toMatchObject({ overLimit: true, limit: "rounds", step: "tries" });
    // And it survives into what is written: a true stays a true.
    expect(safe(drew.fields)).toMatchObject({ overLimit: true, limit: "rounds" });
  });

  it("says nothing of a limit when the call is within it", async () => {
    const { service, log } = made({ enforce: false });
    await service.draw(tries(), {});
    const drew = log.entries.find((entry) => entry.event === "drew")!;
    expect(drew.fields.overLimit).toBeUndefined();
    expect(drew.fields.limit).toBeUndefined();
    expect(safe(drew.fields)).not.toHaveProperty("overLimit");
  });

  it("tells the ledger which way the switch is set, for the draw and for the allowance", async () => {
    for (const enforce of [true, false]) {
      const { service, calls } = made({ enforce });
      await service.draw(tries(), {});
      expect(calls.reserved[0]!.enforceLifetime).toBe(enforce);
    }
  });
});
