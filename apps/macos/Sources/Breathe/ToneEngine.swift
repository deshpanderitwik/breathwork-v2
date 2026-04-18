import AVFoundation

/// Chime generation lifted from breathwork-v1/Sources/BreathEngine.swift.
/// Fundamental + 2nd partial (×0.3) + 3rd partial (×0.1), 8ms linear attack,
/// exp(-5.5·t) decay, overall scale ×0.25. Warmer than pure sines.
final class ToneEngine {
    private let sampleRate: Double = 44100
    private let chimeDuration: Double = 0.6

    // G4 inhale, D5 exhale (a fifth up) — inherited from v1.
    private let inhaleFreq: Float = 392.0
    private let exhaleFreq: Float = 587.33

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inhaleBuffer: AVAudioPCMBuffer!
    private var exhaleBuffer: AVAudioPCMBuffer!
    private var started = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        inhaleBuffer = makeChime(frequency: inhaleFreq)
        exhaleBuffer = makeChime(frequency: exhaleFreq)
    }

    private func makeChime(frequency: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(chimeDuration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        let sr = Float(sampleRate)

        for i in 0..<Int(frameCount) {
            let t = Float(i) / sr
            let attackTime: Float = 0.008
            let envelope: Float = t < attackTime
                ? (t / attackTime)
                : exp(-(t - attackTime) * 5.5)
            let fundamental = sin(2.0 * .pi * frequency * t)
            let partial2 = sin(2.0 * .pi * frequency * 2.0 * t) * 0.3
            let partial3 = sin(2.0 * .pi * frequency * 3.0 * t) * 0.1
            data[i] = (fundamental + partial2 + partial3) * envelope * 0.25
        }
        return buffer
    }

    private func ensureStarted() {
        guard !started else { return }
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            // Audio unavailable — silent failure, session continues visually.
        }
    }

    /// Schedule one chime per count-second across `durationSec`.
    /// A 4s inhale → 4 chimes at t=0,1,2,3 relative to now.
    func playInhale(durationSec: Double) {
        ensureStarted()
        scheduleCounts(durationSec: durationSec, buffer: inhaleBuffer)
    }

    func playExhale(durationSec: Double) {
        ensureStarted()
        scheduleCounts(durationSec: durationSec, buffer: exhaleBuffer)
    }

    private func scheduleCounts(durationSec: Double, buffer: AVAudioPCMBuffer) {
        let count = max(1, Int(durationSec.rounded()))
        guard let lastRender = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: lastRender) else {
            // First schedule before engine has rendered — fall back to "now".
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            for _ in 1..<count {
                player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            }
            return
        }
        let sr = playerTime.sampleRate
        let nowSample = playerTime.sampleTime
        for i in 0..<count {
            let at = AVAudioTime(sampleTime: nowSample + AVAudioFramePosition(Double(i) * sr), atRate: sr)
            player.scheduleBuffer(buffer, at: at, options: [], completionHandler: nil)
        }
    }

    func fadeOut(fadeSec: Double) {
        // Simple approach: clear anything queued. Any currently-ringing chime
        // is short (0.6s) and tapers naturally via its exp decay.
        player.stop()
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
        started = false
    }
}
