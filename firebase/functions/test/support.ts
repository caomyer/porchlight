import { randomUUID } from "node:crypto";

import sharp from "sharp";

import type { Claim, Ledger, Reservation } from "../src/ledger";
import type { Log, LogFields } from "../src/log";

/** A PNG of the given size, as the app would send a cut-out. */
export async function png(width = 256, height = 256): Promise<Buffer> {
  return sharp({ create: { width, height, channels: 4, background: { r: 200, g: 150, b: 90, alpha: 1 } } }).png().toBuffer();
}

export async function pngBase64(width = 256, height = 256): Promise<string> {
  return (await png(width, height)).toString("base64");
}

export const newId = () => randomUUID();

/** A day no other test uses, so each test has its own spending and its own daily counts. */
export function newDay(): string {
  const year = 3000 + Math.floor(Math.random() * 6000);
  const month = String(1 + Math.floor(Math.random() * 12)).padStart(2, "0");
  const day = String(1 + Math.floor(Math.random() * 28)).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export interface Logged {
  level: "info" | "warn" | "error";
  event: string;
  fields: LogFields;
}

/** A log that keeps what it was given, for a test to read. */
export function memoryLog(): Log & { entries: Logged[] } {
  const entries: Logged[] = [];
  return {
    entries,
    info: (event, fields) => entries.push({ level: "info", event, fields }),
    warn: (event, fields) => entries.push({ level: "warn", event, fields }),
    error: (event, fields) => entries.push({ level: "error", event, fields }),
  };
}

/**
 * A ledger that grants everything and remembers what was asked of it. The limits
 * themselves are tested against Firestore (test/store); this one is for the service's own
 * rules: what it reserves, settles and gives back.
 */
export function openLedger(options: { reserve?: () => Error | undefined; roundsLeft?: number } = {}) {
  const calls = { reserved: [] as Claim[], settled: [] as { reservation: Reservation; dollars: number }[], released: [] as Reservation[] };
  const ledger: Ledger = {
    async reserve(claim) {
      const failure = options.reserve?.();
      if (failure) throw failure;
      calls.reserved.push(claim);
      return { claim, roundsLeft: options.roundsLeft ?? 2 };
    },
    async settle(reservation, dollars) {
      calls.settled.push({ reservation, dollars });
    },
    async release(reservation) {
      calls.released.push(reservation);
    },
    async roundsLeft() {
      return options.roundsLeft ?? 3;
    },
  };
  return { ledger, calls };
}

/** Every string anywhere inside a value, for checking what a log or a database holds. */
export function strings(value: unknown): string[] {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap(strings);
  if (typeof value === "object" && value !== null) return Object.entries(value).flatMap(([key, inner]) => [key, ...strings(inner)]);
  return [];
}
