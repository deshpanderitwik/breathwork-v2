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
    case inhaleStart(round: Int, durationSec: Double, atMs: Double)
    case exhaleStart(round: Int, durationSec: Double, atMs: Double)
    case restStart(round: Int, durationSec: Double, fadeOutSec: Double, atMs: Double)
    case roundComplete(round: Int, atMs: Double)
    case sessionComplete(atMs: Double)

    fileprivate init?(jsValue: JSValue) {
        guard jsValue.isObject,
              let kind = jsValue.forProperty("kind")?.toString() else { return nil }
        switch kind {
        case "inhale-start":
            guard let round = jsValue.forProperty("round")?.toInt32(),
                  let dur = jsValue.forProperty("durationSec")?.toDouble(),
                  let at = jsValue.forProperty("atMs")?.toDouble() else { return nil }
            self = .inhaleStart(round: Int(round), durationSec: dur, atMs: at)
        case "exhale-start":
            guard let round = jsValue.forProperty("round")?.toInt32(),
                  let dur = jsValue.forProperty("durationSec")?.toDouble(),
                  let at = jsValue.forProperty("atMs")?.toDouble() else { return nil }
            self = .exhaleStart(round: Int(round), durationSec: dur, atMs: at)
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
        case .inhaleStart(_, _, let t),
             .exhaleStart(_, _, let t),
             .restStart(_, _, _, let t),
             .roundComplete(_, let t),
             .sessionComplete(let t):
            return t
        }
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
