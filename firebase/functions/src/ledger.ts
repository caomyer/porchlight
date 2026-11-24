import { FieldValue, type Firestore } from "firebase-admin/firestore";

import { config, type Mood, type Step } from "./config";
import { RelayError } from "./errors";

/** What a call wants to use up, in hashed ids. */
export interface Claim {
  household: string;
  companion: string;
  /** The signed-in installation, when the app signs in; nil otherwise. */
  installation?: string;
  step: Step;
  mood?: Mood;
  /** The day the call counts toward, as "2026-11-24" in UTC. */
  day: string;
  /** What the call is assumed to cost until it is known, in dollars. */
  estimate: number;
  /** The day's ceiling for the whole project, in dollars. */
  ceiling: number;
}

/** A claim that was granted, to settle or give back when the call ends. */
export interface Reservation {
  claim: Claim;
  /** Rounds of tries this companion has left after this call. */
  roundsLeft: number;
}

/**
 * The relay's memory: how much each companion has used, how many calls a household made
 * today, and what the project spent today. It holds counters under hashed ids and nothing
 * else: no photo, no drawing, no name.
 */
export interface Ledger {
  /** Takes what the call needs, all or nothing, or says which limit stands in the way. */
  reserve(claim: Claim): Promise<Reservation>;
  /** The call drew: its real cost replaces the estimate. */
  settle(reservation: Reservation, dollars: number): Promise<void>;
  /** The call drew nothing: its round or redraw and its estimate are given back. */
  release(reservation: Reservation): Promise<void>;
  roundsLeft(household: string, companion: string): Promise<number>;
}

interface CompanionUse {
  rounds?: number;
  moods?: Partial<Record<Mood, number>>;
  animations?: Partial<Record<Mood, number>>;
}

const micro = (dollars: number) => Math.round(dollars * 1_000_000);

function used(use: CompanionUse): number {
  const sum = (counts?: Partial<Record<Mood, number>>) => Object.values(counts ?? {}).reduce((total, value) => total + (value ?? 0), 0);
  return (use.rounds ?? 0) + sum(use.moods) + sum(use.animations);
}

/** Adds to the counter the step uses, or says the limit is reached. `by` is 1 or -1. */
function counted(use: CompanionUse, step: Step, mood: Mood | undefined, by: number): CompanionUse {
  const next: CompanionUse = { rounds: use.rounds ?? 0, moods: { ...use.moods }, animations: { ...use.animations } };
  const { roundsPerCompanion, drawsPerMood, drawsPerAnimation } = config.limits;
  if (step === "tries") {
    const rounds = (next.rounds ?? 0) + by;
    if (rounds > roundsPerCompanion) throw new RelayError("limit-reached", "rounds");
    next.rounds = Math.max(0, rounds);
    return next;
  }
  const key = mood ?? "fine";
  const bucket = step === "mood" ? next.moods! : next.animations!;
  const value = (bucket[key] ?? 0) + by;
  if (value > (step === "mood" ? drawsPerMood : drawsPerAnimation)) throw new RelayError("limit-reached", step);
  bucket[key] = Math.max(0, value);
  return next;
}

export function firestoreLedger(db: Firestore): Ledger {
  const householdRef = (household: string) => db.collection("households").doc(household);
  const companionRef = (household: string, companion: string) => householdRef(household).collection("companions").doc(companion);
  const householdDay = (household: string, day: string) => householdRef(household).collection("days").doc(day);
  const installationDay = (installation: string, day: string) => db.collection("installations").doc(installation).collection("days").doc(day);
  const spendRef = (day: string) => db.collection("spend").doc(day);

  return {
    async reserve(claim) {
      return db.runTransaction(async (tx) => {
        const { household, companion, installation, day } = claim;
        const [home, pet, homeDay, spend, device] = await Promise.all([
          tx.get(householdRef(household)),
          tx.get(companionRef(household, companion)),
          tx.get(householdDay(household, day)),
          tx.get(spendRef(day)),
          installation ? tx.get(installationDay(installation, day)) : Promise.resolve(undefined),
        ]);

        const spent = (spend.get("micro") as number | undefined) ?? 0;
        if (spent + micro(claim.estimate) > micro(claim.ceiling)) throw new RelayError("unavailable", "spend ceiling");

        const homeCalls = (homeDay.get("calls") as number | undefined) ?? 0;
        if (homeCalls >= config.limits.callsPerHouseholdPerDay) throw new RelayError("limit-reached", "household day");
        const deviceCalls = (device?.get("calls") as number | undefined) ?? 0;
        if (device && deviceCalls >= config.limits.callsPerInstallationPerDay) throw new RelayError("limit-reached", "installation day");

        const companions = (home.get("companions") as string[] | undefined) ?? [];
        if (!companions.includes(companion)) {
          if (companions.length >= config.limits.companionsPerHousehold) throw new RelayError("limit-reached", "companions");
          tx.set(householdRef(household), { companions: [...companions, companion] }, { merge: true });
        }

        const next = counted((pet.data() as CompanionUse | undefined) ?? {}, claim.step, claim.mood, 1);
        tx.set(companionRef(household, companion), next);
        tx.set(householdDay(household, day), { calls: homeCalls + 1 });
        if (installation) tx.set(installationDay(installation, day), { calls: deviceCalls + 1 });
        tx.set(spendRef(day), { micro: spent + micro(claim.estimate) }, { merge: true });
        return { claim, roundsLeft: config.limits.roundsPerCompanion - (next.rounds ?? 0) };
      });
    },

    async settle(reservation, dollars) {
      const { claim } = reservation;
      await spendRef(claim.day).set({ micro: FieldValue.increment(micro(dollars) - micro(claim.estimate)) }, { merge: true });
    },

    async release(reservation) {
      const { claim } = reservation;
      await db.runTransaction(async (tx) => {
        const [home, pet] = await Promise.all([
          tx.get(householdRef(claim.household)),
          tx.get(companionRef(claim.household, claim.companion)),
        ]);
        const next = counted((pet.data() as CompanionUse | undefined) ?? {}, claim.step, claim.mood, -1);
        if (used(next) === 0) {
          // Nothing was ever drawn for this companion: it gives its place in the household back.
          tx.delete(companionRef(claim.household, claim.companion));
          const companions = ((home.get("companions") as string[] | undefined) ?? []).filter((id) => id !== claim.companion);
          tx.set(householdRef(claim.household), { companions }, { merge: true });
        } else {
          tx.set(companionRef(claim.household, claim.companion), next);
        }
        tx.set(spendRef(claim.day), { micro: FieldValue.increment(-micro(claim.estimate)) }, { merge: true });
      });
    },

    async roundsLeft(household, companion) {
      const pet = await companionRef(household, companion).get();
      return config.limits.roundsPerCompanion - ((pet.get("rounds") as number | undefined) ?? 0);
    },
  };
}
