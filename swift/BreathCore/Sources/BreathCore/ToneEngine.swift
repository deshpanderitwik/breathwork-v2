import AVFoundation
import BreathRuntime

/// Handle for a chime that has been scheduled against the audio engine's
/// clock but may not have sounded yet. Lets the host cancel queued chimes
/// when the user pauses between scheduling and audible firing.
///
/// AVAudioPlayerNode does not support per-buffer cancellation, so cancel()
/// here records the fact that the chime should not play. The actual queue
/// flush happens at the pause boundary via `flushScheduledChimes()`, which
/// stops and restarts the player to drop everything still in its queue.
public final class ScheduledChimeHandle {
    fileprivate weak var owner: ToneEngine?
    fileprivate var cancelled = false
    fileprivate var played = false

    fileprivate init(owner: ToneEngine) { self.owner = owner }

    public func cancel() {
        guard !played, !cancelled else { return }
        cancelled = true
        owner?.markCancelled(self)
    }
}

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
    /// Headroom added to every anchor capture so sessionMs=0 events get
    /// scheduled comfortably in the future relative to the audio clock,
    /// not in the millisecond-old past. AVAudioPlayerNode silently drops
    /// scheduled times that are slightly past `now`, so without headroom
    /// the very first chime of every session can play late or not at all.
    /// 50 ms is imperceptible against tap → first chime latency.
    private static let ANCHOR_HEADROOM_SEC: Double = 0.05

    /// Maximum time we'll wait for `player.lastRenderTime` to populate
    /// after `play()`. The render thread normally fills it within one
    /// quantum (~5ms). If it takes longer than this we fall back to
    /// "play ASAP" — better to play slightly late than not at all.
    private static let ANCHOR_RETRY_SEC: Double = 0.05

    private let sampleRate: Double = 44100
    private let design: ToneDesign

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inhaleBuffer: AVAudioPCMBuffer!
    private var exhaleBuffer: AVAudioPCMBuffer!
    private var silentPrimingBuffer: AVAudioPCMBuffer!
    private var started = false

    /// Sample-time corresponding to session t=0. Maps session-relative ms
    /// to AVAudioTime sampleTime via:
    ///   target = sessionAnchorSample + sessionMs * sampleRate / 1000
    /// nil before beginSession(), or after a flushScheduledChimes() resets
    /// the player's sample-time. Re-acquired lazily by scheduleAt().
    private var sessionAnchorSample: AVAudioFramePosition?
    /// Outstanding handles for chimes scheduled into the future. Counts down
    /// as chimes complete; checked on cancel() to decide if a flush is needed.
    private var pendingHandles: [ScheduledChimeHandle] = []

    public init(design: ToneDesign) {
        self.design = design
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        inhaleBuffer = makeChime(frequency: Float(design.inhaleFreqHz))
        exhaleBuffer = makeChime(frequency: Float(design.exhaleFreqHz))
        silentPrimingBuffer = makeSilentBuffer(frames: 64)
    }

    /// Tiny silent buffer scheduled in `prepare()` to force the render
    /// thread to advance lastRenderTime before the host calls beginSession().
    /// Without this, the first session of an app launch can race the render
    /// thread and capture a nil anchor (falling back to "play ASAP").
    private func makeSilentBuffer(frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { data[i] = 0 }
        return buffer
    }

    /// Pre-render one chime. The last 2 ms taper linearly to zero so the
    /// buffer ends at silence — otherwise the natural exp decay leaves the
    /// final sample at ~4% and the iPhone speaker pops on the step to 0.
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
        let releaseSamples = max(1, Int(0.002 * sampleRate))
        let releaseStart = Int(frameCount) - releaseSamples

        for i in 0..<Int(frameCount) {
            let t = Float(i) / sr
            let envelope: Float = t < attackTime
                ? (t / attackTime)
                : exp(-(t - attackTime) * lambda)
            let release: Float = i < releaseStart
                ? 1.0
                : Float(Int(frameCount) - i) / Float(releaseSamples)
            let fundamental = sin(2.0 * .pi * frequency * t)
            let partial2 = sin(2.0 * .pi * frequency * 2.0 * t) * p2
            let partial3 = sin(2.0 * .pi * frequency * 3.0 * t) * p3
            data[i] = (fundamental + partial2 + partial3) * envelope * release * scale
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

    /// Warm the audio pipeline so the first chime fires sample-accurately.
    ///
    /// On iOS, AVAudioSession activation + engine.start + player.play takes
    /// 100–300 ms cold. Prepare moves that latency to the pre-roll. We also
    /// schedule a tiny silent priming buffer here so `lastRenderTime` is
    /// reliably populated by the time beginSession() reads it — without
    /// the priming buffer, the render thread can race and we'd anchor nil
    /// on the first session of an app launch.
    public func prepare() {
        ensureStarted()
        if started {
            player.scheduleBuffer(
                silentPrimingBuffer, at: nil, options: [], completionHandler: nil
            )
        }
    }

    /// Anchor the audio clock to session t=0. Called by the host once at
    /// session start, before any scheduleChimeAt calls.
    ///
    /// Briefly retries reading `lastRenderTime` if it's not yet populated
    /// (sub-millisecond on a primed engine). Adds a small headroom offset
    /// so sessionMs=0 events schedule comfortably in the future of the
    /// audio clock, not in the past.
    public func beginSession() {
        reanchor(currentSessionMs: 0)
    }

    /// Re-acquire the anchor. Sets sessionAnchorSample such that the
    /// player's CURRENT sample-time corresponds to `currentSessionMs`.
    ///
    /// Use after a flush (player.stop() resets sample-time to 0) and after
    /// recovering from an audio interruption / engine reconfig. The host
    /// passes the current effective time so the anchor stays consistent
    /// across the session even though the underlying sample counter resets.
    public func reanchor(currentSessionMs: Double) {
        ensureStarted()
        guard started else { sessionAnchorSample = nil; return }
        guard let nowSample = readPlayerSampleTimeWithRetry() else {
            sessionAnchorSample = nil
            return
        }
        let headroom = AVAudioFramePosition(Self.ANCHOR_HEADROOM_SEC * sampleRate)
        let nowOffset = AVAudioFramePosition(currentSessionMs * sampleRate / 1000.0)
        sessionAnchorSample = nowSample + headroom - nowOffset
    }

    /// Schedule one inhale chime to sound at exactly `sessionMs` past the
    /// anchor. The audio engine's hardware clock decides when the buffer
    /// plays — polling-tick jitter on the caller no longer affects the
    /// audible moment. If the anchor is invalid (post-flush, before
    /// reanchor), this method attempts a sync re-acquire before scheduling.
    public func scheduleInhaleChimeAt(sessionMs: Double) -> ScheduledChimeHandle {
        scheduleAt(buffer: inhaleBuffer, sessionMs: sessionMs)
    }

    /// As above, for exhale.
    public func scheduleExhaleChimeAt(sessionMs: Double) -> ScheduledChimeHandle {
        scheduleAt(buffer: exhaleBuffer, sessionMs: sessionMs)
    }

    private func scheduleAt(
        buffer: AVAudioPCMBuffer, sessionMs: Double
    ) -> ScheduledChimeHandle {
        ensureStarted()
        // Lazy re-anchor: if the anchor was invalidated (e.g. by a flush
        // earlier on this tick) and the host hasn't re-anchored explicitly,
        // recover here using sessionMs as the current effective time. This
        // is exactly correct only for the first event in a batch; subsequent
        // events in the same batch reuse the same anchor and are scheduled
        // relative to it via the (sessionMs - firstSessionMs) delta — which
        // is what the formula already produces, so this works for batches.
        if sessionAnchorSample == nil {
            reanchor(currentSessionMs: sessionMs)
        }
        let handle = ScheduledChimeHandle(owner: self)
        let when: AVAudioTime?
        if let anchor = sessionAnchorSample {
            let target = anchor + AVAudioFramePosition(sessionMs * sampleRate / 1000.0)
            when = AVAudioTime(sampleTime: target, atRate: sampleRate)
        } else {
            // Anchor still unavailable — fall back to ASAP. Slightly late is
            // better than silent.
            when = nil
        }
        player.scheduleBuffer(buffer, at: when, options: []) { [weak self, weak handle] in
            // Completion runs on an arbitrary queue. Mark the handle as played
            // and trim the pending list. Cancellation flushing is a separate
            // path that runs synchronously from cancel().
            DispatchQueue.main.async {
                handle?.played = true
                self?.trimPendingHandles()
            }
        }
        pendingHandles.append(handle)
        return handle
    }

    /// Called by ScheduledChimeHandle.cancel(). AVAudioPlayerNode has no
    /// per-buffer cancel API — to drop a queued chime we must flush the
    /// player's entire queue. So: any cancel triggers a full flush of
    /// outstanding pending chimes. This is the correct behavior for the
    /// pause path (the host cancels every pending chime in one batch);
    /// cancel() called sparsely outside a pause would also flush, which is
    /// acceptable because the host re-schedules from the audio cursor on
    /// the next tickAudio call.
    fileprivate func markCancelled(_ handle: ScheduledChimeHandle) {
        flushScheduledChimes()
    }

    /// Drop every queued chime that has not yet sounded. Called on pause
    /// (via cancel()) and on stop(). Currently-ringing buffers are cut off
    /// — the existing 50ms fadeOut applied at pause masks any click.
    ///
    /// player.stop() resets the player's sample-time counter to 0, so the
    /// anchor we captured at session start is no longer valid. We invalidate
    /// it here; the next scheduleAt call will lazily re-anchor (or the host
    /// can call reanchor explicitly).
    public func flushScheduledChimes() {
        guard started else { return }
        player.stop()
        player.play()
        sessionAnchorSample = nil
        for handle in pendingHandles where !handle.played {
            handle.cancelled = true
        }
        pendingHandles.removeAll()
    }

    /// Read the player's current sample-time. Retries briefly if not yet
    /// populated — covers the case where reanchor() is called immediately
    /// after engine start, before the render thread has had time to fill
    /// in lastRenderTime. Falls back to the engine's output node which
    /// renders continuously once started.
    private func readPlayerSampleTimeWithRetry() -> AVAudioFramePosition? {
        let deadline = Date().addingTimeInterval(Self.ANCHOR_RETRY_SEC)
        repeat {
            if let sample = readPlayerSampleTime() { return sample }
            // Yield briefly so the audio render thread can advance.
            Thread.sleep(forTimeInterval: 0.001)
        } while Date() < deadline
        return readPlayerSampleTime()
    }

    private func readPlayerSampleTime() -> AVAudioFramePosition? {
        if let lastRender = player.lastRenderTime, lastRender.isSampleTimeValid {
            if let playerTime = player.playerTime(forNodeTime: lastRender) {
                return playerTime.sampleTime
            }
            return lastRender.sampleTime
        }
        if let engineRender = engine.outputNode.lastRenderTime,
           engineRender.isSampleTimeValid {
            return engineRender.sampleTime
        }
        return nil
    }

    private func trimPendingHandles() {
        pendingHandles.removeAll { $0.played || $0.cancelled }
    }

    /// Play one inhale chime starting now. Legacy single-shot path —
    /// retained so the legacy ToneSet protocol stays satisfied; new code
    /// should call scheduleInhaleChimeAt for sample-accurate timing.
    public func playInhaleChime() {
        ensureStarted()
        player.scheduleBuffer(inhaleBuffer, at: nil, options: [], completionHandler: nil)
    }

    /// Play one exhale chime starting now. Single-shot. Legacy.
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
        // player.stop() resets sample-time → anchor is now stale.
        sessionAnchorSample = nil
        // Anything we'd queued ahead via scheduleChimeAt is now gone — mark
        // pending handles cancelled so cancel() on them is a no-op.
        for handle in pendingHandles where !handle.played {
            handle.cancelled = true
        }
        pendingHandles.removeAll()
    }

    public func stop() {
        sessionAnchorSample = nil
        for handle in pendingHandles where !handle.played {
            handle.cancelled = true
        }
        pendingHandles.removeAll()
        player.stop()
        engine.stop()
        started = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}
