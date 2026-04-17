import type { Phase, Session, SessionConfig, SessionEvent } from "./types.js";

/**
 * Validation errors thrown by createSession when config is invalid.
 */
export class InvalidSessionConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidSessionConfigError";
  }
}

function validate(config: SessionConfig): void {
  const positives: Array<keyof SessionConfig> = [
    "inhaleSec",
    "exhaleSec",
    "activeSec",
    "restSec",
    "rounds",
  ];
  for (const key of positives) {
    const value = config[key];
    if (!Number.isFinite(value) || value <= 0) {
      throw new InvalidSessionConfigError(
        `${key} must be a finite positive number, got ${String(value)}`,
      );
    }
  }
  if (!Number.isInteger(config.rounds)) {
    throw new InvalidSessionConfigError(
      `rounds must be an integer, got ${String(config.rounds)}`,
    );
  }
  const breathCycleSec = config.inhaleSec + config.exhaleSec;
  if (breathCycleSec > config.activeSec) {
    throw new InvalidSessionConfigError(
      `activeSec (${config.activeSec}) must fit at least one full breath cycle (inhale + exhale = ${breathCycleSec})`,
    );
  }
}

function computeTotalDurationSec(config: SessionConfig): number {
  return config.rounds * (config.activeSec + config.restSec);
}

/**
 * Phase 0 stub. The real state machine lands in Phase 1.
 *
 * It must pass the contract tests (test/session.test.ts) which encode the
 * expected event sequence for each preset + edge cases. An agent implementing
 * Phase 1 will flesh out start/tick with the actual logic.
 */
export function createSession(config: SessionConfig): Session {
  validate(config);
  const totalDurationSec = computeTotalDurationSec(config);

  let phase: Phase = { kind: "idle" };
  let stopped = false;

  return {
    start(_nowMs: number): readonly SessionEvent[] {
      if (stopped) return [];
      // TODO(phase-1): emit first inhale-start event and transition phase.
      void config;
      return [];
    },
    tick(_nowMs: number): readonly SessionEvent[] {
      if (stopped) return [];
      // TODO(phase-1): advance phase and return events due at or before nowMs.
      return [];
    },
    stop(): void {
      stopped = true;
      phase = { kind: "idle" };
    },
    get phase() {
      return phase;
    },
    get totalDurationSec() {
      return totalDurationSec;
    },
  };
}
