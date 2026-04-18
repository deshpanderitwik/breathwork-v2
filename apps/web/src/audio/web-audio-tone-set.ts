/**
 * WebAudioToneSet — Web Audio API implementation of the ToneSet interface.
 *
 * Inlined constants (do NOT import from @breathe/core to avoid circular deps):
 *   DEFAULT_FADE_IN_SEC  = 0.04
 *   DEFAULT_FADE_OUT_SEC = 0.08
 *
 * Tone design:
 *   Inhale (G4 base = 392 Hz): 5 oscillators ascending — 392, 415, 440, 466, 494 Hz
 *   Exhale (B4 base = 494 Hz): same 5 frequencies descending — 494, 466, 440, 415, 392 Hz
 *
 * All oscillators are scheduled upfront against context.currentTime for
 * sample-accurate timing — no JS-timer jitter.
 */

import type { ToneSet } from "@breathe/core";

// Inlined to avoid circular dependency risk.
const DEFAULT_FADE_IN_SEC = 0.04;
const DEFAULT_FADE_OUT_SEC = 0.08;

/** One pitch for inhale (rise), a lower pitch for exhale (release). */
const INHALE_FREQUENCY_HZ = 392; // G4
const EXHALE_FREQUENCY_HZ = 329.63; // E4 — minor third down from G4
const STAB_DURATION_SEC = 0.35;
const STAB_FADE_IN_SEC = 0.02;
const STAB_FADE_OUT_SEC = 0.18;

interface ScheduledVoice {
  oscillator: OscillatorNode;
  gain: GainNode;
}

class WebAudioToneSet implements ToneSet {
  private context: AudioContext;
  private masterGain: GainNode;
  private activeVoices: ScheduledVoice[] = [];

  constructor() {
    this.context = new AudioContext();
    this.masterGain = this.context.createGain();
    this.masterGain.gain.setValueAtTime(1, this.context.currentTime);
    this.masterGain.connect(this.context.destination);
  }

  // ---------------------------------------------------------------------------
  // Public interface
  // ---------------------------------------------------------------------------

  playInhale({ durationSec }: { durationSec: number }): void {
    this._cancelActive();
    this._resetMasterGain();
    this._scheduleCounts(durationSec, INHALE_FREQUENCY_HZ);
  }

  playExhale({ durationSec }: { durationSec: number }): void {
    this._cancelActive();
    this._resetMasterGain();
    this._scheduleCounts(durationSec, EXHALE_FREQUENCY_HZ);
  }

  fadeOut({ fadeSec }: { fadeSec: number }): void {
    const now = this.context.currentTime;
    this.masterGain.gain.cancelScheduledValues(now);
    this.masterGain.gain.setValueAtTime(this.masterGain.gain.value, now);
    this.masterGain.gain.linearRampToValueAtTime(0, now + fadeSec);

    // Stop all oscillators after the fade completes.
    const voices = this.activeVoices.slice();
    const stopAt = now + fadeSec;
    for (const { oscillator } of voices) {
      try {
        oscillator.stop(stopAt);
      } catch {
        // Already stopped — ignore.
      }
    }

    // Clean up references once the fade is done.
    const cleanupDelay = (fadeSec + 0.1) * 1000;
    setTimeout(() => {
      this._disconnectVoices(voices);
    }, cleanupDelay);

    this.activeVoices = [];
  }

  stop(): void {
    const voices = this.activeVoices.slice();
    this.activeVoices = [];

    for (const { oscillator, gain } of voices) {
      try {
        oscillator.stop();
      } catch {
        // Already stopped.
      }
      oscillator.disconnect();
      gain.disconnect();
    }

    this.masterGain.disconnect();
    this.context.close().catch(() => {
      // Ignore errors on close — page may already be unloading.
    });
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /**
   * Schedule one stab per second across `durationSec` at `frequencyHz`.
   * A 4-second inhale → 4 beeps at t=0, 1, 2, 3.
   */
  private _scheduleCounts(durationSec: number, frequencyHz: number): void {
    const count = Math.max(1, Math.round(durationSec));
    const now = this.context.currentTime;
    for (let i = 0; i < count; i++) {
      this._scheduleStabAt(now + i, frequencyHz);
    }
  }

  /** Schedule a single short sine stab at the given AudioContext time. */
  private _scheduleStabAt(startAt: number, frequencyHz: number): void {
    const endAt = startAt + STAB_DURATION_SEC;

    const osc = this.context.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(frequencyHz, startAt);

    const gainNode = this.context.createGain();
    gainNode.gain.setValueAtTime(0, startAt);

    const fadeInEnd = startAt + STAB_FADE_IN_SEC;
    gainNode.gain.linearRampToValueAtTime(1, fadeInEnd);
    gainNode.gain.linearRampToValueAtTime(0, endAt);

    osc.connect(gainNode);
    gainNode.connect(this.masterGain);

    osc.start(startAt);
    osc.stop(endAt);

    osc.onended = () => {
      osc.disconnect();
      gainNode.disconnect();
      this.activeVoices = this.activeVoices.filter((v) => v.oscillator !== osc);
    };

    this.activeVoices.push({ oscillator: osc, gain: gainNode });
  }

  /** Stop and discard all currently scheduled oscillators immediately. */
  private _cancelActive(): void {
    const voices = this.activeVoices.slice();
    this.activeVoices = [];
    for (const { oscillator, gain } of voices) {
      try {
        oscillator.stop();
      } catch {
        // Already stopped.
      }
      oscillator.disconnect();
      gain.disconnect();
    }
  }

  /**
   * Snap the master gain back to 1 and clear any scheduled ramps.
   * Called before each new play so a preceding fadeOut does not carry over.
   */
  private _resetMasterGain(): void {
    const now = this.context.currentTime;
    this.masterGain.gain.cancelScheduledValues(now);
    this.masterGain.gain.setValueAtTime(1, now);
  }

  /** Disconnect a specific set of voices without touching activeVoices. */
  private _disconnectVoices(voices: ScheduledVoice[]): void {
    for (const { oscillator, gain } of voices) {
      oscillator.disconnect();
      gain.disconnect();
    }
  }
}

// ---------------------------------------------------------------------------
// Public factory — the class stays unexported.
// ---------------------------------------------------------------------------

/**
 * Create a new WebAudioToneSet backed by a fresh AudioContext.
 * Call this once per session (AudioContext construction is heavy).
 */
export default function createWebAudioToneSet(): ToneSet {
  return new WebAudioToneSet();
}
