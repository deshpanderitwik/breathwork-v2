import Foundation
import JavaScriptCore

/// BreathRuntime — the typed Swift bridge to the shared TypeScript state
/// machine. Loads `core.iife.js` into a `JSContext` and exposes a Swift-friendly
/// API over it.
///
/// Phase 0 establishes the shape. Phase 1 implements against it.
///
/// The core guarantee: the state machine in `packages/core` IS the state
/// machine that runs on macOS and iOS. No port, no mirror, no drift.

public struct SessionConfig: Codable, Sendable, Equatable {
    public let inhaleSec: Double
    public let exhaleSec: Double
    public let activeSec: Double
    public let restSec: Double
    public let rounds: Int

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
}

public enum BreathRuntimeError: Error {
    case missingBundle
    case evaluationFailed(String)
    case unexpectedResponse
}

/// Loads and owns a `JSContext` running the shared core. One per session.
public final class BreathRuntime {
    private let context: JSContext

    public init() throws {
        guard let context = JSContext() else {
            throw BreathRuntimeError.evaluationFailed("JSContext init failed")
        }
        self.context = context

        // TODO(phase-1):
        //  1. Load core.iife.js from Bundle.module (Resources/core.iife.js).
        //  2. context.evaluateScript(script)
        //  3. Wire up an exception handler that surfaces JS errors as Swift errors.
        //  4. Expose `Breathe.createSession(config)` returning a handle we can
        //     drive via start / tick / stop from Swift.
    }

    /// Build a session from the given config. Phase 1 implements.
    public func createSession(config: SessionConfig) throws -> SessionHandle {
        _ = config
        throw BreathRuntimeError.evaluationFailed("not implemented: phase 1")
    }
}

/// A thin Swift wrapper around the JS-side `Session` object.
public struct SessionHandle: Sendable {
    public let totalDurationSec: Double

    // TODO(phase-1): hold a reference to the underlying JSValue and
    // implement start / tick / stop as Swift methods that marshal events.
    public func start(nowMs: Double) -> [SessionEvent] { _ = nowMs; return [] }
    public func tick(nowMs: Double) -> [SessionEvent] { _ = nowMs; return [] }
    public func stop() {}
}
