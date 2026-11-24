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
}

const maxLength = 120;

export function safe(fields: LogFields): Record<string, string | number> {
  const entry: Record<string, string | number> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (typeof value === "number" && Number.isFinite(value)) entry[key] = value;
    else if (typeof value === "string") entry[key] = value.length > maxLength ? value.slice(0, maxLength) : value;
  }
  return entry;
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
