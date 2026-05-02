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
export interface ToneSet {
  /**
   * Play one inhale chime starting now. Single-shot — the state machine
   * emits one count event per beat and the engine plays one chime per
   * event. Pause/resume "just works" because there's nothing queued past
   * the moment of the call.
   */
  playInhaleChime(): void;

  /** Play one exhale chime starting now. Single-shot. */
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
