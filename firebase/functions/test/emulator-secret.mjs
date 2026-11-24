// The functions emulator wants a value for every secret a function names. The tests never
// call the real image model, so a stand-in is written when none is there. The file is
// git-ignored, and a real key never belongs in it.
import { existsSync, writeFileSync } from "node:fs";

if (!existsSync(".secret.local")) writeFileSync(".secret.local", "OPENAI_API_KEY=not-a-real-key\n");
