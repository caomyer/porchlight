import sharp from "sharp";

import type { ImageModel, ModelRequest, ModelResult } from "./model";

/**
 * A stand-in for the image model, for the emulator and the tests: it draws a plain square
 * for a still and a tiny many-frame GIF for an animation, and reports token counts like
 * the real one. It is only ever used when the functions run in the emulator.
 */
export async function fakePng(side = 1024, color = { r: 217, g: 101, b: 59, alpha: 1 }): Promise<Buffer> {
  return sharp({ create: { width: side, height: side, channels: 4, background: color } }).png().toBuffer();
}

/** A valid GIF of `frames` one-pixel frames. */
export function fakeGif(frames = 9): Buffer {
  const header = Buffer.from("GIF89a", "latin1");
  // A 1x1 screen with a two-colour table.
  const screen = Buffer.from([0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff]);
  const control = Buffer.from([0x21, 0xf9, 0x04, 0x01, 0x0e, 0x00, 0x00, 0x00]);
  const image = Buffer.from([0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00]);
  const parts = [header, screen];
  for (let frame = 0; frame < frames; frame += 1) parts.push(control, image);
  parts.push(Buffer.from([0x3b]));
  return Buffer.concat(parts);
}

export interface FakeOptions {
  /** Called with each request, so a test can see what the model was asked. */
  seen?: (request: ModelRequest) => void;
  /** Thrown in place of drawing, when set. */
  failure?: () => Error | undefined;
  /** How long a drawing takes, to let calls overlap. */
  delayMs?: number;
}

export function fakeModel(options: FakeOptions = {}): ImageModel {
  return {
    async draw(request): Promise<ModelResult> {
      options.seen?.(request);
      if (options.delayMs) await new Promise((resolve) => setTimeout(resolve, options.delayMs));
      const failure = options.failure?.();
      if (failure) throw failure;
      const outputs: Buffer[] = [];
      for (let index = 0; index < request.count; index += 1) {
        outputs.push(request.format === "gif" ? fakeGif() : await fakePng());
      }
      return { outputs, usage: { textTokens: 150, imageTokens: 768 * request.images.length, outputTokens: 1400 * request.count }, attempts: 1 };
    },
  };
}
