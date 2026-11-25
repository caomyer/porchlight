import { beforeAll, describe, expect, it } from "vitest";

import { config } from "../../src/config";
import { hashed, parseDraw } from "../../src/contract";
import { RelayError } from "../../src/errors";
import { fakeModel } from "../../src/fake";
import { gifFrames } from "../../src/images";
import type { ModelRequest } from "../../src/model";
import { promptFor } from "../../src/prompts";
import { relay } from "../../src/service";
import { memoryLog, newId, openLedger, png, pngBase64 } from "../support";

/**
 * An animation is drawn from its mood's still alone. The app does not keep the cut-out
 * once a character is saved, so an animation may be asked for without one; a build that
 * still sends one is treated exactly as before.
 */
let cutout: string;
let reference: string;
beforeAll(async () => {
  cutout = await pngBase64(640, 512);
  reference = await pngBase64(512, 512);
});

const ids = () => ({ householdId: newId(), companionId: newId() });

function refused(work: () => unknown, reason: string) {
  try {
    work();
  } catch (error) {
    expect(error).toBeInstanceOf(RelayError);
    expect((error as RelayError).code).toBe("invalid");
    expect((error as RelayError).reason).toContain(reason);
    return;
  }
  throw new Error("expected the input to be refused");
}

describe("an animation request's cut-out", () => {
  const animation = () => ({ ...ids(), species: "dog", step: "animation", mood: "waiting", reference });

  it("may be left out, or sent as nothing", () => {
    for (const body of [animation(), { ...animation(), cutout: undefined }, { ...animation(), cutout: null }]) {
      const request = parseDraw(body);
      expect(request.cutout).toBeUndefined();
      expect(request.reference?.length).toBeGreaterThan(0);
      expect(request.mood).toBe("waiting");
    }
  });

  it("is taken as before when it is sent", () => {
    const request = parseDraw({ ...animation(), cutout });
    expect(request.cutout?.equals(Buffer.from(cutout, "base64"))).toBe(true);
  });

  it("is still checked when it is sent: a bad one is refused, not ignored", async () => {
    refused(() => parseDraw({ ...animation(), cutout: "" }), "cutout missing");
    refused(() => parseDraw({ ...animation(), cutout: "not base64!" }), "not base64");
    refused(() => parseDraw({ ...animation(), cutout: Buffer.from("some text that is plainly not a picture at all").toString("base64") }), "not a PNG");
    const tooLong = (await png(1040, 16)).toString("base64");
    refused(() => parseDraw({ ...animation(), cutout: tooLong }), "size");
    refused(() => parseDraw({ ...animation(), cutout: 12 }), "cutout missing");
  });

  it("does not excuse the still or the mood", () => {
    refused(() => parseDraw({ ...ids(), species: "dog", step: "animation", mood: "waiting" }), "reference");
    refused(() => parseDraw({ ...ids(), species: "dog", step: "animation", reference }), "mood");
    refused(() => parseDraw({ ...animation(), reference: "not base64!" }), "not base64");
  });
});

describe("the other steps' cut-out", () => {
  it("is still required for tries and for a mood", () => {
    for (const absent of [{}, { cutout: undefined }, { cutout: null }]) {
      refused(() => parseDraw({ ...ids(), species: "dog", step: "tries", ...absent }), "cutout missing");
      refused(() => parseDraw({ ...ids(), species: "dog", step: "mood", mood: "asleep", reference, ...absent }), "cutout missing");
    }
  });
});

describe("drawing an animation from the still alone", () => {
  function made() {
    const seen: ModelRequest[] = [];
    const log = memoryLog();
    const { ledger, calls } = openLedger();
    const service = relay({
      model: fakeModel({ seen: (request) => seen.push(request) }), ledger, log,
      now: () => new Date("2026-11-24T10:30:00Z"), dailyCeiling: 5, enforceLifetimeLimits: true,
    });
    return { service, seen, log, calls };
  }

  it("asks the model the same thing, counts the same and logs the same, with or without a cut-out", async () => {
    const pet = ids();
    const base = { ...pet, species: "cat", step: "animation", mood: "asleep", reference };
    const without = made();
    const withCutout = made();
    const first = await without.service.draw(base, { installationId: "installation-1" });
    const second = await withCutout.service.draw({ ...base, cutout }, { installationId: "installation-1" });

    for (const response of [first, second]) {
      if (!("gif" in response)) throw new Error("expected a gif");
      expect(response.frames).toBe(9);
      expect(gifFrames(Buffer.from(response.gif, "base64"))).toBe(9);
    }

    // The model is given the still and nothing else, either way.
    for (const { seen } of [without, withCutout]) {
      expect(seen).toHaveLength(1);
      expect(seen[0]).toMatchObject({
        count: 1, quality: "medium", format: "gif", size: config.model.animationSize, prompt: promptFor("animation", "cat", "asleep"),
        safetyIdentifier: hashed("household", pet.householdId),
      });
      expect(seen[0]!.images).toHaveLength(1);
      expect(seen[0]!.images[0]!.equals(Buffer.from(reference, "base64"))).toBe(true);
    }

    // The limits are asked for the same claim, and the same cost is settled.
    expect(without.calls.reserved).toEqual(withCutout.calls.reserved);
    expect(without.calls.reserved[0]).toMatchObject({
      step: "animation", mood: "asleep", estimate: config.cost.estimate.animation,
      household: hashed("household", pet.householdId), companion: hashed("companion", pet.companionId),
      installation: hashed("installation", "installation-1"),
    });
    expect(without.calls.settled[0]!.dollars).toBe(withCutout.calls.settled[0]!.dollars);
    expect(without.calls.released).toHaveLength(0);

    // And the log line names the same things.
    const fields = (entries: typeof without.log.entries) => {
      // Everything but how long it took.
      const rest = { ...entries.find((entry) => entry.event === "drew")!.fields };
      delete rest.ms;
      return rest;
    };
    expect(fields(without.log.entries)).toEqual(fields(withCutout.log.entries));
    expect(fields(without.log.entries)).toMatchObject({ step: "animation", mood: "asleep", species: "cat", attempts: 1 });
  });

  it("gives the redraw back when the drawing fails, as it does with a cut-out", async () => {
    const { ledger, calls } = openLedger();
    const service = relay({
      model: fakeModel({ failure: () => new RelayError("unavailable", "model status 503", "model") }), ledger, log: memoryLog(),
      now: () => new Date(), dailyCeiling: 5, enforceLifetimeLimits: true,
    });
    await expect(service.draw({ ...ids(), species: "dog", step: "animation", mood: "fine", reference }, {})).rejects.toMatchObject({ code: "unavailable" });
    expect(calls.released).toHaveLength(1);
    expect(calls.settled).toHaveLength(0);
  });
});
