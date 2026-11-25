import * as logger from "firebase-functions/logger";

import type { Upstream } from "./errors";

/**
 * The one way the relay writes a log. An entry holds hashed ids, the step, how long it
 * took, token counts and the class of an error: never a photo, a drawing, a prompt or a
 * key. Anything longer than a short word is cut, so a slip cannot put image bytes in a log.
 */
export interface LogFields {
  household?: string;
  companion?: string;
  step?: string;
  mood?: string;
  species?: string;
  ms?: number;
  attempts?: number;
  textTokens?: number;
  imageTokens?: number;
  outputTokens?: number;
  dollars?: number;
  errorClass?: string;
  reason?: string;
  status?: number;
  /** An unexpected error's own name, as `TypeError`. */
  errorName?: string;
  /** An unexpected error's message, scrubbed by `described`. */
  detail?: string;
  /** What the image model answered when it failed (`upstreamFields`). */
  modelStatus?: number;
  modelCode?: string;
  modelType?: string;
  modelParam?: string;
  modelMessage?: string;
  /** The id the model gave the request, to quote to its support. */
  requestId?: string;
  /**
   * True when the call went past a lifetime limit that is counted but not enforced, with
   * `limit` naming which. Never present on a call within its limits.
   */
  overLimit?: boolean;
  limit?: string;
}

const maxLength = 120;
const maxDetail = 300;

export function safe(fields: LogFields): Record<string, string | number | boolean> {
  const entry: Record<string, string | number | boolean> = {};
  for (const [key, value] of Object.entries(fields)) {
    const cap = key === "detail" || key === "modelMessage" ? maxDetail : maxLength;
    if (typeof value === "number" && Number.isFinite(value)) entry[key] = value;
    else if (typeof value === "boolean") entry[key] = value;
    else if (typeof value === "string") entry[key] = value.length > cap ? value.slice(0, cap) : value;
  }
  return entry;
}

/**
 * Text that may be written down: keys and bearer tokens are named and not shown, and any
 * long unbroken run of letters and digits (which is what image bytes, tokens and ids look
 * like) is replaced, whatever it was.
 */
export function scrubbed(text: string): string {
  return text
    .replace(/Bearer\s+\S+/gi, "Bearer [key]")
    .replace(/sk-[A-Za-z0-9_-]{6,}/g, "[key]")
    // A long run with a digit or a capital in it: bytes, a token, an id. A long word made
    // of small letters and underscores is the model's own name for an error, and stays.
    .replace(/[A-Za-z0-9+/=_-]{32,}/g, (run) => (/[0-9A-Z+/=]/.test(run) ? "[long]" : run))
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxDetail);
}

/**
 * An unexpected error, as much as may be logged: its name and its scrubbed message, so a
 * failure in production can be told from another without its data.
 */
export function described(error: unknown): Pick<LogFields, "errorName" | "detail"> {
  if (error instanceof Error) return { errorName: scrubbed(error.name).slice(0, 60), detail: scrubbed(error.message) };
  return { errorName: typeof error, detail: scrubbed(String(error)) };
}

/** One of the model's own short names (a code, a type, a parameter), or nothing if it is not one. */
function named(value: string | undefined): string | undefined {
  if (!value) return undefined;
  if (/sk-/.test(value) || !/^[A-Za-z0-9_.\-[\]]{1,80}$/.test(value)) return "[unreadable]";
  return value;
}

/**
 * What the image model answered, as it may be logged: its status, its own names for the
 * error, its message scrubbed like any other, and its request id. This is what tells a
 * wrong key from a missing permission, an unverified organisation, an unknown model, no
 * access to a feature, and a billing limit.
 */
export function upstreamFields(upstream: Upstream | undefined): LogFields {
  if (!upstream) return {};
  const id = upstream.requestId;
  return {
    modelStatus: upstream.status,
    modelCode: named(upstream.code),
    modelType: named(upstream.type),
    modelParam: named(upstream.param),
    modelMessage: upstream.message ? scrubbed(upstream.message) : undefined,
    requestId: id && /^[A-Za-z0-9_-]{1,80}$/.test(id) ? id : undefined,
  };
}

export interface Log {
  info(event: string, fields: LogFields): void;
  warn(event: string, fields: LogFields): void;
  error(event: string, fields: LogFields): void;
}

export const log: Log = {
  info: (event, fields) => logger.info(event, safe(fields)),
  warn: (event, fields) => logger.warn(event, safe(fields)),
  error: (event, fields) => logger.error(event, safe(fields)),
};
