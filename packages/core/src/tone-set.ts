/**
 * ToneSet — the one place where each platform owns its own implementation.
 *
 * The state machine is shared. The audio is not. Web Audio and AVAudioEngine
 * have genuinely different strengths, and fade envelopes feel different
 * through each. Keeping this seam explicit is the whole point.
 *
 * The MVP tone set is simple sine oscillators:
 *   - Inhale: G4 (392 Hz) — 5 sine tones ascending over the inhale duration
 *   - Exhale: B4 (494 Hz) — 5 sine tones descending over the exhale duration
 *
 * Both implementations MUST:
 *   - Fade in gently at the start of each tone
 *   - Fade out gently at the end
 *   - Avoid hard cuts (sine discontinuities produce clicks)
 *   - Support a longer trailing fade (1–2s) when the active phase ends
 *
 * Architecture for the future:
 *   - The ToneSet interface is the swap point for more musical tones later.
 *   - Different ToneSet implementations can deliver different tone palettes.
 */
/**
 * Handle returned by scheduled chime playback. Allows the host to cancel a
 * chime that was queued in the lookahead window but has not yet sounded —
 * needed when the user pauses between scheduling and audible firing.
 *
 * cancel() is a no-op once the chime has already played.
 */
export interface ScheduledChime {
  cancel(): void;
}

export interface ToneSet {
  /**
   * Anchor the audio clock to session t=0. Called once when the session
   * starts, before any scheduleChimeAt() calls. Each implementation captures
   * its own clock (AudioContext.currentTime on web, sample-time on Swift)
   * so it can map session-relative ms to its own future-scheduling units.
   */
  beginSession(): void;

  /**
   * Schedule one inhale chime to sound at exactly `sessionMs` past
   * beginSession(). The audio engine's own high-precision clock decides
   * when the buffer plays, so polling jitter on the calling side does not
   * affect the audible moment.
   *
   * If the target time is in the past relative to the audio clock (e.g. the
   * caller is late), the chime plays as soon as possible — same behavior as
   * the legacy playInhaleChime().
   */
  scheduleInhaleChimeAt(sessionMs: number): ScheduledChime;

  /** As above, for exhale. */
  scheduleExhaleChimeAt(sessionMs: number): ScheduledChime;

  /**
   * Play one inhale chime starting now. Legacy single-shot path — kept for
   * platforms that have not yet adopted the scheduled API. New code should
   * prefer scheduleInhaleChimeAt() for sample-accurate timing.
   */
  playInhaleChime(): void;

  /** Play one exhale chime starting now. Single-shot. Legacy. */
  playExhaleChime(): void;

  /**
   * Gracefully fade any currently-ringing tone out.
   * Used at active → rest boundaries so silence arrives intentionally.
   */
  fadeOut(params: { fadeSec: number }): void;

  /** Hard stop. Cleanup audio resources. */
  stop(): void;
}

/** Default fade envelope used at phase transitions within the active phase. */
export const DEFAULT_FADE_IN_SEC = 0.04;
export const DEFAULT_FADE_OUT_SEC = 0.08;

/** Longer trailing fade when active ends and rest begins. */
export const ACTIVE_TO_REST_FADE_SEC = 1.5;
