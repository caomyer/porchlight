import sharp from "sharp";
import { describe, expect, it } from "vitest";

import { fakeGif } from "../../src/fake";
import { downscaled, gifFrames, pngSize } from "../../src/images";
import { png } from "../support";

describe("reading a PNG's size", () => {
  it("reads width and height from the first chunk", async () => {
    expect(pngSize(await png(300, 120))).toEqual({ width: 300, height: 120 });
  });

  it("says nothing for bytes that are not a PNG", () => {
    expect(pngSize(Buffer.from("GIF89a and then some more bytes to get past the length"))).toBeUndefined();
    expect(pngSize(Buffer.alloc(4))).toBeUndefined();
    expect(pngSize(fakeGif())).toBeUndefined();
  });
});

describe("handing a still back", () => {
  it("makes it 512 and keeps its transparency", async () => {
    const clear = await sharp({ create: { width: 1024, height: 1024, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .composite([{ input: await png(400, 400), left: 312, top: 312 }])
      .png()
      .toBuffer();
    const small = await downscaled(clear);
    expect(pngSize(small)).toEqual({ width: 512, height: 512 });
    const { data, info } = await sharp(small).raw().toBuffer({ resolveWithObject: true });
    expect(info.channels).toBe(4);
    // A corner is clear, the middle is solid.
    expect(data[3]).toBe(0);
    expect(data[(256 * 512 + 256) * 4 + 3]).toBe(255);
  });
});

describe("counting an animation's frames", () => {
  it("counts each frame", () => {
    expect(gifFrames(fakeGif(9))).toBe(9);
    expect(gifFrames(fakeGif(2))).toBe(2);
  });

  it("counts the frames of a real encoder's GIF", async () => {
    const frame = (red: number) => sharp({ create: { width: 8, height: 8, channels: 4, background: { r: red, g: 200, b: 30, alpha: 1 } } }).raw().toBuffer();
    const pages = Buffer.concat([await frame(10), await frame(120), await frame(240)]);
    const gif = await sharp(pages, { raw: { width: 8, height: 24, channels: 4, pageHeight: 8 } })
      .gif({ loop: 0, delay: [100, 100, 100] })
      .toBuffer();
    expect(gifFrames(gif)).toBe(3);
  });

  it("says nothing for bytes that are not a GIF", async () => {
    expect(gifFrames(await png())).toBeUndefined();
    expect(gifFrames(Buffer.from("GIF89a"))).toBeUndefined();
  });
});
