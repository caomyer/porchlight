import { beforeAll, describe, expect, it } from "vitest";

import { config } from "../../src/config";
import { hashed, parseAllowance, parseDraw } from "../../src/contract";
import { RelayError } from "../../src/errors";
import { newId, png, pngBase64 } from "../support";

async function tries(overrides: Record<string, unknown> = {}) {
  return { householdId: newId(), companionId: newId(), species: "dog", step: "tries", cutout: await pngBase64(), ...overrides };
}

function invalid(work: () => unknown, reason?: string) {
  try {
    work();
  } catch (error) {
    expect(error).toBeInstanceOf(RelayError);
    expect((error as RelayError).code).toBe("invalid");
    if (reason) expect((error as RelayError).reason).toContain(reason);
    return;
  }
  throw new Error("expected the input to be refused");
}

describe("a draw request", () => {
  let base: Awaited<ReturnType<typeof tries>>;
  let big: string;
  let tiny: string;

  // Built once: making the images is the slow part.
  beforeAll(async () => {
    base = await tries();
    big = (await png(1040, 16)).toString("base64");
    tiny = (await png(32, 32)).toString("base64");
  });

  it("is taken when it is well formed", async () => {
    const request = parseDraw(await tries());
    expect(request.step).toBe("tries");
    expect(request.cutout.length).toBeGreaterThan(0);
    expect(request.mood).toBeUndefined();
  });

  it("keeps ids in lower case, so one household is one household", async () => {
    const id = newId();
    const request = parseDraw(await tries({ householdId: id.toUpperCase() }));
    expect(request.householdId).toBe(id);
  });

  it("needs a mood and a reference for a mood and for an animation", async () => {
    for (const step of ["mood", "animation"]) {
      invalid(() => parseDraw({ ...base, step }), "mood");
      invalid(() => parseDraw({ ...base, step, mood: "asleep" }), "reference");
      const request = parseDraw({ ...base, step, mood: "asleep", reference: base.cutout });
      expect(request.mood).toBe("asleep");
      expect(request.reference?.length).toBeGreaterThan(0);
    }
  });

  it("takes no mood and no reference for tries", async () => {
    invalid(() => parseDraw({ ...base, mood: "fine" }), "mood given");
    invalid(() => parseDraw({ ...base, reference: base.cutout }), "reference given");
  });

  it("refuses values outside the contract", async () => {
    invalid(() => parseDraw({ ...base, species: "rabbit" }), "species");
    invalid(() => parseDraw({ ...base, step: "paint" }), "step");
    invalid(() => parseDraw({ ...base, step: "mood", mood: "angry", reference: base.cutout }), "mood");
    invalid(() => parseDraw({ ...base, householdId: "household-1" }), "householdId");
    invalid(() => parseDraw({ ...base, companionId: 12 }), "companionId");
    invalid(() => parseDraw(null));
    invalid(() => parseDraw([base]));
    invalid(() => parseDraw("tries"));
  });

  it("refuses words of its own: a client cannot send a prompt", async () => {
    invalid(() => parseDraw({ ...base, prompt: "draw a dragon" }), "unknown field");
    invalid(() => parseDraw({ ...base, model: "another" }), "unknown field");
  });

  it("refuses an image that is not a PNG of the agreed size", async () => {
    invalid(() => parseDraw({ ...base, cutout: undefined }), "cutout missing");
    invalid(() => parseDraw({ ...base, cutout: "" }), "cutout missing");
    invalid(() => parseDraw({ ...base, cutout: "not base64!" }), "not base64");
    invalid(() => parseDraw({ ...base, cutout: Buffer.from("just some text, long enough to look at").toString("base64") }), "not a PNG");
    const jpegStart = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64)]).toString("base64");
    invalid(() => parseDraw({ ...base, cutout: jpegStart }), "not a PNG");
    invalid(() => parseDraw({ ...base, cutout: big }), "size");
    invalid(() => parseDraw({ ...base, cutout: tiny }), "size");
    invalid(() => parseDraw({ ...base, cutout: "A".repeat(config.input.maxBase64Length + 4) }), "too long");
  });

  it("takes a cut-out that is not square, up to the longest side", async () => {
    const wide = (await png(1024, 300)).toString("base64");
    expect(parseDraw({ ...base, cutout: wide }).cutout.length).toBeGreaterThan(0);
  });

});

describe("an allowance request", () => {
  it("takes two ids and nothing else", () => {
    const ids = { householdId: newId(), companionId: newId() };
    expect(parseAllowance(ids)).toEqual(ids);
    invalid(() => parseAllowance({ ...ids, extra: 1 }), "unknown field");
    invalid(() => parseAllowance({ householdId: ids.householdId }), "companionId");
  });
});

describe("a hashed id", () => {
  it("is steady, differs by kind, and does not contain the id", () => {
    const id = newId();
    expect(hashed("household", id)).toBe(hashed("household", id));
    expect(hashed("household", id)).not.toBe(hashed("companion", id));
    expect(hashed("household", id)).not.toContain(id.slice(0, 8));
    expect(hashed("household", id)).toMatch(/^[0-9a-f]{32}$/);
  });
});
