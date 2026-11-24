import type { Mood, Species, Step } from "./config";

/**
 * Every word the model is given. A client picks a step, a mood and a species; it never
 * sends words of its own, so the relay cannot be used to draw anything else.
 *
 * The wording comes from the tests on real photos (docs/design/companion-characters.md,
 * "The relay"): naming what to keep (coat, markings, ears, face, tail, what it wears)
 * holds the likeness, "add nothing it is not wearing" stops invented collars, and "no
 * motion lines, no added symbols" stops the marks the model otherwise draws by a wagging
 * tail.
 */

const style =
  "Crisp square pixels, a limited warm palette, a clean dark outline, then a thin white sticker border around the whole figure.";

const ending =
  "Transparent background. No ground, no shadow, no text, no motion lines, no added symbols, nothing else in the picture.";

const same = (species: Species) =>
  `The first image is a pixel-art sticker of a ${species}. Draw the SAME character again, in exactly the same pixel-art sticker style, palette, proportions, outline and white sticker border as the first image, with the same coat, markings, face, ears, tail and anything it wears, and nothing it does not wear.`;

const sameFromPhoto = (species: Species) =>
  `${same(species)} The second image is a photo of the same real ${species}, to keep its likeness.`;

/** How each mood stands, by species: a dog waits with its leash, a cat by its bowl. */
const poses: Record<Mood, Record<Species, string>> = {
  fine: {
    dog: "Full body, standing on four legs, turned three-quarters toward the viewer with a friendly look.",
    cat: "Full body, sitting upright with its tail curled around its paws, turned three-quarters toward the viewer with a calm, friendly look.",
  },
  waiting: {
    dog: "New pose: sitting upright facing the viewer, holding a leash in its mouth, looking up hopefully, waiting to go for a walk.",
    cat: "New pose: sitting upright beside a small empty food bowl, looking up hopefully at the viewer, waiting to be fed.",
  },
  zoomies: {
    dog: "New pose: mid-run, joyful, mouth open and tongue out, ears flying back, all energy.",
    cat: "New pose: mid-pounce, playful, front paws stretched forward, tail up, eyes wide, all energy.",
  },
  asleep: {
    dog: 'New pose: curled up asleep, eyes closed, tail wrapped around, with a small "z" floating above.',
    cat: 'New pose: curled up asleep in a tight loaf, eyes closed, tail wrapped around, with a small "z" floating above.',
  },
};

/** What moves in each mood's animation; everything else holds still. */
const motions: Record<Mood, Record<Species, string>> = {
  fine: {
    dog: "it blinks once and its tail wags.",
    cat: "it blinks slowly once and the tip of its tail flicks.",
  },
  waiting: {
    dog: "it sits holding its leash, its tail wags, it blinks once, and the leash sways slightly.",
    cat: "it sits by its bowl, the tip of its tail flicks, and it blinks once.",
  },
  zoomies: {
    dog: "a run cycle in place, legs galloping, ears and tail bouncing, tongue out.",
    cat: "a playful bounce in place, front paws batting, tail swishing.",
  },
  asleep: {
    dog: "it sleeps, its body rising and falling gently with slow breathing, eyes staying closed, and the small z above it drifts up a little.",
    cat: "it sleeps, its body rising and falling gently with slow breathing, eyes staying closed, and the small z above it drifts up a little.",
  },
};

/** The first drawing, from the photo's cut-out alone. */
export function triesPrompt(species: Species): string {
  return [
    `Redraw the ${species} in this photo as a pixel-art sticker, like a character sprite from a 16-bit game.`,
    "It must be recognisably this same animal: keep its exact coat colour and texture, markings, ear shape, face, tail and anything it is wearing, and add nothing it is not wearing.",
    poses.fine[species],
    style,
    ending,
  ].join(" ");
}

/** A mood's still, from the chosen character and the photo. */
export function moodPrompt(species: Species, mood: Mood): string {
  const pose = mood === "fine" ? `Pose: ${poses.fine[species]}` : poses[mood][species];
  return [sameFromPhoto(species), pose, ending].join(" ");
}

/** A mood's animation, from that mood's still alone, so the character cannot change. */
export function animationPrompt(species: Species, mood: Mood): string {
  return [
    `The image is a pixel-art sticker of a ${species}.`,
    "Draw the SAME character in exactly the same pixel-art sticker style, palette, proportions, pose, outline and white sticker border, changing nothing about how it looks.",
    `Make a short looping animation of this pose: ${motions[mood][species]}`,
    "Nothing else moves, and the character stays the same size and in the same place in every frame.",
    ending,
  ].join(" ");
}

export function promptFor(step: Step, species: Species, mood: Mood | undefined): string {
  switch (step) {
    case "tries":
      return triesPrompt(species);
    case "mood":
      return moodPrompt(species, mood ?? "fine");
    case "animation":
      return animationPrompt(species, mood ?? "fine");
  }
}
