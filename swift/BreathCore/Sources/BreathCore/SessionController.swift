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
public final class SessionController {
    private let state: AppState
    private let tones: ToneEngine
    private let runtime: BreathRuntime
    private var session: SessionHandle?
    private var tickTimer: Timer?

    /// Wall-clock anchor for the current session — set on start, used to
    /// compute the monotonic `nowMs` argument for every JS call below.
    private var sessionStart = Date()

    public init(state: AppState, tones: ToneEngine, runtime: BreathRuntime) {
        self.state = state
        self.tones = tones
        self.runtime = runtime
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

        sessionStart = Date()

        let initial = session?.start(nowMs: 0) ?? []
        handle(events: initial)
        startTicker()
    }

    public func pause() {
        guard state.isRunning, !state.isPaused else { return }
        let now = Date().timeIntervalSince(sessionStart) * 1000
        session?.pause(nowMs: now)
        state.isPaused = true
        // Silence any chimes already scheduled past the freeze point.
        tones.fadeOut(fadeSec: 0.05)
    }

    public func resume() {
        guard state.isRunning, state.isPaused else { return }
        let now = Date().timeIntervalSince(sessionStart) * 1000
        session?.resume(nowMs: now)
        state.isPaused = false
    }

    public func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
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
        let events = session.tick(nowMs: now)
        if !events.isEmpty { handle(events: events) }
    }

    private func handle(events: [SessionEvent]) {
        for ev in events {
            switch ev {
            case .inhaleCount(let round, let beatIndex, _, _):
                state.currentRound = round
                if beatIndex == 0 { state.currentPhase = "Inhale" }
                tones.playInhaleChime()
            case .exhaleCount(let round, let beatIndex, _, _):
                state.currentRound = round
                if beatIndex == 0 { state.currentPhase = "Exhale" }
                tones.playExhaleChime()
            case .restStart(let round, _, let fadeOutSec, _):
                state.currentRound = round
                state.currentPhase = "Rest"
                tones.fadeOut(fadeSec: fadeOutSec)
            case .roundComplete:
                break
            case .sessionComplete:
                stop()
            }
        }
    }
}
