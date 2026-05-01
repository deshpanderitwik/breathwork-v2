/**
 * All shared types for the breath state machine.
 *
 * This file defines the contract that both the web surface and the Apple
 * surfaces (via JavaScriptCore) rely on. Change it carefully.
 */

/**
 * Configuration for a single session.
 * All durations are in seconds. Rounds is a positive integer.
 */
export interface SessionConfig {
  inhaleSec: number;
  exhaleSec: number;
  activeSec: number;
  restSec: number;
  rounds: number;
}

/**
 * The phase a session is currently in.
 *
 * Transitions:
 *   idle → active-inhale → active-exhale → ... → rest → active-inhale → ... → complete
 */
export type Phase =
  | { kind: "idle" }
  | { kind: "active-inhale"; round: number; startedAtMs: number }
  | { kind: "active-exhale"; round: number; startedAtMs: number }
  | { kind: "rest"; round: number; startedAtMs: number }
  | { kind: "complete" };

/**
 * Events emitted by the state machine.
 *
 * Surfaces consume events to drive UI and audio. The state machine itself is
 * pure — it never plays a sound or touches a DOM. Swift drives the clock,
 * Swift handles the events.
 */
export type SessionEvent =
  | {
      kind: "inhale-start";
      round: number;
      durationSec: number;
      atMs: number;
    }
  | {
      kind: "exhale-start";
      round: number;
      durationSec: number;
      atMs: number;
    }
  | {
      kind: "rest-start";
      round: number;
      durationSec: number;
      /** Trailing fade applied to the last tone as active ends. 1–2s feels intentional. */
      fadeOutSec: number;
      atMs: number;
    }
  | {
      kind: "round-complete";
      round: number;
      atMs: number;
    }
  | {
      kind: "session-complete";
      atMs: number;
    };

/**
 * The stateful session object.
 *
 * Lifecycle:
 *   const s = createSession(config);
 *   s.start(nowMs)       // returns initial events (e.g. inhale-start for round 1)
 *   s.tick(nowMs)        // called on a loop; returns events to fire "now"
 *   s.pause(nowMs)       // freeze effective time; no further events fire
 *   s.resume(nowMs)      // unfreeze; events scheduled for "now" or earlier fire
 *   s.stop()             // abort; no further events
 *
 * The state machine is pure and deterministic: given the same config and the
 * same sequence of tick timestamps (with pause/resume calls in fixed places),
 * it always emits the same events at the same effective timestamps.
 *
 * Pause arithmetic lives here, not in hosts. Hosts pass strictly monotonic
 * `nowMs` (e.g. `performance.now() - startPerfMs` on web) and call
 * `pause()` / `resume()` at user gestures. The TS engine internally tracks
 * total paused time and freezes the queue cursor while paused.
 */
export interface Session {
  /** Start the session. Returns the events fired at t=0 (typically an inhale-start). */
  start(nowMs: number): readonly SessionEvent[];

  /** Advance time. Returns events to fire at or before effective time. */
  tick(nowMs: number): readonly SessionEvent[];

  /** Pause: freeze effective time. Idempotent — no-op if already paused or stopped. */
  pause(nowMs: number): void;

  /** Resume: unfreeze. Idempotent — no-op if not paused or stopped. */
  resume(nowMs: number): void;

  /** Abort. Idempotent. No further events will be emitted. */
  stop(): void;

  /** Current phase. Read-only snapshot. */
  readonly phase: Phase;

  /** True while paused (between pause() and resume()). */
  readonly isPaused: boolean;

  /**
   * Effective elapsed time in ms — wall clock with paused intervals subtracted.
   * Hosts use this for UI (timeline progress, "Round N of M" derivations).
   * Returns the frozen value while paused.
   */
  effectiveMs(nowMs: number): number;

  /** Total duration of a completed session in seconds, given the config. */
  readonly totalDurationSec: number;
}
