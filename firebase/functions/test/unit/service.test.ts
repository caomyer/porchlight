import { beforeAll, describe, expect, it } from "vitest";

import { config } from "../../src/config";
import { hashed } from "../../src/contract";
import { details, RelayError } from "../../src/errors";
import { fakeModel } from "../../src/fake";
import { gifFrames, pngSize } from "../../src/images";
import { described, safe, scrubbed } from "../../src/log";
import type { ModelRequest } from "../../src/model";
import { promptFor } from "../../src/prompts";
import { relay } from "../../src/service";
import { memoryLog, newId, openLedger, pngBase64, strings } from "../support";

let cutout: string;
let reference: string;
beforeAll(async () => {
  cutout = await pngBase64(640, 512);
  reference = await pngBase64(512, 512);
});

const fixedNow = () => new Date("2026-11-24T10:30:00Z");

function made(options: { failure?: () => Error | undefined; reserve?: () => Error | undefined } = {}) {
  const seen: ModelRequest[] = [];
  const log = memoryLog();
  const { ledger, calls } = openLedger({ reserve: options.reserve });
  const service = relay({
    model: fakeModel({ seen: (request) => seen.push(request), failure: options.failure }),
    ledger, log, now: fixedNow, dailyCeiling: 5, enforceLifetimeLimits: true,
  });
  return { service, seen, log, calls };
}

const ids = () => ({ householdId: newId(), companionId: newId() });

async function failure(work: Promise<unknown>): Promise<RelayError> {
  try {
    await work;
  } catch (error) {
    expect(error).toBeInstanceOf(RelayError);
    return error as RelayError;
  }
  throw new Error("expected a failure");
}

describe("drawing the three tries", () => {
  it("returns three 512 PNGs and the rounds left, from the cut-out alone", async () => {
    const { service, seen, calls } = made();
    const response = await service.draw({ ...ids(), species: "dog", step: "tries", cutout }, {});
    if (!("images" in response)) throw new Error("expected images");
    expect(response.images).toHaveLength(3);
    for (const image of response.images) expect(pngSize(Buffer.from(image, "base64"))).toEqual({ width: 512, height: 512 });
    expect(response.roundsLeft).toBe(2);
    expect(seen[0]).toMatchObject({ count: 3, quality: "low", size: "1024x1024", format: "png", prompt: promptFor("tries", "dog", undefined) });
    expect(seen[0]!.images).toHaveLength(1);
    expect(calls.reserved[0]).toMatchObject({ step: "tries", day: "2026-11-24", estimate: config.cost.estimate.tries, ceiling: 5 });
  });

  it("settles what it really cost and gives nothing back", async () => {
    const { service, calls } = made();
    await service.draw({ ...ids(), species: "cat", step: "tries", cutout }, {});
    expect(calls.settled).toHaveLength(1);
    // 150 text, 768 image and 3 x 1400 output tokens.
    expect(calls.settled[0]!.dollars).toBeCloseTo((150 * 5 + 768 * 8 + 4200 * 30) / 1_000_000, 6);
    expect(calls.released).toHaveLength(0);
  });
});

describe("drawing a mood", () => {
  it("returns one 512 PNG, from the chosen character and the cut-out, at the better quality", async () => {
    const { service, seen } = made();
    const response = await service.draw({ ...ids(), species: "dog", step: "mood", mood: "waiting", cutout, reference }, {});
    if (!("image" in response)) throw new Error("expected an image");
    expect(pngSize(Buffer.from(response.image, "base64"))).toEqual({ width: 512, height: 512 });
    expect(seen[0]).toMatchObject({ count: 1, quality: "medium", format: "png", prompt: promptFor("mood", "dog", "waiting") });
    // The character first, then the photo: the prompt speaks of them in that order.
    expect(seen[0]!.images).toHaveLength(2);
    expect(seen[0]!.images[0]!.equals(Buffer.from(reference, "base64"))).toBe(true);
  });
});

describe("drawing an animation", () => {
  it("returns a GIF and how many frames it really has, from the mood's still alone", async () => {
    const { service, seen } = made();
    const response = await service.draw({ ...ids(), species: "cat", step: "animation", mood: "asleep", cutout, reference }, {});
    if (!("gif" in response)) throw new Error("expected a gif");
    expect(response.frames).toBe(9);
    expect(gifFrames(Buffer.from(response.gif, "base64"))).toBe(9);
    expect(seen[0]).toMatchObject({ count: 1, quality: "medium", format: "gif", size: "512x512", prompt: promptFor("animation", "cat", "asleep") });
    expect(seen[0]!.images).toHaveLength(1);
  });
});

describe("when the drawing fails", () => {
  it("gives the round back, and says which way it failed", async () => {
    for (const code of ["refused", "unavailable"] as const) {
      const { service, calls } = made({ failure: () => new RelayError(code, "model said so") });
      const error = await failure(service.draw({ ...ids(), species: "dog", step: "tries", cutout }, {}));
      expect(error.code).toBe(code);
      expect(calls.released).toHaveLength(1);
      expect(calls.settled).toHaveLength(0);
    }
  });

  it("calls anything unexpected unavailable, gives the round back, and logs what it was without its data", async () => {
    const key = "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789";
    const message = `Cannot read properties of undefined (reading 'data') with Bearer ${key} and image ${cutout.slice(0, 400)}`;
    const { service, calls, log } = made({ failure: () => new TypeError(message) });
    const error = await failure(service.draw({ ...ids(), species: "dog", step: "tries", cutout }, {}));
    expect(error.code).toBe("unavailable");
    expect(error.reason).toBe("internal");
    expect(details(error)).toEqual({ code: "unavailable", reason: "relay" });
    expect(calls.released).toHaveLength(1);
    const entry = log.entries.find((logged) => logged.event === "draw failed unexpectedly")!;
    expect(entry.level).toBe("error");
    expect(entry.fields).toMatchObject({ errorClass: "internal", errorName: "TypeError", step: "tries" });
    expect(entry.fields.detail).toContain("Cannot read properties of undefined (reading 'data')");
    const written = strings(safe(entry.fields)).join(" ");
    expect(written).not.toContain(key);
    expect(written).not.toContain("abcdefghijklmnop");
    expect(written).not.toContain(cutout.slice(0, 40));
    expect((safe(entry.fields).detail as string).length).toBeLessThanOrEqual(300);
  });

  it("scrubs keys, tokens and long runs from anything it describes", () => {
    expect(scrubbed("failed with Authorization: Bearer abc.def.ghi and more")).toBe("failed with Authorization: Bearer [key] and more");
    expect(scrubbed("key sk-test-1234567890 was refused")).toBe("key [key] was refused");
    expect(scrubbed(`bytes ${"iVBORw0KGgo".repeat(20)} end`)).toBe("bytes [long] end");
    expect(scrubbed("deadline   exceeded\n after 30s")).toBe("deadline exceeded after 30s");
    expect(described("just a string")).toEqual({ errorName: "string", detail: "just a string" });
    expect(described(new RangeError("out of range"))).toEqual({ errorName: "RangeError", detail: "out of range" });
  });

  it("says what a broken ledger said", async () => {
    const { service, log } = made({ reserve: () => new Error("10 ABORTED: too much contention on these documents") });
    await failure(service.draw({ ...ids(), species: "dog", step: "tries", cutout }, {}));
    const entry = log.entries.find((logged) => logged.event === "ledger failed")!;
    expect(entry.fields).toMatchObject({ errorClass: "ledger", errorName: "Error", detail: "10 ABORTED: too much contention on these documents" });
  });

  it("draws nothing when a limit stands in the way", async () => {
    const { service, seen, calls } = made({ reserve: () => new RelayError("limit-reached", "rounds") });
    const error = await failure(service.draw({ ...ids(), species: "dog", step: "tries", cutout }, {}));
    expect(error.code).toBe("limit-reached");
    expect(seen).toHaveLength(0);
    expect(calls.released).toHaveLength(0);
  });

  it("draws nothing past the day's spending, says so to the app, and logs it as an error", async () => {
    const { service, seen, log } = made({ reserve: () => new RelayError("unavailable", "spend ceiling", "spend-ceiling") });
    const error = await failure(service.draw({ ...ids(), species: "dog", step: "tries", cutout }, {}));
    expect(error.code).toBe("unavailable");
    expect(details(error)).toEqual({ code: "unavailable", reason: "spend-ceiling" });
    expect(seen).toHaveLength(0);
    expect(log.entries.filter((entry) => entry.level === "error")).toHaveLength(1);
  });

  it("calls a broken ledger unavailable", async () => {
    const { service, seen } = made({ reserve: () => new Error("firestore is down") });
    const error = await failure(service.draw({ ...ids(), species: "dog", step: "tries", cutout }, {}));
    expect(error.code).toBe("unavailable");
    expect(seen).toHaveLength(0);
  });

  it("refuses bad input before anything is reserved or drawn", async () => {
    const { service, seen, calls } = made();
    const error = await failure(service.draw({ ...ids(), species: "dog", step: "tries", cutout, prompt: "a dragon" }, {}));
    expect(error.code).toBe("invalid");
    expect(seen).toHaveLength(0);
    expect(calls.reserved).toHaveLength(0);
  });
});

describe("what the relay writes down", () => {
  it("logs hashed ids, the step, the time and the tokens, and no picture", async () => {
    const { service, log } = made();
    const request = { ...ids(), species: "dog", step: "mood", mood: "zoomies", cutout, reference };
    const response = await service.draw(request, { installationId: "installation-1" });
    if (!("image" in response)) throw new Error("expected an image");
    const drew = log.entries.find((entry) => entry.event === "drew")!;
    expect(drew.fields).toMatchObject({
      household: hashed("household", request.householdId), companion: hashed("companion", request.companionId),
      step: "mood", mood: "zoomies", species: "dog", textTokens: 150, outputTokens: 1400, attempts: 1,
    });
    const written = strings(log.entries.map((entry) => safe(entry.fields)));
    for (const text of written) expect(text.length).toBeLessThanOrEqual(120);
    const all = written.join(" ");
    for (const secret of [request.householdId, request.companionId, "installation-1", cutout.slice(0, 60), reference.slice(0, 60), response.image.slice(0, 60)]) {
      expect(all).not.toContain(secret);
    }
  });

  it("cuts anything long before it reaches a log", () => {
    const entry = safe({ reason: "x".repeat(5000), ms: 12, step: "tries" });
    expect((entry.reason as string).length).toBe(120);
    expect(entry.ms).toBe(12);
    expect(safe({ ms: Number.NaN })).toEqual({});
  });

  it("names the installation to the ledger only as a hash", async () => {
    const { service, calls } = made();
    await service.draw({ ...ids(), species: "dog", step: "tries", cutout }, { installationId: "installation-1" });
    expect(calls.reserved[0]!.installation).toBe(hashed("installation", "installation-1"));
    await service.draw({ ...ids(), species: "dog", step: "tries", cutout }, {});
    expect(calls.reserved[1]!.installation).toBeUndefined();
  });
});

describe("asking what is left", () => {
  it("answers with the rounds left", async () => {
    const { service } = made();
    expect(await service.allowance(ids())).toEqual({ roundsLeft: 3 });
    const error = await failure(service.allowance({ householdId: "nope", companionId: newId() }));
    expect(error.code).toBe("invalid");
  });
});
