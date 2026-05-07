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
 * Single-shot: each playInhaleChime/playExhaleChime call schedules ONE
 * chime at "now." The state machine emits one count event per beat, so
 * count granularity lives upstream — pause cancels nothing because nothing
 * is queued past the moment of the call.
 */

import {
  TONE_DESIGN,
  type ScheduledChime,
  type ToneDesign,
  type ToneSet,
} from "@breathe/core";

interface ScheduledVoice {
  source: AudioBufferSourceNode;
}

class WebAudioToneSet implements ToneSet {
  private context: AudioContext;
  private masterGain: GainNode;
  private inhaleBuffer: AudioBuffer;
  private exhaleBuffer: AudioBuffer;
  private activeVoices: ScheduledVoice[] = [];
  /**
   * AudioContext.currentTime captured at session start. Maps session-relative
   * ms (from event.atMs) to absolute audio-clock seconds:
   *   audioTime = sessionStartCtxTime + sessionMs / 1000
   */
  private sessionStartCtxTime: number | null = null;

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

  beginSession(): void {
    this.sessionStartCtxTime = this.context.currentTime;
  }

  scheduleInhaleChimeAt(sessionMs: number): ScheduledChime {
    return this._scheduleAt(this.inhaleBuffer, sessionMs);
  }

  scheduleExhaleChimeAt(sessionMs: number): ScheduledChime {
    return this._scheduleAt(this.exhaleBuffer, sessionMs);
  }

  playInhaleChime(): void {
    this._resetMasterGain();
    this._schedulePlayAt(this.inhaleBuffer, this.context.currentTime);
  }

  playExhaleChime(): void {
    this._resetMasterGain();
    this._schedulePlayAt(this.exhaleBuffer, this.context.currentTime);
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
    this.sessionStartCtxTime = null;
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
   *
   * The last 2 ms taper linearly to zero so the buffer ends at silence —
   * otherwise the natural exp decay leaves the final sample at ~4% and the
   * speaker hardware clicks on the step to 0 (especially audible on the
   * iPhone built-in speaker).
   */
  private _renderChime(d: ToneDesign, frequencyHz: number): AudioBuffer {
    const sampleRate = this.context.sampleRate;
    const frameCount = Math.floor(d.chimeDurationSec * sampleRate);
    const buffer = this.context.createBuffer(1, frameCount, sampleRate);
    const data = buffer.getChannelData(0);

    const twoPiF = 2 * Math.PI * frequencyHz;
    const releaseSamples = Math.max(1, Math.floor(0.002 * sampleRate));
    const releaseStart = frameCount - releaseSamples;
    for (let i = 0; i < frameCount; i++) {
      const t = i / sampleRate;
      const envelope =
        t < d.attackSec
          ? t / d.attackSec
          : Math.exp(-(t - d.attackSec) * d.decayLambda);
      const release = i < releaseStart ? 1 : (frameCount - i) / releaseSamples;
      const fundamental = Math.sin(twoPiF * t);
      const partial2 = Math.sin(twoPiF * 2 * t) * d.partial2Weight;
      const partial3 = Math.sin(twoPiF * 3 * t) * d.partial3Weight;
      data[i] =
        (fundamental + partial2 + partial3) * envelope * release * d.masterScale;
    }
    return buffer;
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

  /**
   * Sample-accurate scheduling against the AudioContext clock. The audio
   * engine's hardware clock decides when the buffer plays, so polling jitter
   * on the caller no longer affects the audible moment.
   *
   * If beginSession() was never called, falls back to "play now" — same
   * behavior as the legacy path. If the target is in the past (caller is
   * late), AudioContext clamps to currentTime and plays immediately.
   */
  private _scheduleAt(
    buffer: AudioBuffer,
    sessionMs: number,
  ): ScheduledChime {
    this._resetMasterGain();
    const target =
      this.sessionStartCtxTime !== null
        ? this.sessionStartCtxTime + sessionMs / 1000
        : this.context.currentTime;
    const startAt = Math.max(target, this.context.currentTime);

    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(this.masterGain);
    source.start(startAt);

    let played = false;
    source.onended = () => {
      played = true;
      source.disconnect();
      this.activeVoices = this.activeVoices.filter((v) => v.source !== source);
    };
    this.activeVoices.push({ source });

    return {
      cancel: () => {
        if (played) return;
        try {
          source.stop();
        } catch {
          // Already stopped — fine.
        }
      },
    };
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
