import { describe, expect, it } from "vitest";

import { config } from "../../src/config";
import { RelayError } from "../../src/errors";
import { openAIModel, usageDollars, type ModelRequest, type Transport } from "../../src/model";
import { png } from "../support";

const key = "sk-test-key-that-must-never-be-logged";

async function request(overrides: Partial<ModelRequest> = {}): Promise<ModelRequest> {
  return {
    prompt: "draw it", images: [await png()], size: "1024x1024", quality: "low", count: 1, format: "png",
    safetyIdentifier: "abc123", ...overrides,
  };
}

const drawn = (count = 1) => ({
  status: 200,
  body: {
    data: Array.from({ length: count }, () => ({ b64_json: Buffer.from("picture").toString("base64") })),
    usage: { output_tokens: 1449, input_tokens_details: { text_tokens: 184, image_tokens: 768 } },
  },
});

/** A transport that answers from a script and remembers what it was sent. */
function scripted(answers: (ReturnType<typeof drawn> | { status: number; body: unknown } | Error)[]) {
  const sent: { form: FormData; key: string; timeoutMs: number }[] = [];
  const transport: Transport = async (form, sentKey, timeoutMs) => {
    sent.push({ form, key: sentKey, timeoutMs });
    const answer = answers[Math.min(sent.length - 1, answers.length - 1)]!;
    if (answer instanceof Error) throw answer;
    return answer;
  };
  return { transport, sent };
}

const noPause = async () => undefined;

async function failure(work: Promise<unknown>): Promise<RelayError> {
  try {
    await work;
  } catch (error) {
    expect(error).toBeInstanceOf(RelayError);
    return error as RelayError;
  }
  throw new Error("expected a failure");
}

describe("asking the image model", () => {
  it("sends the model, the prompt, a transparent background and every image", async () => {
    const { transport, sent } = scripted([drawn(3)]);
    const result = await openAIModel(() => key, transport, noPause).draw(await request({ count: 3, images: [await png(), await png()] }));
    expect(result.outputs).toHaveLength(3);
    expect(result.attempts).toBe(1);
    expect(result.usage).toEqual({ textTokens: 184, imageTokens: 768, outputTokens: 1449 });
    const form = sent[0]!.form;
    expect(form.get("model")).toBe(config.model.name);
    expect(form.get("prompt")).toBe("draw it");
    expect(form.get("background")).toBe("transparent");
    expect(form.get("output_format")).toBe("png");
    expect(form.get("n")).toBe("3");
    expect(form.get("safety_identifier")).toBe("abc123");
    expect(form.getAll("image[]")).toHaveLength(2);
    expect(form.get("frame_count")).toBeNull();
    expect(sent[0]!.key).toBe(key);
    expect(sent[0]!.timeoutMs).toBe(config.model.attemptTimeoutMs);
  });

  it("asks for nine frames when it asks for an animation", async () => {
    const { transport, sent } = scripted([drawn()]);
    await openAIModel(() => key, transport, noPause).draw(await request({ format: "gif", size: config.model.animationSize }));
    expect(sent[0]!.form.get("output_format")).toBe("gif");
    expect(sent[0]!.form.get("frame_count")).toBe(String(config.model.animationFrames));
    expect(sent[0]!.form.get("size")).toBe("512x512");
  });

  it("calls a blocked picture a refusal, and does not try again", async () => {
    const { transport, sent } = scripted([{ status: 400, body: { error: { type: "image_generation_user_error", code: "moderation_blocked" } } }]);
    const error = await failure(openAIModel(() => key, transport, noPause).draw(await request()));
    expect(error.code).toBe("refused");
    expect(sent).toHaveLength(1);
  });

  it("tries once more after a rate limit, a server error or a timeout", async () => {
    for (const first of [{ status: 429, body: {} }, { status: 503, body: undefined }, new DOMException("timed out", "TimeoutError")]) {
      const { transport, sent } = scripted([first, drawn()]);
      const result = await openAIModel(() => key, transport, noPause).draw(await request());
      expect(result.attempts).toBe(2);
      expect(sent).toHaveLength(2);
    }
  });

  it("gives up as unavailable when the second attempt fails too", async () => {
    const { transport, sent } = scripted([{ status: 500, body: {} }]);
    const error = await failure(openAIModel(() => key, transport, noPause).draw(await request()));
    expect(error.code).toBe("unavailable");
    expect(sent).toHaveLength(1 + config.model.retries);
  });

  it("does not try again when the request itself is at fault", async () => {
    for (const status of [400, 401, 403, 404]) {
      const { transport, sent } = scripted([{ status, body: { error: { code: "invalid_api_key", message: `Incorrect API key provided: ${key}` } } }]);
      const error = await failure(openAIModel(() => key, transport, noPause).draw(await request()));
      expect(error.code).toBe("unavailable");
      expect(sent).toHaveLength(1);
      // The model's own message can quote the key: only its short code is kept.
      expect(error.reason).not.toContain(key);
      expect(error.message).not.toContain(key);
    }
  });

  it("treats too few drawings as a failure worth one more attempt", async () => {
    const { transport, sent } = scripted([drawn(2), drawn(3)]);
    const result = await openAIModel(() => key, transport, noPause).draw(await request({ count: 3 }));
    expect(result.outputs).toHaveLength(3);
    expect(sent).toHaveLength(2);
  });

  it("keeps nothing of a transport error but its kind", async () => {
    const { transport } = scripted([new Error(`connect failed with header Bearer ${key}`)]);
    const error = await failure(openAIModel(() => key, transport, noPause).draw(await request()));
    expect(error.reason).toBe("transport Error");
  });

  it("fits two attempts inside the function's own time limit", () => {
    const longest = (1 + config.model.retries) * config.model.attemptTimeoutMs + config.model.retries * config.model.retryDelayMs;
    expect(longest).toBeLessThan(config.deploy.timeoutSeconds * 1000 - 15_000);
    expect(config.model.attemptTimeoutMs).toBeGreaterThanOrEqual(30_000);
  });
});

describe("what a call cost", () => {
  it("comes from its tokens and the rates", () => {
    // A still at medium quality in the lead's test: about 5 cents.
    expect(usageDollars({ textTokens: 184, imageTokens: 768, outputTokens: 1449 })).toBeCloseTo(0.0505, 3);
    expect(usageDollars({ textTokens: 0, imageTokens: 0, outputTokens: 0 })).toBe(0);
  });
});
