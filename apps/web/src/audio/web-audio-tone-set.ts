/**
 * WebAudioToneSet — Web Audio API implementation of the ToneSet interface.
 *
 * Synthesis parameters (frequencies, partial weights, envelope) come from
 * TONE_DESIGN in @breathe/core. The native (AVAudioEngine) ToneEngine reads
 * the same constants via the JS bridge and renders an identical waveform —
 * change a number in tone-design.ts, all three platforms move together.
 *
 * Chime shape (per the canonical design):
 *   Fundamental + 2× partial × 0.3 + 3× partial × 0.1
 *   Linear attack over `attackSec`, then exp(-decayLambda · t) decay
 *   Final scale × `masterScale` for headroom
 *
 * Each call to playInhale/playExhale schedules N chimes one second apart,
 * counting out the breath. Scheduling is sample-accurate against
 * AudioContext.currentTime — no JS-timer jitter.
 */

import { TONE_DESIGN, type ToneDesign, type ToneSet } from "@breathe/core";

interface ScheduledVoice {
  source: AudioBufferSourceNode;
}

class WebAudioToneSet implements ToneSet {
  private context: AudioContext;
  private masterGain: GainNode;
  private inhaleBuffer: AudioBuffer;
  private exhaleBuffer: AudioBuffer;
  private activeVoices: ScheduledVoice[] = [];

  constructor(design: ToneDesign = TONE_DESIGN) {
    this.context = new AudioContext();
    this.masterGain = this.context.createGain();
    this.masterGain.gain.setValueAtTime(1, this.context.currentTime);
    this.masterGain.connect(this.context.destination);

    this.inhaleBuffer = this._renderChime(design, design.inhaleFreqHz);
    this.exhaleBuffer = this._renderChime(design, design.exhaleFreqHz);
  }

  // ---------------------------------------------------------------------------
  // Public interface
  // ---------------------------------------------------------------------------

  playInhale({ durationSec }: { durationSec: number }): void {
    this._cancelActive();
    this._resetMasterGain();
    this._scheduleCounts(durationSec, this.inhaleBuffer);
  }

  playExhale({ durationSec }: { durationSec: number }): void {
    this._cancelActive();
    this._resetMasterGain();
    this._scheduleCounts(durationSec, this.exhaleBuffer);
  }

  fadeOut({ fadeSec }: { fadeSec: number }): void {
    const now = this.context.currentTime;
    this.masterGain.gain.cancelScheduledValues(now);
    this.masterGain.gain.setValueAtTime(this.masterGain.gain.value, now);
    this.masterGain.gain.linearRampToValueAtTime(0, now + fadeSec);

    const voices = this.activeVoices.slice();
    const stopAt = now + fadeSec;
    for (const { source } of voices) {
      try {
        source.stop(stopAt);
      } catch {
        // Already stopped — ignore.
      }
    }
    this.activeVoices = [];
  }

  stop(): void {
    const voices = this.activeVoices.slice();
    this.activeVoices = [];
    for (const { source } of voices) {
      try {
        source.stop();
      } catch {
        // Already stopped.
      }
      source.disconnect();
    }
    this.masterGain.disconnect();
    this.context.close().catch(() => {
      // Page may already be unloading.
    });
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /**
   * Pre-render one chime to an AudioBuffer using the same math the native
   * ToneEngine uses. Computed once per toneset, replayed cheaply per beat.
   */
  private _renderChime(d: ToneDesign, frequencyHz: number): AudioBuffer {
    const sampleRate = this.context.sampleRate;
    const frameCount = Math.floor(d.chimeDurationSec * sampleRate);
    const buffer = this.context.createBuffer(1, frameCount, sampleRate);
    const data = buffer.getChannelData(0);

    const twoPiF = 2 * Math.PI * frequencyHz;
    for (let i = 0; i < frameCount; i++) {
      const t = i / sampleRate;
      const envelope =
        t < d.attackSec
          ? t / d.attackSec
          : Math.exp(-(t - d.attackSec) * d.decayLambda);
      const fundamental = Math.sin(twoPiF * t);
      const partial2 = Math.sin(twoPiF * 2 * t) * d.partial2Weight;
      const partial3 = Math.sin(twoPiF * 3 * t) * d.partial3Weight;
      data[i] = (fundamental + partial2 + partial3) * envelope * d.masterScale;
    }
    return buffer;
  }

  /**
   * Schedule one chime per second across `durationSec`.
   * A 4-second inhale → 4 chimes at t=0, 1, 2, 3.
   */
  private _scheduleCounts(durationSec: number, buffer: AudioBuffer): void {
    const count = Math.max(1, Math.round(durationSec * TONE_DESIGN.chimesPerSec));
    const now = this.context.currentTime;
    const interval = 1 / TONE_DESIGN.chimesPerSec;
    for (let i = 0; i < count; i++) {
      this._schedulePlayAt(buffer, now + i * interval);
    }
  }

  private _schedulePlayAt(buffer: AudioBuffer, startAt: number): void {
    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(this.masterGain);
    source.start(startAt);

    source.onended = () => {
      source.disconnect();
      this.activeVoices = this.activeVoices.filter((v) => v.source !== source);
    };

    this.activeVoices.push({ source });
  }

  private _cancelActive(): void {
    const voices = this.activeVoices.slice();
    this.activeVoices = [];
    for (const { source } of voices) {
      try {
        source.stop();
      } catch {
        // Already stopped.
      }
      source.disconnect();
    }
  }

  private _resetMasterGain(): void {
    const now = this.context.currentTime;
    this.masterGain.gain.cancelScheduledValues(now);
    this.masterGain.gain.setValueAtTime(1, now);
  }
}

/**
 * Create a new WebAudioToneSet backed by a fresh AudioContext.
 * Call this once per session (AudioContext construction is heavy).
 */
export default function createWebAudioToneSet(design?: ToneDesign): ToneSet {
  return new WebAudioToneSet(design);
}
