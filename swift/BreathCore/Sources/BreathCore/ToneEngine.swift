import AVFoundation
import BreathRuntime

/// AVAudioEngine-backed chime player.
///
/// Synthesis parameters (frequencies, partials, envelope) come from a
/// `ToneDesign` injected at init — typically read from `BreathRuntime` so
/// they match the JS-canonical TONE_DESIGN. Same numbers as the web side
/// uses; same waveform produced.
///
/// On iOS, configures AVAudioSession for `.playback` so chimes continue
/// with the screen locked (requires `UIBackgroundModes: audio` in Info.plist).
public final class ToneEngine {
    private let sampleRate: Double = 44100
    private let design: ToneDesign

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inhaleBuffer: AVAudioPCMBuffer!
    private var exhaleBuffer: AVAudioPCMBuffer!
    private var started = false

    public init(design: ToneDesign) {
        self.design = design
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        inhaleBuffer = makeChime(frequency: Float(design.inhaleFreqHz))
        exhaleBuffer = makeChime(frequency: Float(design.exhaleFreqHz))
    }

    private func makeChime(frequency: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(design.chimeDurationSec * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        let sr = Float(sampleRate)
        let attackTime = Float(design.attackSec)
        let lambda = Float(design.decayLambda)
        let p2 = Float(design.partial2Weight)
        let p3 = Float(design.partial3Weight)
        let scale = Float(design.masterScale)

        for i in 0..<Int(frameCount) {
            let t = Float(i) / sr
            let envelope: Float = t < attackTime
                ? (t / attackTime)
                : exp(-(t - attackTime) * lambda)
            let fundamental = sin(2.0 * .pi * frequency * t)
            let partial2 = sin(2.0 * .pi * frequency * 2.0 * t) * p2
            let partial3 = sin(2.0 * .pi * frequency * 3.0 * t) * p3
            data[i] = (fundamental + partial2 + partial3) * envelope * scale
        }
        return buffer
    }

    private func ensureStarted() {
        guard !started else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true, options: [])
        #endif
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            // Audio unavailable — silent failure, session continues visually.
        }
    }

    /// Play one inhale chime starting now. Single-shot — count granularity
    /// lives in the state machine (one inhale-count event = one call here),
    /// so pause/resume cancels nothing because nothing is queued past now.
    public func playInhaleChime() {
        ensureStarted()
        player.scheduleBuffer(inhaleBuffer, at: nil, options: [], completionHandler: nil)
    }

    /// Play one exhale chime starting now. Single-shot.
    public func playExhaleChime() {
        ensureStarted()
        player.scheduleBuffer(exhaleBuffer, at: nil, options: [], completionHandler: nil)
    }

    public func fadeOut(fadeSec: Double) {
        // Short chimes taper naturally via their exp decay — flush the queue.
        // (`fadeSec` is currently unused; the buffer envelope handles the
        // tail. Future work: tweenable mixer-volume ramp for explicit fades.)
        _ = fadeSec
        player.stop()
        player.play()
    }

    public func stop() {
        player.stop()
        engine.stop()
        started = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}
