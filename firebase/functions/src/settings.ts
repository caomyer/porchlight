import { config } from "./config";

/**
 * The ENFORCE_LIFETIME_LIMITS switch as it is written: "true" or "false", in any case.
 * Anything else, a missing value included, is the default in config.ts, so a typing slip
 * can never be read as "enforce" or "do not enforce" by accident of how it is parsed.
 */
export function enforced(value: string | undefined): boolean {
  const written = (value ?? "").trim().toLowerCase();
  if (written === "true") return true;
  if (written === "false") return false;
  return config.limits.enforceLifetimeByDefault;
}
