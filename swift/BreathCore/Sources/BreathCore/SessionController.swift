import AVFoundation
import Foundation
import BreathRuntime

/// Wires the JS-backed BreathRuntime + ToneEngine + AppState together.
/// Starts the session, drives ticks on a timer, translates events into tone
/// calls and UI state mutations, and cleans up on stop.
///
/// Pause arithmetic lives in the JS engine. The controller only tracks a
/// single `sessionStart` Date used to compute strictly-monotonic `nowMs`
/// values to hand to `session.tick / pause / resume`. UI elapsed time comes
/// from `session.effectiveMs(nowMs:)`, which freezes during pause.
///
/// Audio dispatch goes through a separate path: each tick calls
/// `session.tickAudio(now, AUDIO_LOOKAHEAD_MS)` to pull events landing
/// within the lookahead window and pre-schedules them against the audio
/// engine's own clock. The Timer's ~100ms cadence (and its drift) no
/// longer affects the audible moment — only the audio hardware clock does.
public final class SessionController {
    /// How far ahead of effective time we pre-schedule chimes against the
    /// audio engine's clock. Must comfortably exceed the Timer's 100ms
    /// cadence so chimes are always queued in the future relative to the
    /// audio clock, even if the Timer fires late.
    private static let AUDIO_LOOKAHEAD_MS: Double = 250

    private let state: AppState
    private let tones: ToneEngine
    private let runtime: BreathRuntime
    private var session: SessionHandle?
    private var tickTimer: Timer?

    /// Outstanding chime handles for chimes scheduled into the future.
    /// Held so pause() can cancel anything queued past the freeze point.
    private var pendingChimes: [ScheduledChimeHandle] = []

    /// Wall-clock anchor for the current session — set on start, used to
    /// compute the monotonic `nowMs` argument for every JS call below.
    private var sessionStart = Date()

    /// True if the most recent pause was triggered by an audio interruption
    /// (phone call, Siri, alarm) rather than a user gesture. We auto-resume
    /// from interruption pauses when iOS tells us .shouldResume; user-paused
    /// sessions stay paused until the user taps Resume.
    private var pausedDueToInterruption = false

    public init(state: AppState, tones: ToneEngine, runtime: BreathRuntime) {
        self.state = state
        self.tones = tones
        self.runtime = runtime
        registerAudioNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Subscribe to the AVFoundation events that can disrupt audio mid-
    /// session: interruptions (phone call, Siri), engine config changes
    /// (output device switch). On iOS these all fire through different
    /// notification names; macOS only has the engine-config one.
    private func registerAudioNotifications() {
        let nc = NotificationCenter.default
        #if os(iOS)
        nc.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        #endif
        nc.addObserver(
            self, selector: #selector(handleEngineConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange, object: nil
        )
    }

    public var isRunning: Bool { state.isRunning }

    /// Menu-bar click behavior: a running session stops fully, an idle one
    /// starts. Pause/resume stays available via `pause()` / `resume()` for
    /// surfaces (iOS) that expose dedicated controls.
    public func toggle() {
        if state.isRunning {
            stop()
        } else {
            start()
        }
    }

    public func start() {
        do {
            session = try runtime.createSession(config: state.config)
        } catch {
            return
        }

        state.isRunning = true
        state.isPaused = false
        state.elapsedMs = 0
        state.currentPhase = ""
        state.currentRound = 1

        // Warm the audio engine BEFORE dispatching the first inhale-count
        // event. Otherwise the first chime is delayed by AVAudioSession +
        // engine startup latency (~200 ms on iOS), bunching chimes 1 and 2.
        tones.prepare()
        // Anchor the audio clock to session t=0 so subsequent
        // scheduleChimeAt calls map correctly to AVAudioTime sampleTime.
        tones.beginSession()

        sessionStart = Date()

        let initial = session?.start(nowMs: 0) ?? []
        // Initial events fired at t=0: feed both audio path and UI path.
        // Without scheduleAudio() the first chime never plays — tick()
        // alone only updates the label.
        scheduleAudio(events: initial)
        handleUiEvents(events: initial)
        startTicker()
    }

    public func pause() {
        pausedDueToInterruption = false
        pauseInternal()
    }

    public func resume() {
        pausedDueToInterruption = false
        resumeInternal()
    }

    /// Shared pause path used by both user gesture and audio interruption.
    /// Cancels chimes pre-scheduled past the freeze point and rewinds the
    /// audio cursor so resume re-queues them at their (now shifted) atMs.
    /// The 50ms fadeOut masks the queue-flush click.
    private func pauseInternal() {
        guard state.isRunning, !state.isPaused else { return }
        let now = Date().timeIntervalSince(sessionStart) * 1000
        session?.pause(nowMs: now)
        state.isPaused = true
        flushPendingChimes()
        session?.rewindAudioCursor()
        tones.fadeOut(fadeSec: 0.05)
    }

    /// Shared resume path. Re-anchors the audio clock against the current
    /// effective time — the previous anchor was invalidated by the flush
    /// (player.stop() resets the sample-time counter) and the engine may
    /// have been reset entirely if we're resuming from an interruption.
    private func resumeInternal() {
        guard state.isRunning, state.isPaused else { return }
        let now = Date().timeIntervalSince(sessionStart) * 1000
        let effective = session?.effectiveMs(nowMs: now) ?? 0
        // ensure engine is up (interruption may have stopped it) then anchor
        // against the current effective time so future scheduleChimeAt calls
        // produce sample-times that line up with where the session actually is.
        tones.prepare()
        tones.reanchor(currentSessionMs: effective)
        session?.resume(nowMs: now)
        state.isPaused = false
    }

    public func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        flushPendingChimes()
        session?.stop()
        session = nil
        tones.stop()
        state.isRunning = false
        state.isPaused = false
        state.currentPhase = ""
        state.elapsedMs = 0
    }

    private func startTicker() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let session = session else { return }
        let now = Date().timeIntervalSince(sessionStart) * 1000
        state.elapsedMs = session.effectiveMs(nowMs: now)
        // Audio path: pre-schedule any events landing within the lookahead.
        // Their atMs values become absolute audio-clock targets — sample-
        // accurate regardless of whether THIS Timer tick fired on time.
        let audioEvents = session.tickAudio(
            nowMs: now, lookaheadMs: Self.AUDIO_LOOKAHEAD_MS
        )
        if !audioEvents.isEmpty { scheduleAudio(events: audioEvents) }
        // UI path: only update labels at the actual audible moment.
        let events = session.tick(nowMs: now)
        if !events.isEmpty { handleUiEvents(events: events) }
    }

    /// Pre-schedule audio events against the engine's own clock. Each
    /// chime returns a cancel handle we hold so pause() can flush.
    /// rest-start fadeOut fires immediately because it acts on currently-
    /// ringing voices, not on scheduled future buffers.
    private func scheduleAudio(events: [SessionEvent]) {
        for ev in events {
            switch ev {
            case .inhaleCount(_, _, _, let atMs):
                pendingChimes.append(tones.scheduleInhaleChimeAt(sessionMs: atMs))
            case .exhaleCount(_, _, _, let atMs):
                pendingChimes.append(tones.scheduleExhaleChimeAt(sessionMs: atMs))
            case .restStart(_, _, let fadeOutSec, _):
                tones.fadeOut(fadeSec: fadeOutSec)
            case .roundComplete, .sessionComplete:
                break
            }
        }
        // Trim the array so it doesn't grow unbounded across long sessions.
        // cancel() is a no-op once played, so this is just hygiene.
        if pendingChimes.count > 64 {
            pendingChimes = Array(pendingChimes.suffix(32))
        }
    }

    /// UI updates fire at the actual audible moment (driven by tick(),
    /// which advances the fired cursor). Labels stay locked to sound even
    /// though audio was scheduled ahead of time.
    private func handleUiEvents(events: [SessionEvent]) {
        for ev in events {
            switch ev {
            case .inhaleCount(let round, let beatIndex, _, _):
                state.currentRound = round
                if beatIndex == 0 { state.currentPhase = "Inhale" }
            case .exhaleCount(let round, let beatIndex, _, _):
                state.currentRound = round
                if beatIndex == 0 { state.currentPhase = "Exhale" }
            case .restStart(let round, _, _, _):
                state.currentRound = round
                state.currentPhase = "Rest"
            case .roundComplete:
                break
            case .sessionComplete:
                stop()
            }
        }
    }

    private func flushPendingChimes() {
        let handles = pendingChimes
        pendingChimes.removeAll()
        for h in handles { h.cancel() }
    }

    // MARK: - Audio interruption / reconfig recovery

    #if os(iOS)
    /// AVAudioSession.interruptionNotification handler. Phone calls, Siri,
    /// alarms, and FaceTime all post this. On .began the engine is paused
    /// by iOS; on .ended we may be told to resume.
    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case .began:
                guard self.state.isRunning, !self.state.isPaused else { return }
                self.pausedDueToInterruption = true
                self.pauseInternal()
            case .ended:
                let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                guard options.contains(.shouldResume),
                      self.pausedDueToInterruption,
                      self.state.isRunning, self.state.isPaused else { return }
                self.pausedDueToInterruption = false
                self.resumeInternal()
            @unknown default:
                break
            }
        }
    }
    #endif

    /// AVAudioEngineConfigurationChangeNotification handler. Posted when
    /// iOS reconfigures the audio hardware (output device change, format
    /// change). The engine is stopped and silenced when this fires — we
    /// have to restart it and re-anchor. We do NOT pause the session;
    /// from the user's perspective playback should recover seamlessly
    /// (with at most a tiny gap).
    @objc private func handleEngineConfigChange(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.state.isRunning else { return }
            // Drop anything we'd queued — the engine restart drops them
            // anyway, but this keeps our handle tracking honest.
            self.flushPendingChimes()
            self.session?.rewindAudioCursor()
            // Restart the engine and re-anchor against current effective time.
            self.tones.prepare()
            let now = Date().timeIntervalSince(self.sessionStart) * 1000
            let effective = self.session?.effectiveMs(nowMs: now) ?? 0
            self.tones.reanchor(currentSessionMs: effective)
            // Next tick will re-fill the audio queue from the rewound cursor.
        }
    }
}
