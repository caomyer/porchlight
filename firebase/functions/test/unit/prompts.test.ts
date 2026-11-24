import { describe, expect, it } from "vitest";

import { moods, speciesList, steps } from "../../src/config";
import { animationPrompt, moodPrompt, promptFor, triesPrompt } from "../../src/prompts";

const every = steps.flatMap((step) => speciesList.flatMap((species) => moods.map((mood) => ({ step, species, mood, text: promptFor(step, species, mood) }))));

describe("the words the model is given", () => {
  it("always ask for a transparent sticker with nothing added", () => {
    for (const { text } of every) {
      expect(text).toContain("Transparent background.");
      expect(text).toContain("no motion lines");
      expect(text).toContain("no added symbols");
      expect(text).toContain("no text");
      expect(text).toContain("white sticker border");
    }
  });

  it("name the species and nothing about one particular pet", () => {
    for (const { species, text } of every) {
      expect(text).toContain(species);
      for (const word of ["apricot", "harness", "poodle", "tuft", "green collar", "Yo-Yo", "navy"]) {
        expect(text.toLowerCase()).not.toContain(word.toLowerCase());
      }
    }
  });

  it("ask the first drawing to keep the animal as it is and add nothing it does not wear", () => {
    for (const species of speciesList) {
      const text = triesPrompt(species);
      expect(text).toContain("recognisably this same animal");
      expect(text).toContain("add nothing it is not wearing");
      expect(text).toContain("16-bit");
    }
  });

  it("ask a mood for the same character in a new pose", () => {
    expect(moodPrompt("dog", "waiting")).toContain("leash in its mouth");
    expect(moodPrompt("cat", "waiting")).toContain("food bowl");
    expect(moodPrompt("cat", "waiting")).not.toContain("leash");
    for (const species of speciesList) {
      for (const mood of moods) {
        const text = moodPrompt(species, mood);
        expect(text).toContain("SAME character");
        expect(text).toContain("second image is a photo");
      }
    }
  });

  it("ask an animation to move one thing and hold the rest", () => {
    for (const species of speciesList) {
      for (const mood of moods) {
        const text = animationPrompt(species, mood);
        expect(text).toContain("short looping animation");
        expect(text).toContain("Nothing else moves");
        expect(text).toContain("same size and in the same place in every frame");
        expect(text).not.toContain("photo");
      }
    }
  });

  it("differ for every step, mood and species", () => {
    const moodTexts = every.filter((entry) => entry.step !== "tries").map((entry) => entry.text);
    expect(new Set(moodTexts).size).toBe(moodTexts.length);
    expect(triesPrompt("dog")).not.toBe(triesPrompt("cat"));
  });
});
