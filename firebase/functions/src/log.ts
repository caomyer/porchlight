import * as logger from "firebase-functions/logger";

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
}

const maxLength = 120;
const maxDetail = 300;

export function safe(fields: LogFields): Record<string, string | number> {
  const entry: Record<string, string | number> = {};
  for (const [key, value] of Object.entries(fields)) {
    const cap = key === "detail" ? maxDetail : maxLength;
    if (typeof value === "number" && Number.isFinite(value)) entry[key] = value;
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
    .replace(/[A-Za-z0-9+/=_-]{32,}/g, "[long]")
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
