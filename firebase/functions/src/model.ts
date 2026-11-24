import { config } from "./config";
import { RelayError } from "./errors";

/** What one call to the image model asks for. */
export interface ModelRequest {
  prompt: string;
  /** PNGs, the reference first when there is one. */
  images: Buffer[];
  size: string;
  quality: string;
  count: number;
  format: "png" | "gif";
  /** A stable, hashed name for whoever asked, for the model's own abuse checks. */
  safetyIdentifier: string;
}

export interface Usage {
  textTokens: number;
  imageTokens: number;
  outputTokens: number;
}

export interface ModelResult {
  /** The drawings, as raw bytes. */
  outputs: Buffer[];
  usage: Usage;
  attempts: number;
}

/** The image model, behind a seam so the tests never call the real one. */
export interface ImageModel {
  draw(request: ModelRequest): Promise<ModelResult>;
}

/** What one attempt came back with, before it is turned into a result or an error. */
interface Attempt {
  status: number;
  body: unknown;
}

export type Transport = (form: FormData, key: string, timeoutMs: number) => Promise<Attempt>;

/** The real call: a multipart post to the images edit endpoint. */
export const post: Transport = async (form, key, timeoutMs) => {
  const response = await fetch(config.model.endpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}` },
    body: form,
    signal: AbortSignal.timeout(timeoutMs),
  });
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    body = undefined;
  }
  return { status: response.status, body };
};

function form(request: ModelRequest): FormData {
  const data = new FormData();
  data.set("model", config.model.name);
  data.set("prompt", request.prompt);
  data.set("size", request.size);
  data.set("quality", request.quality);
  data.set("n", String(request.count));
  data.set("background", "transparent");
  data.set("output_format", request.format);
  data.set("safety_identifier", request.safetyIdentifier);
  if (request.format === "gif") {
    data.set("frame_count", String(config.model.animationFrames));
    data.set("frame_duration_ms", String(config.model.animationFrameMs));
  }
  request.images.forEach((image, index) => {
    data.append("image[]", new Blob([new Uint8Array(image)], { type: "image/png" }), `image-${index}.png`);
  });
  return data;
}

function field(value: unknown, key: string): unknown {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>)[key] : undefined;
}

function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0;
}

/** The model's own words for "this picture or prompt is not allowed". */
const refusalCodes = ["moderation_blocked", "content_policy_violation"];

/**
 * Turns an attempt into drawings, or says how it failed: a refusal is final, a rate limit
 * or a server error may be tried again, and anything else is the relay's own fault.
 */
function read(attempt: Attempt, expected: number): { result?: Omit<ModelResult, "attempts">; error?: RelayError; retry: boolean } {
  const { status, body } = attempt;
  if (status >= 200 && status < 300) {
    const data = field(body, "data");
    const outputs = Array.isArray(data)
      ? data.map((item) => field(item, "b64_json")).filter((item): item is string => typeof item === "string" && item.length > 0)
      : [];
    if (outputs.length < expected) {
      return { error: new RelayError("unavailable", `model returned ${outputs.length} of ${expected}`), retry: true };
    }
    const usage = field(body, "usage");
    const details = field(usage, "input_tokens_details");
    return {
      result: {
        outputs: outputs.slice(0, expected).map((item) => Buffer.from(item, "base64")),
        usage: {
          textTokens: count(field(details, "text_tokens")),
          imageTokens: count(field(details, "image_tokens")),
          outputTokens: count(field(usage, "output_tokens")),
        },
      },
      retry: false,
    };
  }
  const error = field(body, "error");
  const code = field(error, "code");
  const type = field(error, "type");
  if (typeof code === "string" && refusalCodes.includes(code)) {
    return { error: new RelayError("refused", code), retry: false };
  }
  if (status === 429 || status >= 500 || status === 408) {
    return { error: new RelayError("unavailable", `model status ${status}`), retry: true };
  }
  // A request the model will not take as written (a bad key, an unknown field, no access
  // to a feature): trying again cannot help, and it is not the person's doing.
  const named = typeof code === "string" ? code : typeof type === "string" ? type : "unknown";
  return { error: new RelayError("unavailable", `model status ${status} ${named}`.slice(0, 100)), retry: false };
}

export function usageDollars(usage: Usage): number {
  const { textInputPerMillion, imageInputPerMillion, outputPerMillion } = config.cost;
  return (usage.textTokens * textInputPerMillion + usage.imageTokens * imageInputPerMillion + usage.outputTokens * outputPerMillion) / 1_000_000;
}

const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** The image model over HTTP, with one more attempt where another attempt can help. */
export function openAIModel(key: () => string, transport: Transport = post, pause: (ms: number) => Promise<void> = wait): ImageModel {
  return {
    async draw(request) {
      let last = new RelayError("unavailable", "no attempt");
      for (let attempt = 1; attempt <= 1 + config.model.retries; attempt += 1) {
        let outcome: ReturnType<typeof read>;
        try {
          outcome = read(await transport(form(request), key(), config.model.attemptTimeoutMs), request.count);
        } catch (error) {
          // A timeout or a dropped connection. The error's own text is never kept: it
          // could hold a URL or a header.
          const name = error instanceof Error ? error.name : "Error";
          outcome = { error: new RelayError("unavailable", `transport ${name}`), retry: true };
        }
        if (outcome.result) return { ...outcome.result, attempts: attempt };
        last = outcome.error ?? last;
        if (!outcome.retry) break;
        if (attempt <= config.model.retries) await pause(config.model.retryDelayMs);
      }
      throw last;
    },
  };
}
