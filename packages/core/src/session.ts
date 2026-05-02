import { ACTIVE_TO_REST_FADE_SEC } from "./tone-set.js";
import type { Phase, Session, SessionConfig, SessionEvent } from "./types.js";

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

function buildSchedule(
  config: SessionConfig,
  startMs: number,
  totalDurationSec: number,
): Array<{ atMs: number; event: SessionEvent }> {
  const scheduled: Array<{ atMs: number; event: SessionEvent }> = [];
  const cycleSec = config.inhaleSec + config.exhaleSec;

  for (let r = 1; r <= config.rounds; r++) {
    const roundStartMs =
      startMs + (r - 1) * (config.activeSec + config.restSec) * 1000;

    // Emit one count event per second within the active phase. Each
    // breath cycle = inhaleSec inhale-counts followed by exhaleSec
    // exhale-counts. We bail out the moment a count would land at or past
    // the active phase boundary so the rest-start event isn't preceded
    // by a stray count.
    for (let c = 0; ; c++) {
      const inhaleOffsetSec = c * cycleSec;
      const exhaleOffsetSec = inhaleOffsetSec + config.inhaleSec;
      if (inhaleOffsetSec >= config.activeSec) break;

      for (let i = 0; i < config.inhaleSec; i++) {
        const offsetSec = inhaleOffsetSec + i;
        if (offsetSec >= config.activeSec) break;
        const atMs = roundStartMs + offsetSec * 1000;
        scheduled.push({
          atMs,
          event: {
            kind: "inhale-count",
            round: r,
            beatIndex: i,
            beatsInPhase: config.inhaleSec,
            atMs,
          },
        });
      }

      if (exhaleOffsetSec < config.activeSec) {
        for (let i = 0; i < config.exhaleSec; i++) {
          const offsetSec = exhaleOffsetSec + i;
          if (offsetSec >= config.activeSec) break;
          const atMs = roundStartMs + offsetSec * 1000;
          scheduled.push({
            atMs,
            event: {
              kind: "exhale-count",
              round: r,
              beatIndex: i,
              beatsInPhase: config.exhaleSec,
              atMs,
            },
          });
        }
      }
    }

    const restAtMs = roundStartMs + config.activeSec * 1000;
    scheduled.push({
      atMs: restAtMs,
      event: {
        kind: "rest-start",
        round: r,
        durationSec: config.restSec,
        fadeOutSec: ACTIVE_TO_REST_FADE_SEC,
        atMs: restAtMs,
      },
    });

    const roundCompleteAtMs = restAtMs + config.restSec * 1000;
    scheduled.push({
      atMs: roundCompleteAtMs,
      event: { kind: "round-complete", round: r, atMs: roundCompleteAtMs },
    });
  }

  const sessionCompleteAtMs = startMs + totalDurationSec * 1000;
  scheduled.push({
    atMs: sessionCompleteAtMs,
    event: { kind: "session-complete", atMs: sessionCompleteAtMs },
  });

  // Stable sort — equal-atMs items preserve insertion order (round-complete before session-complete)
  scheduled.sort((a, b) => a.atMs - b.atMs);

  return scheduled;
}

function phaseFromEvent(event: SessionEvent): Phase | null {
  switch (event.kind) {
    case "inhale-count":
      return event.beatIndex === 0
        ? { kind: "active-inhale", round: event.round, startedAtMs: event.atMs }
        : null;
    case "exhale-count":
      return event.beatIndex === 0
        ? { kind: "active-exhale", round: event.round, startedAtMs: event.atMs }
        : null;
    case "rest-start":
      return { kind: "rest", round: event.round, startedAtMs: event.atMs };
    case "session-complete":
      return { kind: "complete" };
    case "round-complete":
      return null;
    default:
      return null;
  }
}

export function createSession(config: SessionConfig): Session {
  validate(config);
  const totalDurationSec = computeTotalDurationSec(config);

  let phase: Phase = { kind: "idle" };
  let stopped = false;
  let queue: Array<{ atMs: number; event: SessionEvent }> = [];
  let cursor = 0;
  // Pause arithmetic. While paused, effective time freezes at `pausedAtMs`
  // (the nowMs passed to pause()). On resume, totalPausedMs accumulates the
  // wall-clock duration of the pause, so subsequent ticks compute effective
  // time as nowMs - totalPausedMs.
  let pausedAtMs: number | null = null;
  let totalPausedMs = 0;

  function effectiveMs(nowMs: number): number {
    if (pausedAtMs !== null) return pausedAtMs - totalPausedMs;
    return nowMs - totalPausedMs;
  }

  function drain(nowMs: number): readonly SessionEvent[] {
    const effective = effectiveMs(nowMs);
    const events: SessionEvent[] = [];
    while (cursor < queue.length) {
      const entry = queue[cursor];
      if (!entry || entry.atMs > effective) break;
      cursor++;
      events.push(entry.event);
      const next = phaseFromEvent(entry.event);
      if (next !== null) phase = next;
    }
    return events;
  }

  return {
    start(nowMs: number): readonly SessionEvent[] {
      if (stopped) return [];
      queue = buildSchedule(config, 0, totalDurationSec);
      cursor = 0;
      pausedAtMs = null;
      totalPausedMs = nowMs; // so effective time starts at 0 regardless of nowMs
      return drain(nowMs);
    },

    tick(nowMs: number): readonly SessionEvent[] {
      if (stopped || queue.length === 0) return [];
      return drain(nowMs);
    },

    pause(nowMs: number): void {
      if (stopped || pausedAtMs !== null) return;
      pausedAtMs = nowMs;
    },

    resume(nowMs: number): void {
      if (stopped || pausedAtMs === null) return;
      totalPausedMs += nowMs - pausedAtMs;
      pausedAtMs = null;
    },

    stop(): void {
      stopped = true;
      phase = { kind: "idle" };
      queue = [];
      pausedAtMs = null;
    },

    effectiveMs(nowMs: number): number {
      return effectiveMs(nowMs);
    },

    get phase() {
      return phase;
    },

    get isPaused() {
      return pausedAtMs !== null;
    },

    get totalDurationSec() {
      return totalDurationSec;
    },
  };
}
