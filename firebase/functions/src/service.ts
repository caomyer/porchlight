import { config } from "./config";
import { hashed, parseAllowance, parseDraw, type DrawRequest, type DrawResponse } from "./contract";
import { RelayError } from "./errors";
import { downscaled, gifFrames, pngSize } from "./images";
import type { Ledger, Reservation } from "./ledger";
import type { Log } from "./log";
import { usageDollars, type ImageModel, type ModelRequest } from "./model";
import { promptFor } from "./prompts";

export interface Caller {
  /** The signed-in installation's id, when the app signs in. */
  installationId?: string;
}

export interface Relay {
  draw(data: unknown, caller: Caller): Promise<DrawResponse>;
  allowance(data: unknown): Promise<{ roundsLeft: number }>;
}

export interface Parts {
  model: ImageModel;
  ledger: Ledger;
  log: Log;
  now: () => Date;
  /** The day's spending ceiling for the whole project, in dollars. */
  dailyCeiling: number;
}

/** What the model is asked for at each step. */
function modelRequest(request: DrawRequest, household: string): ModelRequest {
  const base = { prompt: promptFor(request.step, request.species, request.mood), safetyIdentifier: household };
  switch (request.step) {
    case "tries":
      return {
        ...base, images: [request.cutout], size: config.model.stillSize, quality: config.model.triesQuality,
        count: config.model.triesPerRound, format: "png",
      };
    case "mood":
      return {
        ...base, images: [request.reference!, request.cutout], size: config.model.stillSize, quality: config.model.finalQuality,
        count: 1, format: "png",
      };
    case "animation":
      // From the mood's still alone: with the photo beside it the model redraws the pet.
      return {
        ...base, images: [request.reference!], size: config.model.animationSize, quality: config.model.finalQuality,
        count: 1, format: "gif",
      };
  }
}

/** A still as the app keeps it, or an error when the model sent something else. */
async function still(output: Buffer): Promise<string> {
  if (!pngSize(output)) throw new RelayError("unavailable", "model sent no PNG");
  return (await downscaled(output)).toString("base64");
}

export function relay(parts: Parts): Relay {
  const { model, ledger, log, now } = parts;

  return {
    async draw(data, caller) {
      const started = now().getTime();
      const request = parseDraw(data);
      const household = hashed("household", request.householdId);
      const companion = hashed("companion", request.companionId);
      const fields = { household, companion, step: request.step, mood: request.mood, species: request.species };

      let reservation: Reservation;
      try {
        reservation = await ledger.reserve({
          household, companion, step: request.step, mood: request.mood,
          installation: caller.installationId ? hashed("installation", caller.installationId) : undefined,
          day: now().toISOString().slice(0, 10),
          estimate: config.cost.estimate[request.step],
          ceiling: parts.dailyCeiling,
        });
      } catch (error) {
        if (error instanceof RelayError) {
          const event = error.reason === "spend ceiling" ? log.error : log.warn;
          event("draw turned down", { ...fields, errorClass: error.code, reason: error.reason });
          throw error;
        }
        log.error("ledger failed", { ...fields, errorClass: "ledger" });
        throw new RelayError("unavailable", "ledger");
      }

      try {
        const result = await model.draw(modelRequest(request, household));
        let response: DrawResponse;
        if (request.step === "tries") {
          response = { images: await Promise.all(result.outputs.map(still)), roundsLeft: reservation.roundsLeft };
        } else if (request.step === "mood") {
          response = { image: await still(result.outputs[0]!) };
        } else {
          const gif = result.outputs[0]!;
          const frames = gifFrames(gif);
          if (!frames || frames < 2) throw new RelayError("unavailable", "model sent no animation");
          response = { gif: gif.toString("base64"), frames };
        }
        const dollars = usageDollars(result.usage);
        await ledger.settle(reservation, dollars).catch(() => log.error("settle failed", { ...fields, errorClass: "ledger" }));
        log.info("drew", { ...fields, ...result.usage, dollars, attempts: result.attempts, ms: now().getTime() - started });
        return response;
      } catch (error) {
        // Nothing was handed over, so nothing is used up.
        await ledger.release(reservation).catch(() => log.error("release failed", { ...fields, errorClass: "ledger" }));
        const failure = error instanceof RelayError ? error : new RelayError("unavailable", "internal");
        log.warn("draw failed", { ...fields, errorClass: failure.code, reason: failure.reason, ms: now().getTime() - started });
        throw failure;
      }
    },

    async allowance(data) {
      const request = parseAllowance(data);
      try {
        return { roundsLeft: await ledger.roundsLeft(hashed("household", request.householdId), hashed("companion", request.companionId)) };
      } catch {
        log.error("ledger failed", { errorClass: "ledger" });
        throw new RelayError("unavailable", "ledger");
      }
    },
  };
}
