import sharp from "sharp";

import { config } from "./config";
import { RelayError } from "./errors";

const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/**
 * A client's image, checked before anything is spent on it: base64 of a PNG, within the
 * length cap, and no larger than the size the app is meant to send.
 */
export function decodePng(value: unknown, field: string): Buffer {
  if (typeof value !== "string" || value.length === 0) throw new RelayError("invalid", `${field} missing`);
  if (value.length > config.input.maxBase64Length) throw new RelayError("invalid", `${field} too long`);
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value) || value.length % 4 !== 0) {
    throw new RelayError("invalid", `${field} not base64`);
  }
  const bytes = Buffer.from(value, "base64");
  const size = pngSize(bytes);
  if (!size) throw new RelayError("invalid", `${field} not a PNG`);
  const longest = Math.max(size.width, size.height);
  const shortest = Math.min(size.width, size.height);
  if (longest > config.input.maxSide || shortest < config.input.minSide) {
    throw new RelayError("invalid", `${field} size ${size.width}x${size.height}`);
  }
  return bytes;
}

/** A PNG's width and height from its first chunk, or nil when the bytes are not a PNG. */
export function pngSize(bytes: Buffer): { width: number; height: number } | undefined {
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(pngSignature)) return undefined;
  if (bytes.toString("latin1", 12, 16) !== "IHDR") return undefined;
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  if (width === 0 || height === 0) return undefined;
  return { width, height };
}

/** A drawn still at the size the app keeps, its transparency intact. */
export async function downscaled(png: Buffer, side: number = config.model.stillSide): Promise<Buffer> {
  return sharp(png)
    .resize(side, side, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 }, kernel: "lanczos3" })
    .png({ compressionLevel: 9 })
    .toBuffer();
}

/**
 * How many frames a GIF holds, by walking its blocks, or nil when the bytes are not a GIF.
 * The app is told what it really got, never what was asked for.
 */
export function gifFrames(bytes: Buffer): number | undefined {
  const header = bytes.toString("latin1", 0, 6);
  if (bytes.length < 14 || (header !== "GIF89a" && header !== "GIF87a")) return undefined;
  let at = 13;
  const flags = bytes[10] ?? 0;
  if (flags & 0x80) at += 3 * (1 << ((flags & 0x07) + 1));
  let frames = 0;
  const skipSubBlocks = () => {
    while (at < bytes.length) {
      const length = bytes[at] ?? 0;
      at += 1 + length;
      if (length === 0) return;
    }
  };
  while (at < bytes.length) {
    const block = bytes[at];
    if (block === 0x3b) return frames;
    if (block === 0x21) {
      at += 2;
      skipSubBlocks();
    } else if (block === 0x2c) {
      frames += 1;
      const local = bytes[at + 9] ?? 0;
      at += 10;
      if (local & 0x80) at += 3 * (1 << ((local & 0x07) + 1));
      at += 1;
      skipSubBlocks();
    } else {
      return undefined;
    }
  }
  return frames > 0 ? frames : undefined;
}
