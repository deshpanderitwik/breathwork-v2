/**
 * Tone design — the shared sound parameters for inhale and exhale chimes.
 *
 * The state machine is platform-agnostic; audio synthesis is platform-native
 * (Web Audio on the web, AVAudioEngine on Apple). What used to differ between
 * those two implementations was not just *how* sound was produced but *what*
 * was produced — different pitches, different envelopes, different partial
 * weights. This file is the single source of truth for the *what*.
 *
 * Implementations read these values and synthesize accordingly. Change a
 * number here, all three platforms move together.
 *
 * Canonical palette today:
 *   - Inhale chime at G4 (392 Hz)
 *   - Exhale chime at E4 (329.63 Hz) — a minor third below, signalling release
 *   - Each chime: fundamental + 2nd partial × 0.3 + 3rd partial × 0.1
 *   - Envelope: 8 ms linear attack, then exp(-decayLambda · t)
 *   - Duration 0.6 s, master scale 0.25
 *   - One chime per second of breath duration (4-second inhale → 4 chimes)
 */
export interface ToneDesign {
  /** Inhale chime fundamental, Hz. */
  inhaleFreqHz: number;
  /** Exhale chime fundamental, Hz. */
  exhaleFreqHz: number;
  /** Total length of one chime, seconds (attack + decay tail). */
  chimeDurationSec: number;
  /** Linear ramp from 0 to peak, seconds. */
  attackSec: number;
  /** Exponential decay rate λ in `exp(-λ · t)` after attack ends. */
  decayLambda: number;
  /** Amplitude of the 2nd partial relative to fundamental. */
  partial2Weight: number;
  /** Amplitude of the 3rd partial relative to fundamental. */
  partial3Weight: number;
  /** Final scale applied to the summed waveform — keeps headroom. */
  masterScale: number;
  /** Chimes per second of breath duration. 1 = "count out the seconds." */
  chimesPerSec: number;
}

export const TONE_DESIGN: Readonly<ToneDesign> = Object.freeze({
  inhaleFreqHz: 392.0, // G4
  exhaleFreqHz: 329.63, // E4 — minor third down from G4
  chimeDurationSec: 0.6,
  attackSec: 0.008,
  decayLambda: 5.5,
  partial2Weight: 0.3,
  partial3Weight: 0.1,
  masterScale: 0.25,
  chimesPerSec: 1.0,
});
