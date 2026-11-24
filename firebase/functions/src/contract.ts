import { createHash } from "node:crypto";

import { moods, speciesList, steps, type Mood, type Species, type Step } from "./config";
import { RelayError } from "./errors";
import { decodePng } from "./images";

/** What the app sends to `drawCharacter`, once checked. */
export interface DrawRequest {
  householdId: string;
  companionId: string;
  species: Species;
  step: Step;
  /** Set for a mood and an animation. */
  mood?: Mood;
  /** The pet's cut-out from the photo. */
  cutout: Buffer;
  /** The chosen character (for a mood) or that mood's still (for an animation). */
  reference?: Buffer;
}

export type DrawResponse =
  | { images: string[]; roundsLeft: number }
  | { image: string }
  | { gif: string; frames: number };

export interface AllowanceRequest {
  householdId: string;
  companionId: string;
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function record(data: unknown): Record<string, unknown> {
  if (typeof data !== "object" || data === null || Array.isArray(data)) throw new RelayError("invalid", "not an object");
  return data as Record<string, unknown>;
}

/** An id as the app writes them: a UUID, kept in lower case. */
function id(value: unknown, field: string): string {
  if (typeof value !== "string") throw new RelayError("invalid", `${field} missing`);
  const lowered = value.toLowerCase();
  if (!uuid.test(lowered)) throw new RelayError("invalid", `${field} not an id`);
  return lowered;
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[], field: string): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) throw new RelayError("invalid", `${field} not allowed`);
  return value as T;
}

function onlyKeys(data: Record<string, unknown>, allowed: readonly string[]): void {
  for (const key of Object.keys(data)) {
    if (!allowed.includes(key)) throw new RelayError("invalid", "unknown field");
  }
}

export function parseDraw(data: unknown): DrawRequest {
  const body = record(data);
  onlyKeys(body, ["householdId", "companionId", "species", "step", "mood", "cutout", "reference"]);
  const step = oneOf(body.step, steps, "step");
  const request: DrawRequest = {
    householdId: id(body.householdId, "householdId"),
    companionId: id(body.companionId, "companionId"),
    species: oneOf(body.species, speciesList, "species"),
    step,
    cutout: decodePng(body.cutout, "cutout"),
  };
  if (step === "tries") {
    if (body.mood !== undefined) throw new RelayError("invalid", "mood given for tries");
    if (body.reference !== undefined) throw new RelayError("invalid", "reference given for tries");
    return request;
  }
  request.mood = oneOf(body.mood, moods, "mood");
  request.reference = decodePng(body.reference, "reference");
  return request;
}

export function parseAllowance(data: unknown): AllowanceRequest {
  const body = record(data);
  onlyKeys(body, ["householdId", "companionId"]);
  return { householdId: id(body.householdId, "householdId"), companionId: id(body.companionId, "companionId") };
}

/**
 * An id as the relay stores and logs it: a one-way hash, so its own records name no
 * household. The app's ids are random, so the hash cannot be worked back.
 */
export function hashed(kind: "household" | "companion" | "installation", value: string): string {
  return createHash("sha256").update(`porchlight:${kind}:${value}`).digest("hex").slice(0, 32);
}
