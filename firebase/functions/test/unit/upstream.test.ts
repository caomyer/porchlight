import { beforeAll, describe, expect, it } from "vitest";

import { config } from "../../src/config";
import { details, RelayError, type Upstream } from "../../src/errors";
import { fakeModel } from "../../src/fake";
import { safe, upstreamFields } from "../../src/log";
import { openAIModel, type Transport } from "../../src/model";
import { relay } from "../../src/service";
import { memoryLog, newId, openLedger, png, pngBase64, strings } from "../support";

const key = "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCD";

/** The answers the image model gives when it turns the relay away, as its API words them. */
const answers = {
  wrongKey: { status: 401, error: { message: `Incorrect API key provided: ${key}. You can find your API key at https://platform.openai.com/account/api-keys.`, type: "invalid_request_error", param: null, code: "invalid_api_key" } },
  missingScope: { status: 401, error: { message: "You have insufficient permissions for this operation. Missing scopes: api.model.images.request. Check that you have the correct role in your organization, and if you're using a restricted API key, that it has the necessary scopes.", type: "invalid_request_error", param: null, code: null } },
  unverified: { status: 403, error: { message: "Your organization must be verified to use the model `gpt-image-2.6-flare`. Please go to: https://platform.openai.com/settings/organization/general and click on Verify Organization.", type: "invalid_request_error", param: null, code: "organization_must_be_verified_to_use_this_model" } },
  noModel: { status: 404, error: { message: "The model `gpt-image-2.6-flare` does not exist or you do not have access to it.", type: "invalid_request_error", param: "model", code: "model_not_found" } },
  noGif: { status: 400, error: { message: "GIF output requires access to the GIF preview for this model.", type: "invalid_request_error", param: "output_format", code: "unsupported_value" } },
  billing: { status: 429, error: { message: "Billing hard limit has been reached.", type: "insufficient_quota", param: null, code: "billing_hard_limit_reached" } },
};

function answering(answer: { status: number; error: unknown }, requestId: string | undefined = "req_0123456789abcdef0123456789abcdef") {
  let calls = 0;
  const transport: Transport = async () => {
    calls += 1;
    return { status: answer.status, body: { error: answer.error }, requestId };
  };
  return { transport, calls: () => calls };
}

async function caught(transport: Transport): Promise<RelayError> {
  try {
    await openAIModel(() => key, transport, async () => undefined).draw({
      prompt: "p", images: [await png()], size: "1024x1024", quality: "low", count: 1, format: "png", safetyIdentifier: "s",
    });
  } catch (error) {
    return error as RelayError;
  }
  throw new Error("expected a failure");
}

describe("when the model turns the relay itself away", () => {
  it("is the key's fault to the app, is not tried again, and keeps what the model said", async () => {
    for (const answer of [answers.wrongKey, answers.missingScope, answers.unverified]) {
      const { transport, calls } = answering(answer);
      const error = await caught(transport);
      expect(details(error)).toEqual({ code: "unavailable", reason: "model-key" });
      expect(calls()).toBe(1);
      expect(error.upstream?.status).toBe(answer.status);
      expect(error.upstream?.requestId).toBe("req_0123456789abcdef0123456789abcdef");
    }
  });

  it("stays an ordinary model failure for anything but 401 and 403", async () => {
    for (const answer of [answers.noModel, answers.noGif]) {
      const { transport, calls } = answering(answer);
      const error = await caught(transport);
      expect(details(error)).toEqual({ code: "unavailable", reason: "model" });
      expect(calls()).toBe(1);
    }
    const { transport, calls } = answering(answers.billing);
    expect(details(await caught(transport))).toEqual({ code: "unavailable", reason: "model" });
    expect(calls()).toBe(1 + config.model.retries);
  });
});

describe("what the log says the model said", () => {
  async function logged(answer: { status: number; error: unknown }) {
    return safe(upstreamFields((await caught(answering(answer).transport)).upstream));
  }

  it("reads differently for each way a key can be wrong", async () => {
    expect(await logged(answers.wrongKey)).toMatchObject({ modelStatus: 401, modelCode: "invalid_api_key", modelType: "invalid_request_error" });
    const scope = await logged(answers.missingScope);
    expect(scope.modelCode).toBeUndefined();
    expect(scope.modelMessage).toContain("Missing scopes: api.model.images.request");
    const unverified = await logged(answers.unverified);
    expect(unverified).toMatchObject({ modelStatus: 403, modelCode: "organization_must_be_verified_to_use_this_model" });
    expect(unverified.modelMessage).toContain("Your organization must be verified");
    expect(await logged(answers.noModel)).toMatchObject({ modelStatus: 404, modelCode: "model_not_found", modelParam: "model" });
    expect(await logged(answers.noGif)).toMatchObject({ modelStatus: 400, modelCode: "unsupported_value", modelParam: "output_format" });
    expect((await logged(answers.noGif)).modelMessage).toContain("GIF preview");
    expect(await logged(answers.billing)).toMatchObject({ modelStatus: 429, modelCode: "billing_hard_limit_reached", modelType: "insufficient_quota" });
  });

  it("never shows the key, though the model's message quotes it", async () => {
    const entry = await logged(answers.wrongKey);
    const written = strings(entry).join(" ");
    expect(written).not.toContain(key);
    expect(written).not.toContain("abcdefghijklmnop");
    expect(entry.modelMessage).toContain("Incorrect API key provided: [key]");
  });

  it("cuts a long message and scrubs bytes out of it", () => {
    const upstream: Upstream = { status: 400, message: `bad image ${"iVBORw0KGgoAAAANSUhEUg".repeat(40)} ${"word ".repeat(200)}` };
    const entry = safe(upstreamFields(upstream));
    expect((entry.modelMessage as string).length).toBeLessThanOrEqual(300);
    expect(entry.modelMessage).toContain("bad image [long]");
    expect(entry.modelMessage).not.toContain("iVBORw0KGgo");
  });

  it("keeps the request id as given, and drops one that is not an id", () => {
    expect(upstreamFields({ status: 500, requestId: "req_0123456789abcdef0123456789abcdef" }).requestId).toBe("req_0123456789abcdef0123456789abcdef");
    expect(upstreamFields({ status: 500, requestId: "an id with spaces\nand a line" }).requestId).toBeUndefined();
    expect(upstreamFields({ status: 500 }).requestId).toBeUndefined();
  });

  it("will not log a code that is not a plain name", () => {
    expect(upstreamFields({ status: 400, code: `weird ${key}` }).modelCode).toBe("[unreadable]");
    expect(upstreamFields({ status: 400, code: "x".repeat(200) }).modelCode).toBe("[unreadable]");
    expect(upstreamFields({ status: 400, param: "image[0]" }).modelParam).toBe("image[0]");
    expect(upstreamFields(undefined)).toEqual({});
  });
});

describe("a draw the model turned away", () => {
  let cutout: string;
  beforeAll(async () => {
    cutout = await pngBase64();
  });

  async function drawn(error: RelayError) {
    const log = memoryLog();
    const { ledger, calls } = openLedger();
    const service = relay({ model: fakeModel({ failure: () => error }), ledger, log, now: () => new Date(), dailyCeiling: 5 });
    let thrown: RelayError | undefined;
    try {
      await service.draw({ householdId: newId(), companionId: newId(), species: "dog", step: "tries", cutout }, {});
    } catch (failure) {
      thrown = failure as RelayError;
    }
    return { log, calls, thrown: thrown! };
  }

  it("logs what the model said, as an error when it is the key, and gives the round back", async () => {
    const { log, calls, thrown } = await drawn(await caught(answering(answers.missingScope).transport));
    const entry = log.entries.find((logged) => logged.event === "draw failed")!;
    expect(entry.level).toBe("error");
    expect(entry.fields).toMatchObject({ errorClass: "unavailable", modelStatus: 401, modelType: "invalid_request_error", requestId: "req_0123456789abcdef0123456789abcdef", step: "tries" });
    expect(entry.fields.modelMessage).toContain("Missing scopes");
    expect(calls.released).toHaveLength(1);
    // The app is told whose fault it is, and none of the model's words.
    expect(details(thrown)).toEqual({ code: "unavailable", reason: "model-key" });
    expect(JSON.stringify(details(thrown))).not.toContain("scopes");
  });

  it("logs an outage as a warning, with the model's words too", async () => {
    const { log } = await drawn(await caught(answering(answers.billing).transport));
    const entry = log.entries.find((logged) => logged.event === "draw failed")!;
    expect(entry.level).toBe("warn");
    expect(entry.fields).toMatchObject({ modelStatus: 429, modelCode: "billing_hard_limit_reached" });
  });
});
