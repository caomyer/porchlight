import { describe, expect, it } from "vitest";

import type { FailureDetails } from "../../src/contract";
import { details, RelayError, statusFor, type RelayReason } from "../../src/errors";
import { openAIModel, type Transport } from "../../src/model";
import { png } from "../support";

/** Every reason the contract names. Adding one here is adding it to the contract. */
const reasons: RelayReason[] = [
  "rounds", "mood-redraws", "animation-redraws", "companions", "household-day", "installation-day",
  "spend-ceiling", "model", "relay",
];

describe("what the app is told about a failure", () => {
  it("is the code, and the reason when there is one", () => {
    expect(details(new RelayError("limit-reached", "rounds", "rounds"))).toEqual({ code: "limit-reached", reason: "rounds" });
    expect(details(new RelayError("unavailable", "spend ceiling", "spend-ceiling"))).toEqual({ code: "unavailable", reason: "spend-ceiling" });
    expect(details(new RelayError("refused", "moderation_blocked"))).toEqual({ code: "refused" });
    expect(details(new RelayError("invalid", "cutout not a PNG"))).toEqual({ code: "invalid" });
  });

  it("never carries the log's own words, which may say more than the app should hear", () => {
    const sent = details(new RelayError("unavailable", "model status 401 invalid_api_key", "model"));
    expect(JSON.stringify(sent)).not.toContain("invalid_api_key");
    expect(sent).toEqual({ code: "unavailable", reason: "model" });
  });

  it("calls an unavailable with nothing more to say the relay's own", () => {
    expect(details(new RelayError("unavailable", "something inside"))).toEqual({ code: "unavailable", reason: "relay" });
  });

  it("uses only reasons from the closed set, in a shape the contract names", () => {
    for (const reason of reasons) {
      const code = ["spend-ceiling", "model", "relay"].includes(reason) ? "unavailable" : "limit-reached";
      const sent: FailureDetails = details(new RelayError(code, "for the log", reason)) as FailureDetails;
      expect(sent.reason).toBe(reason);
      expect(reason).toMatch(/^[a-z]+(-[a-z]+)*$/);
    }
    expect(Object.keys(statusFor)).toEqual(["limit-reached", "refused", "unavailable", "unauthenticated", "invalid"]);
  });
});

describe("a failure of the image model", () => {
  const failing = (answer: { status: number; body: unknown } | Error): Transport => async () => {
    if (answer instanceof Error) throw answer;
    return answer;
  };

  async function caught(transport: Transport): Promise<RelayError> {
    try {
      await openAIModel(() => "key", transport, async () => undefined).draw({
        prompt: "p", images: [await png()], size: "1024x1024", quality: "low", count: 1, format: "png", safetyIdentifier: "s",
      });
    } catch (error) {
      return error as RelayError;
    }
    throw new Error("expected a failure");
  }

  it("is told to the app as the model's, whichever way it failed", async () => {
    for (const answer of [{ status: 500, body: {} }, { status: 429, body: {} }, { status: 401, body: { error: { code: "invalid_api_key" } } }, new Error("socket hang up"), { status: 200, body: { data: [] } }]) {
      expect(details(await caught(failing(answer)))).toEqual({ code: "unavailable", reason: "model" });
    }
  });

  it("is a refusal, with no reason, when the picture is blocked", async () => {
    expect(details(await caught(failing({ status: 400, body: { error: { code: "moderation_blocked" } } })))).toEqual({ code: "refused" });
  });
});
