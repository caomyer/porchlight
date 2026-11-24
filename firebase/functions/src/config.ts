/**
 * Every number the relay runs on, in one place: the model and how it is asked, the limits,
 * what a token costs, and how the function itself is deployed.
 */
export const config = {
  model: {
    name: "gpt-image-2.6-flare",
    endpoint: "https://api.openai.com/v1/images/edits",
    /** A still is drawn at this size and handed back at `stillSide`. */
    stillSize: "1024x1024",
    stillSide: 512,
    /**
     * One frame of an animation. The model lays the frames out on a sheet, so nine frames
     * of 512 make a 1536 sheet, which fits its pixel budget; 1024 does not, and 256 is
     * under its minimum.
     */
    animationSize: "512x512",
    animationFrames: 9,
    animationFrameMs: 140,
    /** Three tries to pick from, then the chosen character's moods and animations. */
    triesQuality: "low",
    finalQuality: "medium",
    triesPerRound: 3,
    /** One attempt may take this long; a still took 15 to 30 seconds in testing. */
    attemptTimeoutMs: 75_000,
    /** One more attempt after a rate limit, a timeout or a server error. */
    retries: 1,
    retryDelayMs: 1_500,
  },

  limits: {
    /** Rounds of tries for one companion, for life. */
    roundsPerCompanion: 3,
    /** Times one mood's still may be drawn for one companion, for life. */
    drawsPerMood: 3,
    /** Times one mood's animation may be drawn for one companion, for life. */
    drawsPerAnimation: 3,
    companionsPerHousehold: 6,
    /**
     * Calls one household, and one signed-in installation, may make in a day. A whole
     * character is 8 calls (a round, three more moods, four animations), so this leaves
     * room for two pets with redraws and stops a runaway client.
     */
    callsPerHouseholdPerDay: 40,
    callsPerInstallationPerDay: 40,
  },

  cost: {
    /** US dollars per million tokens, from the model's pricing page. */
    textInputPerMillion: 5,
    imageInputPerMillion: 8,
    outputPerMillion: 30,
    /** What a call is assumed to cost until its real usage is known, in dollars. */
    estimate: { tries: 0.09, mood: 0.06, animation: 0.08 },
    /** The whole project stops drawing for the day past this, in dollars. */
    defaultDailyCeiling: 5,
  },

  input: {
    /** A cut-out or a reference: a PNG no longer than this on its longest side. */
    maxSide: 1024,
    minSide: 64,
    /** Base64 characters: about 4.5 MB of PNG. */
    maxBase64Length: 6_000_000,
  },

  deploy: {
    /** One region, the cheapest tier, near the model's own servers. */
    region: "us-central1",
    /**
     * A call waits on the model for up to two attempts; the function is given a little
     * more than that.
     */
    timeoutSeconds: 180,
    /** Resizing a 1024 PNG and holding three drawings fits well inside this. */
    memory: "512MiB",
    /** The work is waiting on the network, so one instance serves several calls. */
    concurrency: 16,
    /** No instance is kept warm: the first call after a quiet spell starts one. */
    minInstances: 0,
    maxInstances: 4,
  },
} as const;

export type Step = "tries" | "mood" | "animation";
export const steps: readonly Step[] = ["tries", "mood", "animation"];
export type Mood = "fine" | "waiting" | "zoomies" | "asleep";
export const moods: readonly Mood[] = ["fine", "waiting", "zoomies", "asleep"];
export type Species = "dog" | "cat";
export const speciesList: readonly Species[] = ["dog", "cat"];
