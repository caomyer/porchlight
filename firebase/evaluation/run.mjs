// Draws characters from real photos with the relay's own prompts and request code, to
// judge likeness and consistency by eye and to measure what a character costs.
//
//   npm --prefix ../functions run build
//   node run.mjs --photos <folder> --out <folder> [--budget 5] [--animations fine|all|none]
//
// Each photo is named `<name>.<dog|cat>.jpg` (or .png). The key is read from the
// OPENAI_API_KEY environment variable and is never printed. Nothing is uploaded anywhere
// but to the image model. Not part of CI: it spends money.
import { execFileSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, writeFileSync, existsSync, appendFileSync } from "node:fs";
import { createRequire } from "node:module";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(here, "..", "functions", "package.json"));
const lib = join(here, "..", "functions", "lib", "src");
if (!existsSync(join(lib, "model.js"))) {
  console.error("Build the functions first: npm --prefix ../functions run build");
  process.exit(2);
}
const { config, moods } = require(join(lib, "config.js"));
const { openAIModel, usageDollars } = require(join(lib, "model.js"));
const { promptFor } = require(join(lib, "prompts.js"));
const { downscaled, gifFrames } = require(join(lib, "images.js"));
const sharp = require("sharp");

function option(name, fallback) {
  const at = process.argv.indexOf(`--${name}`);
  return at > 0 && process.argv[at + 1] ? process.argv[at + 1] : fallback;
}
const photos = option("photos");
const out = option("out", join(here, "out"));
const budget = Number.parseFloat(option("budget", "5"));
const animations = option("animations", "fine");
if (!photos) {
  console.error("usage: node run.mjs --photos <folder> --out <folder> [--budget 5] [--animations fine|all|none]");
  process.exit(2);
}
if (!process.env.OPENAI_API_KEY) {
  console.error("Set OPENAI_API_KEY in the environment first (it is never printed).");
  process.exit(2);
}

mkdirSync(out, { recursive: true });
const model = openAIModel(() => process.env.OPENAI_API_KEY);
const usagePath = join(out, "usage.tsv");
if (!existsSync(usagePath)) writeFileSync(usagePath, "pet\tstep\tmood\tseconds\ttext\timage\toutput\tdollars\tresult\n");
let spent = 0;
const summary = [];

/** One call to the model, counted against the budget, or nil with the reason it failed. */
async function draw(pet, step, mood, request) {
  const estimate = config.cost.estimate[step];
  if (spent + estimate > budget) {
    console.log(`  ${step} ${mood ?? ""}: skipped, the budget of $${budget} would be passed`);
    return undefined;
  }
  const started = Date.now();
  try {
    const result = await model.draw({ ...request, prompt: promptFor(step, pet.species, mood), safetyIdentifier: "evaluation" });
    const dollars = usageDollars(result.usage);
    spent += dollars;
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    appendFileSync(usagePath, [pet.name, step, mood ?? "", seconds, result.usage.textTokens, result.usage.imageTokens, result.usage.outputTokens, dollars.toFixed(4), "ok"].join("\t") + "\n");
    console.log(`  ${step} ${mood ?? ""}: ${seconds}s, $${dollars.toFixed(3)}, attempts ${result.attempts}`);
    return result.outputs;
  } catch (error) {
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    const reason = error?.code ? `${error.code}: ${error.reason}` : "failed";
    appendFileSync(usagePath, [pet.name, step, mood ?? "", seconds, "", "", "", "0", reason].join("\t") + "\n");
    console.log(`  ${step} ${mood ?? ""}: ${reason}`);
    return undefined;
  }
}

const cell = 256;
const paper = { r: 245, g: 239, b: 228, alpha: 1 };
const night = { r: 30, g: 26, b: 23, alpha: 1 };

/** An image fitted into one square of a sheet, on the sheet's own colour. */
async function tile(bytes, background) {
  return sharp(bytes).resize(cell - 16, cell - 16, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .extend({ top: 8, bottom: 8, left: 8, right: 8, background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .flatten({ background }).png().toBuffer();
}

/** Rows of images as one picture: each row is a list of image bytes, with its own colour. */
async function sheet(rows, path) {
  const columns = Math.max(...rows.map((row) => row.images.length));
  const composites = [];
  for (const [y, row] of rows.entries()) {
    for (const [x, image] of row.images.entries()) {
      composites.push({ input: await tile(image, row.dark ? night : paper), left: x * cell, top: y * cell });
    }
  }
  await sharp({ create: { width: columns * cell, height: rows.length * cell, channels: 4, background: paper } })
    .composite(composites).png().toFile(path);
}

/** Every frame of a GIF, as PNGs. */
async function framesOf(gif) {
  const count = gifFrames(gif) ?? 1;
  const frames = [];
  for (let page = 0; page < count; page += 1) frames.push(await sharp(gif, { page }).png().toBuffer());
  return frames;
}

const files = readdirSync(photos).filter((file) => /\.(dog|cat)\.(jpe?g|png)$/i.test(file)).sort();
if (files.length === 0) {
  console.error("No photos named <name>.<dog|cat>.jpg in", photos);
  process.exit(2);
}

for (const file of files) {
  const [name, species] = basename(file).split(".");
  const pet = { name, species };
  const folder = join(out, name);
  mkdirSync(folder, { recursive: true });
  console.log(`${name} (${species})`);
  const record = { name, species, tries: 0, moods: [], animations: [], failed: [] };
  summary.push(record);

  // The cut-out, as the app makes it on the device.
  const cutoutPath = join(folder, "cutout.png");
  try {
    execFileSync("swift", [join(here, "cutout.swift"), join(photos, file), cutoutPath], { stdio: ["ignore", "pipe", "pipe"] });
  } catch {
    console.log("  no subject found in the photo");
    record.failed.push("cutout");
    continue;
  }
  const cutout = readFileSync(cutoutPath);
  const photo = await sharp(join(photos, file)).rotate().png().toBuffer();

  const tries = await draw(pet, "tries", undefined, {
    images: [cutout], size: config.model.stillSize, quality: config.model.triesQuality, count: config.model.triesPerRound, format: "png",
  });
  if (!tries) {
    record.failed.push("tries");
    continue;
  }
  record.tries = tries.length;
  const stills = { fine: await downscaled(tries[0]) };
  for (const [index, image] of tries.entries()) writeFileSync(join(folder, `try-${index + 1}.png`), await downscaled(image));

  // The first try stands in for the one a person would pick.
  for (const mood of moods.filter((mood) => mood !== "fine")) {
    const drawn = await draw(pet, "mood", mood, {
      images: [stills.fine, cutout], size: config.model.stillSize, quality: config.model.finalQuality, count: 1, format: "png",
    });
    if (!drawn) {
      record.failed.push(`mood ${mood}`);
      continue;
    }
    stills[mood] = await downscaled(drawn[0]);
    writeFileSync(join(folder, `mood-${mood}.png`), stills[mood]);
    record.moods.push(mood);
  }

  const loops = {};
  const wanted = animations === "all" ? moods : animations === "fine" ? ["fine"] : [];
  for (const mood of wanted) {
    if (!stills[mood]) continue;
    const drawn = await draw(pet, "animation", mood, {
      images: [stills[mood]], size: config.model.animationSize, quality: config.model.finalQuality, count: 1, format: "gif",
    });
    if (!drawn) {
      record.failed.push(`animation ${mood}`);
      continue;
    }
    loops[mood] = drawn[0];
    writeFileSync(join(folder, `animation-${mood}.gif`), drawn[0]);
    record.animations.push({ mood, frames: gifFrames(drawn[0]) ?? 0, bytes: drawn[0].length });
  }

  const rows = [
    { images: [photo, cutout, ...(await Promise.all(tries.map((image) => downscaled(image))))] },
    { images: moods.filter((mood) => stills[mood]).map((mood) => stills[mood]), dark: true },
  ];
  for (const mood of Object.keys(loops)) rows.push({ images: await framesOf(loops[mood]) });
  await sheet(rows, join(out, `${name}.png`));
}

writeFileSync(join(out, "summary.json"), JSON.stringify({ model: config.model.name, spent: Number(spent.toFixed(4)), pets: summary }, null, 2) + "\n");
console.log(`Spent $${spent.toFixed(2)} of a budget of $${budget}. Sheets are in ${out}.`);
