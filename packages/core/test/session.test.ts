import { describe, expect, it } from "vitest";
import {
  InvalidSessionConfigError,
  PRESETS,
  createSession,
  type SessionConfig,
  type SessionEvent,
} from "../src/index.js";

/**
 * Contract tests for the session state machine.
 *
 * These tests define the behavior Phase 1 must deliver. They are the spec.
 * Drive the session with a fake clock by stepping tick() from t=0 to the end
 * of the session and collecting every event.
 */

function runSession(
  config: SessionConfig,
  stepMs = 100,
): { events: SessionEvent[]; totalSec: number } {
  const session = createSession(config);
  const total = session.totalDurationSec;
  const events: SessionEvent[] = [];
  events.push(...session.start(0));
  for (let t = stepMs; t <= total * 1000 + stepMs; t += stepMs) {
    events.push(...session.tick(t));
  }
  return { events, totalSec: total };
}

describe("createSession / totalDurationSec", () => {
  it("computes 4 × (90 + 30) = 480s for the Calm preset", () => {
    const s = createSession(PRESETS.calm);
    expect(s.totalDurationSec).toBe(480);
  });

  it("computes 3 × (120 + 20) = 420s for the Focus preset", () => {
    const s = createSession(PRESETS.focus);
    expect(s.totalDurationSec).toBe(420);
  });

  it("computes 5 × (60 + 30) = 450s for the Deep preset", () => {
    const s = createSession(PRESETS.deep);
    expect(s.totalDurationSec).toBe(450);
  });
});

describe("createSession validation", () => {
  it("rejects non-positive durations", () => {
    expect(() =>
      createSession({ ...PRESETS.calm, inhaleSec: 0 }),
    ).toThrow(InvalidSessionConfigError);
  });

  it("rejects non-integer rounds", () => {
    expect(() => createSession({ ...PRESETS.calm, rounds: 2.5 })).toThrow(
      InvalidSessionConfigError,
    );
  });

  it("rejects activeSec shorter than one breath cycle", () => {
    expect(() =>
      createSession({
        inhaleSec: 4,
        exhaleSec: 6,
        activeSec: 5,
        restSec: 10,
        rounds: 1,
      }),
    ).toThrow(InvalidSessionConfigError);
  });
});

/**
 * Event sequence: one count event per beat (1 chime/sec).
 * For Calm (4/6/90/30/4): each round has 9 cycles, each cycle has
 * 4 inhale-counts + 6 exhale-counts = 10 counts/cycle.
 * Per round: 36 inhale-counts + 54 exhale-counts.
 * Across 4 rounds: 144 inhale-counts + 216 exhale-counts.
 */
describe("session event sequence", () => {
  it("Calm preset emits the expected number of each event kind", () => {
    const { events } = runSession(PRESETS.calm);
    const kinds = events.reduce<Record<string, number>>((acc, e) => {
      acc[e.kind] = (acc[e.kind] ?? 0) + 1;
      return acc;
    }, {});

    expect(kinds["inhale-count"]).toBe(144);
    expect(kinds["exhale-count"]).toBe(216);
    expect(kinds["rest-start"]).toBe(4);
    expect(kinds["round-complete"]).toBe(4);
    expect(kinds["session-complete"]).toBe(1);
  });

  it("starts with an inhale-count(beatIndex=0) at atMs=0 for round 1", () => {
    const { events } = runSession(PRESETS.calm);
    const first = events[0];
    expect(first?.kind).toBe("inhale-count");
    if (first?.kind === "inhale-count") {
      expect(first.round).toBe(1);
      expect(first.atMs).toBe(0);
      expect(first.beatIndex).toBe(0);
      expect(first.beatsInPhase).toBe(4);
    }
  });

  it("emits session-complete as the final event at total duration", () => {
    const { events, totalSec } = runSession(PRESETS.calm);
    const last = events[events.length - 1];
    expect(last?.kind).toBe("session-complete");
    expect(last?.atMs).toBe(totalSec * 1000);
  });

  it("rest-start has fadeOutSec >= 1 (intentional silence)", () => {
    const { events } = runSession(PRESETS.calm);
    const rests = events.filter((e) => e.kind === "rest-start");
    for (const rest of rests) {
      if (rest.kind === "rest-start") {
        expect(rest.fadeOutSec).toBeGreaterThanOrEqual(1);
      }
    }
  });
});

describe("session pause / resume", () => {
  it("isPaused reflects pause/resume state", () => {
    const s = createSession(PRESETS.calm);
    expect(s.isPaused).toBe(false);
    s.start(0);
    expect(s.isPaused).toBe(false);
    s.pause(1000);
    expect(s.isPaused).toBe(true);
    s.resume(2000);
    expect(s.isPaused).toBe(false);
  });

  it("emits no new events while paused", () => {
    const s = createSession(PRESETS.calm);
    s.start(0); // initial event(s) at t=0
    s.tick(3500); // somewhere in the middle of the first inhale
    s.pause(3700);
    // Tick repeatedly during pause; no events should fire even though wall
    // clock time advances past the next event's effective time.
    expect(s.tick(5000)).toEqual([]);
    expect(s.tick(10000)).toEqual([]);
    expect(s.tick(50000)).toEqual([]);
  });

  it("shifts subsequent events by the pause duration on resume", () => {
    const s = createSession(PRESETS.calm);
    const initial = s.start(0); // [inhale-count(beatIndex=0)@0]
    expect(initial[0]?.kind).toBe("inhale-count");

    // Drain inhale-counts at t=1000, 2000, 3000 before pausing so the
    // cursor is at the next pending event (the t=4000 exhale-count).
    s.tick(3500);

    // Pause at wall 3500; the first exhale-count is due at effective 4000.
    s.pause(3500);
    // Resume 5000ms later (wall time 8500). Effective time since start
    // is now 8500 - 5000 = 3500. Still before 4000.
    s.resume(8500);
    expect(s.tick(8900)).toEqual([]); // effective 3900, still before 4000

    // Tick at wall 9001 → effective 4001 → exhale-count(beatIndex=0) fires.
    const events = s.tick(9001);
    expect(events.length).toBeGreaterThanOrEqual(1);
    const first = events[0];
    expect(first?.kind).toBe("exhale-count");
    if (first?.kind === "exhale-count") {
      expect(first.beatIndex).toBe(0);
      expect(first.beatsInPhase).toBe(6);
    }
  });

  it("pause/resume are idempotent and safe before start or after stop", () => {
    const s = createSession(PRESETS.calm);
    expect(() => s.pause(0)).not.toThrow();
    expect(() => s.resume(0)).not.toThrow();
    s.start(0);
    s.pause(1000);
    s.pause(2000); // already paused — no-op
    expect(s.isPaused).toBe(true);
    s.stop();
    expect(() => s.pause(3000)).not.toThrow();
    expect(() => s.resume(4000)).not.toThrow();
  });
});
