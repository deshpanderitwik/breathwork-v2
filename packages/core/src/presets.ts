import type { SessionConfig } from "./types.js";

/**
 * Built-in presets from the PRD.
 *
 * - Calm:  gentle 4/6 rhythm, 8 minute session.
 * - Focus: symmetric 4/4 rhythm, shorter rest, 7 minute session.
 * - Deep:  long exhale 5/8, more rounds, 7.5 minute session.
 *
 * Users can edit any field; doing so switches the UI to "Custom".
 */
export type PresetId = "calm" | "focus" | "deep";

export const PRESETS: Readonly<Record<PresetId, SessionConfig>> = Object.freeze({
  calm: {
    inhaleSec: 4,
    exhaleSec: 6,
    activeSec: 90,
    restSec: 30,
    rounds: 4,
  },
  focus: {
    inhaleSec: 4,
    exhaleSec: 4,
    activeSec: 120,
    restSec: 20,
    rounds: 3,
  },
  deep: {
    inhaleSec: 5,
    exhaleSec: 8,
    activeSec: 60,
    restSec: 30,
    rounds: 5,
  },
});

export const DEFAULT_PRESET: PresetId = "calm";
