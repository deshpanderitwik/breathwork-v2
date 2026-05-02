import XCTest
@testable import BreathRuntime

/// Step-2 smoke tests: prove the bridge can boot, build a session, and
/// drive it through a full lifecycle. Full parity coverage with the TS
/// contract tests lands in step 5.
final class BreathRuntimeTests: XCTestCase {

    private static let calm = SessionConfig(
        inhaleSec: 4, exhaleSec: 6, activeSec: 90, restSec: 30, rounds: 4
    )

    func testRuntimeBoots() throws {
        _ = try BreathRuntime()
    }

    func testReadsCalmPresetFromJS() throws {
        let runtime = try BreathRuntime()
        let calm = try runtime.preset("calm")
        XCTAssertEqual(calm.inhaleSec, 4)
        XCTAssertEqual(calm.exhaleSec, 6)
        XCTAssertEqual(calm.activeSec, 90)
        XCTAssertEqual(calm.restSec, 30)
        XCTAssertEqual(calm.rounds, 4)
    }

    func testDefaultConfigIsCalm() throws {
        let runtime = try BreathRuntime()
        XCTAssertEqual(runtime.defaultConfig, try runtime.preset("calm"))
    }

    func testReadsToneDesignFromJS() throws {
        let runtime = try BreathRuntime()
        let design = try runtime.readToneDesign()
        XCTAssertEqual(design.inhaleFreqHz, 392.0)
        XCTAssertEqual(design.exhaleFreqHz, 329.63)
        XCTAssertEqual(design.chimeDurationSec, 0.6)
        XCTAssertEqual(design.attackSec, 0.008)
        XCTAssertEqual(design.decayLambda, 5.5)
        XCTAssertEqual(design.partial2Weight, 0.3)
        XCTAssertEqual(design.partial3Weight, 0.1)
        XCTAssertEqual(design.masterScale, 0.25)
        XCTAssertEqual(design.chimesPerSec, 1.0)
    }

    func testToneDesignCachedAccessorMatchesReader() throws {
        let runtime = try BreathRuntime()
        XCTAssertEqual(runtime.toneDesign, try runtime.readToneDesign())
    }

    func testRejectsUnknownPreset() throws {
        let runtime = try BreathRuntime()
        XCTAssertThrowsError(try runtime.preset("nonexistent"))
    }

    func testTotalDurationForCalmPreset() throws {
        let runtime = try BreathRuntime()
        let session = try runtime.createSession(config: Self.calm)
        XCTAssertEqual(session.totalDurationSec, 480)
    }

    func testRejectsInvalidConfig() throws {
        let runtime = try BreathRuntime()
        let bad = SessionConfig(
            inhaleSec: 0, exhaleSec: 6, activeSec: 90, restSec: 30, rounds: 4
        )
        XCTAssertThrowsError(try runtime.createSession(config: bad))
    }

    func testCalmEmitsExpectedEventCounts() throws {
        let events = try runFullSession(config: Self.calm)

        var counts: [String: Int] = [:]
        for ev in events {
            counts[label(ev), default: 0] += 1
        }
        // Calm: 4 rounds × 9 cycles/round × (4 inhale-counts + 6 exhale-counts)
        XCTAssertEqual(counts["inhale-count"], 144)
        XCTAssertEqual(counts["exhale-count"], 216)
        XCTAssertEqual(counts["rest-start"], 4)
        XCTAssertEqual(counts["round-complete"], 4)
        XCTAssertEqual(counts["session-complete"], 1)
    }

    func testFirstEventIsInhaleAtZero() throws {
        let events = try runFullSession(config: Self.calm)
        guard case let .inhaleCount(round, beat, total, atMs) = events.first else {
            return XCTFail("expected first event to be inhale-count")
        }
        XCTAssertEqual(round, 1)
        XCTAssertEqual(beat, 0)
        XCTAssertEqual(total, 4)
        XCTAssertEqual(atMs, 0)
    }

    func testLastEventIsSessionComplete() throws {
        let events = try runFullSession(config: Self.calm)
        guard case let .sessionComplete(atMs) = events.last else {
            return XCTFail("expected last event to be session-complete")
        }
        let totalMs = Double(Self.calm.rounds) * (Self.calm.activeSec + Self.calm.restSec) * 1000
        XCTAssertEqual(atMs, totalMs)
    }

    func testPauseAndResumeShiftEffectiveTime() throws {
        let runtime = try BreathRuntime()
        let session = try runtime.createSession(config: Self.calm)
        let initial = session.start(nowMs: 0)
        // Initial events: inhale-count(beatIndex=0) at t=0
        XCTAssertEqual(initial.count, 1)
        XCTAssertFalse(session.isPaused)

        // Drain inhale-counts at t=1000, 2000, 3000 before pausing so the
        // cursor is at the next pending event (t=4000 exhale-count).
        _ = session.tick(nowMs: 3500)

        // Pause at 3.5s wall time. The first exhale-count is due at
        // effective t=4000.
        session.pause(nowMs: 3500)
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.tick(nowMs: 50000), [], "no events while paused")

        // Resume 5s later. Effective time at wall 8500 = 3500.
        session.resume(nowMs: 8500)
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(session.tick(nowMs: 8900), [], "still before effective 4000")

        let events = session.tick(nowMs: 9001)
        let exhaleEvents = events.compactMap { ev -> SessionEvent? in
            if case .exhaleCount = ev { return ev }
            return nil
        }
        XCTAssertGreaterThanOrEqual(exhaleEvents.count, 1)
        if case let .exhaleCount(round, beat, total, _) = exhaleEvents.first {
            XCTAssertEqual(round, 1)
            XCTAssertEqual(beat, 0)
            XCTAssertEqual(total, 6)
        } else {
            XCTFail("expected exhale-count after resume")
        }
    }

    func testPauseResumeAreIdempotent() throws {
        let runtime = try BreathRuntime()
        let session = try runtime.createSession(config: Self.calm)
        // Safe before start.
        session.pause(nowMs: 0)
        session.resume(nowMs: 0)
        session.start(nowMs: 0)
        session.pause(nowMs: 1000)
        session.pause(nowMs: 2000) // double-pause: no-op
        XCTAssertTrue(session.isPaused)
        session.stop()
        // Safe after stop.
        session.pause(nowMs: 3000)
        session.resume(nowMs: 4000)
    }

    func testRestStartFadeIsAtLeastOneSecond() throws {
        let events = try runFullSession(config: Self.calm)
        let rests = events.compactMap { event -> Double? in
            if case let .restStart(_, _, fade, _) = event { return fade }
            return nil
        }
        XCTAssertEqual(rests.count, 4)
        for fade in rests { XCTAssertGreaterThanOrEqual(fade, 1) }
    }

    // MARK: - helpers

    /// Drive a session with a fake 100ms clock from start to total duration,
    /// matching the runner used by `packages/core/test/session.test.ts`.
    private func runFullSession(config: SessionConfig, stepMs: Double = 100) throws -> [SessionEvent] {
        let runtime = try BreathRuntime()
        let session = try runtime.createSession(config: config)
        var events = session.start(nowMs: 0)
        let totalMs = session.totalDurationSec * 1000
        var t = stepMs
        while t <= totalMs + stepMs {
            events.append(contentsOf: session.tick(nowMs: t))
            t += stepMs
        }
        return events
    }

    private func label(_ event: SessionEvent) -> String {
        switch event {
        case .inhaleCount: return "inhale-count"
        case .exhaleCount: return "exhale-count"
        case .restStart: return "rest-start"
        case .roundComplete: return "round-complete"
        case .sessionComplete: return "session-complete"
        }
    }
}
