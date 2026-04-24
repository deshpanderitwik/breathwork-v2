import Foundation

/// Wires a BreathSession + ToneEngine + AppState together. Starts the
/// session, drives ticks on a timer, translates events into tone calls
/// and UI state mutations, and cleans up on stop.
///
/// Both macOS (menu bar) and iOS (screen) use this — they differ only in
/// how they present the state.
public final class SessionController {
    private let state: AppState
    private let tones: ToneEngine
    private var session: BreathSession?
    private var tickTimer: Timer?

    /// Real wall-clock time when the current session (re)started. We derive
    /// elapsed by subtracting this from Date() and adding `accumulatedMs`
    /// (which holds the frozen elapsed from prior paused runs).
    private var segmentStart = Date()
    private var accumulatedMs: Double = 0

    public init(state: AppState, tones: ToneEngine) {
        self.state = state
        self.tones = tones
    }

    public var isRunning: Bool { state.isRunning }

    public func toggle() {
        if state.isRunning {
            if state.isPaused { resume() } else { pause() }
        } else {
            start()
        }
    }

    public func start() {
        do {
            session = try BreathSession(config: state.config)
        } catch {
            return
        }

        state.isRunning = true
        state.isPaused = false
        state.elapsedMs = 0
        state.currentPhase = ""
        state.currentRound = 1
        accumulatedMs = 0
        segmentStart = Date()

        let initial = session?.start(nowMs: 0) ?? []
        handle(events: initial)
        startTicker()
    }

    public func pause() {
        guard state.isRunning, !state.isPaused else { return }
        accumulatedMs += Date().timeIntervalSince(segmentStart) * 1000
        state.elapsedMs = accumulatedMs
        tickTimer?.invalidate()
        tickTimer = nil
        // Clear any already-scheduled chimes so the next count doesn't leak
        // through during the pause.
        tones.fadeOut(fadeSec: 0.05)
        state.isPaused = true
    }

    public func resume() {
        guard state.isRunning, state.isPaused else { return }
        segmentStart = Date()
        state.isPaused = false
        startTicker()
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
        accumulatedMs = 0
    }

    private func startTicker() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let session = session, !state.isPaused else { return }
        let elapsedMs = accumulatedMs + Date().timeIntervalSince(segmentStart) * 1000
        state.elapsedMs = elapsedMs
        let events = session.tick(nowMs: elapsedMs)
        if !events.isEmpty { handle(events: events) }
    }

    private func handle(events: [SessionEvent]) {
        for ev in events {
            switch ev {
            case .inhaleStart(let round, let durationSec, _):
                state.currentRound = round
                state.currentPhase = "Inhale"
                tones.playInhale(durationSec: durationSec)
            case .exhaleStart(let round, let durationSec, _):
                state.currentRound = round
                state.currentPhase = "Exhale"
                tones.playExhale(durationSec: durationSec)
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
