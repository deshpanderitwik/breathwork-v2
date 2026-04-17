import Foundation

/// Swift mirror of the TypeScript `ToneSet` interface from packages/core.
///
/// Two sides of the same contract:
///   - `packages/core/src/tone-set.ts` for web (Web Audio implementation)
///   - this file for Apple (AVAudioEngine implementation)
///
/// The state machine — shared via JavaScriptCore — emits events that the host
/// app turns into ToneSet calls. Audio is the one place we don't share code
/// between platforms, because Web Audio and AVAudioEngine have genuinely
/// different strengths.
public protocol ToneSet: AnyObject {
    /// Begin an inhale tone that should complete in `durationSec`.
    func playInhale(durationSec: Double)

    /// Begin an exhale tone that should complete in `durationSec`.
    func playExhale(durationSec: Double)

    /// Gracefully fade the currently-playing tone out.
    /// Used at active → rest boundaries so silence arrives intentionally.
    func fadeOut(fadeSec: Double)

    /// Hard stop. Cleanup audio resources.
    func stop()
}

/// Default fade envelope used at phase transitions within the active phase.
public enum ToneDefaults {
    public static let fadeInSec: Double = 0.04
    public static let fadeOutSec: Double = 0.08
    /// Longer trailing fade when active ends and rest begins.
    public static let activeToRestFadeSec: Double = 1.5
}
