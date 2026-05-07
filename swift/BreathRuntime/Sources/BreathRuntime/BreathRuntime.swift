import Foundation
import JavaScriptCore

/// BreathRuntime — typed Swift bridge to the shared TypeScript state machine.
/// Loads `core.iife.js` (built from `packages/core` and synced into Resources
/// by `scripts/sync-core.sh`) into a `JSContext` and exposes a Swift API over
/// the global `Breathe` namespace the IIFE installs.
///
/// Threading: `JSContext` is not thread-safe. Use one runtime instance from a
/// single thread. Callers in this project drive it from the main thread.

public struct SessionConfig: Codable, Sendable, Equatable {
    public var inhaleSec: Double
    public var exhaleSec: Double
    public var activeSec: Double
    public var restSec: Double
    public var rounds: Int

    public init(
        inhaleSec: Double,
        exhaleSec: Double,
        activeSec: Double,
        restSec: Double,
        rounds: Int
    ) {
        self.inhaleSec = inhaleSec
        self.exhaleSec = exhaleSec
        self.activeSec = activeSec
        self.restSec = restSec
        self.rounds = rounds
    }
}

public enum SessionEvent: Sendable, Equatable {
    /// Fires once per count-second of an inhale. `beatIndex == 0` means
    /// "phase just started" (UI uses this to swap the label).
    /// One event = one chime.
    case inhaleCount(round: Int, beatIndex: Int, beatsInPhase: Int, atMs: Double)
    /// As above, for exhale.
    case exhaleCount(round: Int, beatIndex: Int, beatsInPhase: Int, atMs: Double)
    case restStart(round: Int, durationSec: Double, fadeOutSec: Double, atMs: Double)
    case roundComplete(round: Int, atMs: Double)
    case sessionComplete(atMs: Double)

    fileprivate init?(jsValue: JSValue) {
        guard jsValue.isObject,
              let kind = jsValue.forProperty("kind")?.toString() else { return nil }
        switch kind {
        case "inhale-count":
            guard let round = jsValue.forProperty("round")?.toInt32(),
                  let beat = jsValue.forProperty("beatIndex")?.toInt32(),
                  let total = jsValue.forProperty("beatsInPhase")?.toInt32(),
                  let at = jsValue.forProperty("atMs")?.toDouble() else { return nil }
            self = .inhaleCount(round: Int(round), beatIndex: Int(beat),
                                beatsInPhase: Int(total), atMs: at)
        case "exhale-count":
            guard let round = jsValue.forProperty("round")?.toInt32(),
                  let beat = jsValue.forProperty("beatIndex")?.toInt32(),
                  let total = jsValue.forProperty("beatsInPhase")?.toInt32(),
                  let at = jsValue.forProperty("atMs")?.toDouble() else { return nil }
            self = .exhaleCount(round: Int(round), beatIndex: Int(beat),
                                beatsInPhase: Int(total), atMs: at)
        case "rest-start":
            guard let round = jsValue.forProperty("round")?.toInt32(),
                  let dur = jsValue.forProperty("durationSec")?.toDouble(),
                  let fade = jsValue.forProperty("fadeOutSec")?.toDouble(),
                  let at = jsValue.forProperty("atMs")?.toDouble() else { return nil }
            self = .restStart(round: Int(round), durationSec: dur, fadeOutSec: fade, atMs: at)
        case "round-complete":
            guard let round = jsValue.forProperty("round")?.toInt32(),
                  let at = jsValue.forProperty("atMs")?.toDouble() else { return nil }
            self = .roundComplete(round: Int(round), atMs: at)
        case "session-complete":
            guard let at = jsValue.forProperty("atMs")?.toDouble() else { return nil }
            self = .sessionComplete(atMs: at)
        default:
            return nil
        }
    }

    public var atMs: Double {
        switch self {
        case .inhaleCount(_, _, _, let t),
             .exhaleCount(_, _, _, let t),
             .restStart(_, _, _, let t),
             .roundComplete(_, let t),
             .sessionComplete(let t):
            return t
        }
    }
}

/// Mirror of `TONE_DESIGN` in `packages/core/src/tone-design.ts`. Read from
/// the JS core via `BreathRuntime.toneDesign()` so platform audio engines
/// synthesize from the same parameters.
public struct ToneDesign: Sendable, Equatable {
    public let inhaleFreqHz: Double
    public let exhaleFreqHz: Double
    public let chimeDurationSec: Double
    public let attackSec: Double
    public let decayLambda: Double
    public let partial2Weight: Double
    public let partial3Weight: Double
    public let masterScale: Double
    public let chimesPerSec: Double

    public init(
        inhaleFreqHz: Double, exhaleFreqHz: Double, chimeDurationSec: Double,
        attackSec: Double, decayLambda: Double, partial2Weight: Double,
        partial3Weight: Double, masterScale: Double, chimesPerSec: Double
    ) {
        self.inhaleFreqHz = inhaleFreqHz
        self.exhaleFreqHz = exhaleFreqHz
        self.chimeDurationSec = chimeDurationSec
        self.attackSec = attackSec
        self.decayLambda = decayLambda
        self.partial2Weight = partial2Weight
        self.partial3Weight = partial3Weight
        self.masterScale = masterScale
        self.chimesPerSec = chimesPerSec
    }
}

public enum BreathRuntimeError: Error, Equatable {
    case missingBundle
    case evaluationFailed(String)
    case unexpectedResponse
}

public final class BreathRuntime {
    private let context: JSContext
    private var lastException: String?

    public init() throws {
        guard let context = JSContext() else {
            throw BreathRuntimeError.evaluationFailed("JSContext init failed")
        }
        self.context = context

        context.exceptionHandler = { [weak self] _, exception in
            self?.lastException = exception?.toString() ?? "unknown JS exception"
        }

        guard let url = Bundle.module.url(forResource: "core.iife", withExtension: "js") else {
            throw BreathRuntimeError.missingBundle
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw BreathRuntimeError.missingBundle
        }

        context.evaluateScript(source)
        if let msg = takeException() {
            throw BreathRuntimeError.evaluationFailed(msg)
        }

        // Sanity-check the global the IIFE installs. If this fails, the bundle
        // we synced is the wrong shape — almost always a build-pipeline bug.
        guard let breathe = context.objectForKeyedSubscript("Breathe"),
              !breathe.isUndefined,
              let createFn = breathe.objectForKeyedSubscript("createSession"),
              !createFn.isUndefined else {
            throw BreathRuntimeError.evaluationFailed(
                "Breathe.createSession not found after loading core.iife.js"
            )
        }
    }

    /// Read a built-in preset from the JS core. Mirrors `PRESETS` in
    /// `packages/core/src/presets.ts`. Valid ids today: "calm", "focus", "deep".
    public func preset(_ id: String) throws -> SessionConfig {
        guard let breathe = context.objectForKeyedSubscript("Breathe"),
              let presets = breathe.objectForKeyedSubscript("PRESETS"),
              presets.isObject else {
            throw BreathRuntimeError.unexpectedResponse
        }
        guard let entry = presets.objectForKeyedSubscript(id),
              entry.isObject else {
            if let msg = takeException() {
                throw BreathRuntimeError.evaluationFailed(msg)
            }
            throw BreathRuntimeError.evaluationFailed("preset '\(id)' not found")
        }
        guard let inhale = entry.objectForKeyedSubscript("inhaleSec")?.toDouble(),
              let exhale = entry.objectForKeyedSubscript("exhaleSec")?.toDouble(),
              let active = entry.objectForKeyedSubscript("activeSec")?.toDouble(),
              let rest = entry.objectForKeyedSubscript("restSec")?.toDouble(),
              let rounds = entry.objectForKeyedSubscript("rounds")?.toInt32() else {
            throw BreathRuntimeError.unexpectedResponse
        }
        return SessionConfig(
            inhaleSec: inhale, exhaleSec: exhale, activeSec: active,
            restSec: rest, rounds: Int(rounds)
        )
    }

    /// Read `TONE_DESIGN` from the JS core. Cached via `toneDesign` lazy var
    /// for typical use; this method exists for symmetry with `preset(_:)`
    /// and for tests that want to verify the round trip.
    public func readToneDesign() throws -> ToneDesign {
        guard let breathe = context.objectForKeyedSubscript("Breathe"),
              let design = breathe.objectForKeyedSubscript("TONE_DESIGN"),
              design.isObject else {
            if let msg = takeException() {
                throw BreathRuntimeError.evaluationFailed(msg)
            }
            throw BreathRuntimeError.unexpectedResponse
        }
        guard
            let inhale = design.objectForKeyedSubscript("inhaleFreqHz")?.toDouble(),
            let exhale = design.objectForKeyedSubscript("exhaleFreqHz")?.toDouble(),
            let dur = design.objectForKeyedSubscript("chimeDurationSec")?.toDouble(),
            let attack = design.objectForKeyedSubscript("attackSec")?.toDouble(),
            let lambda = design.objectForKeyedSubscript("decayLambda")?.toDouble(),
            let p2 = design.objectForKeyedSubscript("partial2Weight")?.toDouble(),
            let p3 = design.objectForKeyedSubscript("partial3Weight")?.toDouble(),
            let scale = design.objectForKeyedSubscript("masterScale")?.toDouble(),
            let cps = design.objectForKeyedSubscript("chimesPerSec")?.toDouble()
        else {
            throw BreathRuntimeError.unexpectedResponse
        }
        return ToneDesign(
            inhaleFreqHz: inhale, exhaleFreqHz: exhale, chimeDurationSec: dur,
            attackSec: attack, decayLambda: lambda,
            partial2Weight: p2, partial3Weight: p3,
            masterScale: scale, chimesPerSec: cps
        )
    }

    /// Cached canonical tone design. Computed once; cheap to reference.
    public lazy var toneDesign: ToneDesign = {
        do {
            return try readToneDesign()
        } catch {
            fatalError("BreathRuntime.toneDesign: failed to read TONE_DESIGN: \(error)")
        }
    }()

    /// The canonical default config — `PRESETS.calm`, read once from the JS
    /// core. Used by app init when no saved settings exist. Cached after
    /// first read; cheap to reference repeatedly.
    public lazy var defaultConfig: SessionConfig = {
        do {
            return try preset("calm")
        } catch {
            fatalError("BreathRuntime.defaultConfig: failed to read 'calm' preset: \(error)")
        }
    }()

    public func createSession(config: SessionConfig) throws -> SessionHandle {
        let configDict: [String: Any] = [
            "inhaleSec": config.inhaleSec,
            "exhaleSec": config.exhaleSec,
            "activeSec": config.activeSec,
            "restSec": config.restSec,
            "rounds": config.rounds,
        ]

        guard let breathe = context.objectForKeyedSubscript("Breathe") else {
            throw BreathRuntimeError.evaluationFailed("Breathe global missing")
        }
        let result = breathe.invokeMethod("createSession", withArguments: [configDict])
        if let msg = takeException() {
            throw BreathRuntimeError.evaluationFailed(msg)
        }
        guard let session = result, session.isObject else {
            throw BreathRuntimeError.unexpectedResponse
        }
        let total = session.objectForKeyedSubscript("totalDurationSec")?.toDouble() ?? 0
        return SessionHandle(jsSession: session, totalDurationSec: total, runtime: self)
    }

    /// Returns and clears the most recent JS exception, if any. Called after
    /// every JS invocation so errors don't pile up across calls.
    fileprivate func takeException() -> String? {
        defer { lastException = nil }
        return lastException
    }
}

public final class SessionHandle {
    private let jsSession: JSValue
    private let runtime: BreathRuntime
    public let totalDurationSec: Double

    fileprivate init(jsSession: JSValue, totalDurationSec: Double, runtime: BreathRuntime) {
        self.jsSession = jsSession
        self.totalDurationSec = totalDurationSec
        self.runtime = runtime
    }

    public func start(nowMs: Double) -> [SessionEvent] {
        invoke("start", arg: nowMs)
    }

    public func tick(nowMs: Double) -> [SessionEvent] {
        invoke("tick", arg: nowMs)
    }

    /// Pull events whose atMs falls within (effective(now), effective(now)
    /// + lookaheadMs]. Lets the host pre-schedule audio against the audio
    /// engine's own clock so polling-tick jitter does not affect the
    /// audible moment. Maintains a cursor independent of `tick`.
    public func tickAudio(nowMs: Double, lookaheadMs: Double) -> [SessionEvent] {
        guard let result = jsSession.invokeMethod(
            "tickAudio", withArguments: [nowMs, lookaheadMs]
        ) else {
            _ = runtime.takeException()
            return []
        }
        _ = runtime.takeException()
        guard result.isArray else { return [] }
        let count = Int(result.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        var events: [SessionEvent] = []
        events.reserveCapacity(count)
        for i in 0..<count {
            if let item = result.atIndex(i), let event = SessionEvent(jsValue: item) {
                events.append(event)
            }
        }
        return events
    }

    /// Roll the audio cursor back to the fired (tick) cursor. After this
    /// call, `tickAudio` will re-emit any events that were dispatched to
    /// audio earlier but have not yet fired through `tick`. Used on pause
    /// so resume re-schedules the chimes that were just cancelled.
    public func rewindAudioCursor() {
        _ = jsSession.invokeMethod("rewindAudioCursor", withArguments: [])
        _ = runtime.takeException()
    }

    public func pause(nowMs: Double) {
        _ = jsSession.invokeMethod("pause", withArguments: [nowMs])
        _ = runtime.takeException()
    }

    public func resume(nowMs: Double) {
        _ = jsSession.invokeMethod("resume", withArguments: [nowMs])
        _ = runtime.takeException()
    }

    public var isPaused: Bool {
        jsSession.objectForKeyedSubscript("isPaused")?.toBool() ?? false
    }

    /// Effective elapsed time in ms — wall clock with paused intervals
    /// subtracted. Use for UI display; frozen while paused.
    public func effectiveMs(nowMs: Double) -> Double {
        let result = jsSession.invokeMethod("effectiveMs", withArguments: [nowMs])
        _ = runtime.takeException()
        return result?.toDouble() ?? 0
    }

    public func stop() {
        _ = jsSession.invokeMethod("stop", withArguments: [])
        _ = runtime.takeException()
    }

    private func invoke(_ method: String, arg: Double) -> [SessionEvent] {
        guard let result = jsSession.invokeMethod(method, withArguments: [arg]) else {
            _ = runtime.takeException()
            return []
        }
        _ = runtime.takeException()
        guard result.isArray else { return [] }
        let count = Int(result.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        var events: [SessionEvent] = []
        events.reserveCapacity(count)
        for i in 0..<count {
            if let item = result.atIndex(i), let event = SessionEvent(jsValue: item) {
                events.append(event)
            }
        }
        return events
    }
}
