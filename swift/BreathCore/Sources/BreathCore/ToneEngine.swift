import AVFoundation

/// Chime generation lifted from breathwork-v1/Sources/BreathEngine.swift.
/// Fundamental + 2nd partial (×0.3) + 3rd partial (×0.1), 8ms linear attack,
/// exp(-5.5·t) decay, overall scale ×0.25.
///
/// On iOS, we configure AVAudioSession for `.playback` so chimes continue
/// with the screen locked (requires `UIBackgroundModes: audio` in Info.plist).
public final class ToneEngine {
    private let sampleRate: Double = 44100
    private let chimeDuration: Double = 0.6
    private let inhaleFreq: Float = 392.0   // G4
    private let exhaleFreq: Float = 587.33  // D5 (a fifth up)

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inhaleBuffer: AVAudioPCMBuffer!
    private var exhaleBuffer: AVAudioPCMBuffer!
    private var started = false

    public init() {
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
        #if os(iOS)
        // Keep playing when the screen locks. Requires background audio
        // entitlement — see apps/ios Info.plist.
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

    public func playInhale(durationSec: Double) {
        ensureStarted()
        scheduleCounts(durationSec: durationSec, buffer: inhaleBuffer)
    }

    public func playExhale(durationSec: Double) {
        ensureStarted()
        scheduleCounts(durationSec: durationSec, buffer: exhaleBuffer)
    }

    private func scheduleCounts(durationSec: Double, buffer: AVAudioPCMBuffer) {
        let count = max(1, Int(durationSec.rounded()))
        guard let lastRender = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: lastRender) else {
            for _ in 0..<count {
                player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            }
            return
        }
        let sr = playerTime.sampleRate
        let nowSample = playerTime.sampleTime
        for i in 0..<count {
            let at = AVAudioTime(
                sampleTime: nowSample + AVAudioFramePosition(Double(i) * sr),
                atRate: sr
            )
            player.scheduleBuffer(buffer, at: at, options: [], completionHandler: nil)
        }
    }

    public func fadeOut(fadeSec: Double) {
        // Short chimes taper naturally via their exp decay — just flush the queue.
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
