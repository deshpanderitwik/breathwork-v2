import AVFoundation
import Foundation

/// MVP tone set: pure sine oscillators with gentle fade envelopes.
///
/// From the PRD:
///   - Inhale: G4 (392 Hz) — 5 sine tones ascending over the inhale duration
///   - Exhale: B4 (494 Hz, major third of G) — 5 sine tones descending
///
/// Reuse candidates from breathwork-v1/Sources/BreathEngine.swift:
///   - AVAudioEngine + AVAudioPlayerNode plumbing
///   - PCM buffer generation with an attack envelope (lines 42-45)
///   - Sine wave formula with optional partials (lines 47-51)
///
/// Phase 1 implements. Phase 0 only locks the contract.
public final class SineToneSet: ToneSet {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    public init() {
        // TODO(phase-1): attach player to mainMixerNode, configure format,
        // start engine lazily on first play call.
    }

    public func playInhale(durationSec: Double) {
        _ = durationSec
        // TODO(phase-1): synthesize G4 buffer with fade-in/out envelope.
    }

    public func playExhale(durationSec: Double) {
        _ = durationSec
        // TODO(phase-1): synthesize B4 buffer with fade-in/out envelope.
    }

    public func fadeOut(fadeSec: Double) {
        _ = fadeSec
        // TODO(phase-1): ramp mainMixerNode volume to 0 over fadeSec, then
        // stop player. Restore volume on next play call.
    }

    public func stop() {
        player.stop()
        engine.stop()
    }
}
