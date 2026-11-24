/**
 * What can go wrong, in the contract's words. A callable's own status is one of a fixed
 * set, so each of ours rides in `details.code` on the nearest status, with `details.reason`
 * beside it where there is more to say. The app reads `details` and nothing else.
 */
export type RelayCode = "limit-reached" | "refused" | "unavailable" | "unauthenticated" | "invalid";

/**
 * Why, for the app to choose its words. A closed set, part of the contract
 * (contract.ts, `FailureDetails`).
 *
 * With `limit-reached`:
 * - `rounds`: this companion has had its three rounds of tries.
 * - `mood-redraws`: this mood's still has been drawn as often as it may be.
 * - `animation-redraws`: this mood's animation has been drawn as often as it may be.
 * - `companions`: the household has as many companions with characters as it may have.
 * - `household-day`: the household has made its calls for today; tomorrow is open again.
 * - `installation-day`: this installation has made its calls for today.
 *
 * With `unavailable`:
 * - `spend-ceiling`: the whole service has spent its money for today; tomorrow is open again.
 * - `model`: the image model failed, timed out or could not be reached; trying again soon may work.
 * - `relay`: the relay itself failed; trying again soon may work.
 *
 * `refused` and `invalid` carry no reason. A reason may be added later, so an app must
 * treat one it does not know as if there were none and fall back on the code.
 */
export type RelayReason =
  | "rounds" | "mood-redraws" | "animation-redraws" | "companions" | "household-day" | "installation-day"
  | "spend-ceiling" | "model" | "relay";

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
    /** A short reason for the log: never a person's data. */
    readonly reason: string,
    /** The reason the app is told, when the code has one. */
    readonly shared?: RelayReason,
  ) {
    super(`${code}: ${reason}`);
    this.name = "RelayError";
  }
}

/** What the app is sent about a failure. */
export function details(error: RelayError): { code: RelayCode; reason?: RelayReason } {
  if (error.shared) return { code: error.code, reason: error.shared };
  // Whatever went wrong inside, "unavailable" always says whose side it was on.
  if (error.code === "unavailable") return { code: error.code, reason: "relay" };
  return { code: error.code };
}
