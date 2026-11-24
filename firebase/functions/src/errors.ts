/**
 * What can go wrong, in the contract's words. A callable's own status is one of a fixed
 * set, so each of ours rides in `details.code` on the nearest status; the app reads
 * `details.code` and nothing else.
 */
export type RelayCode = "limit-reached" | "refused" | "unavailable" | "unauthenticated" | "invalid";

/** The callable status each code is sent under. */
export const statusFor = {
  "limit-reached": "resource-exhausted",
  refused: "failed-precondition",
  unavailable: "unavailable",
  unauthenticated: "unauthenticated",
  invalid: "invalid-argument",
} as const satisfies Record<RelayCode, string>;

export class RelayError extends Error {
  constructor(
    readonly code: RelayCode,
    /** A short reason for the log and the app's own diagnostics: never a person's data. */
    readonly reason: string,
  ) {
    super(`${code}: ${reason}`);
    this.name = "RelayError";
  }
}
