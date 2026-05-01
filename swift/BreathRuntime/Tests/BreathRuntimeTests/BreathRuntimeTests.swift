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
        XCTAssertEqual(counts["inhale-start"], 36)
        XCTAssertEqual(counts["exhale-start"], 36)
        XCTAssertEqual(counts["rest-start"], 4)
        XCTAssertEqual(counts["round-complete"], 4)
        XCTAssertEqual(counts["session-complete"], 1)
    }

    func testFirstEventIsInhaleAtZero() throws {
        let events = try runFullSession(config: Self.calm)
        guard case let .inhaleStart(round, durationSec, atMs) = events.first else {
            return XCTFail("expected first event to be inhale-start")
        }
        XCTAssertEqual(round, 1)
        XCTAssertEqual(durationSec, 4)
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
        case .inhaleStart: return "inhale-start"
        case .exhaleStart: return "exhale-start"
        case .restStart: return "rest-start"
        case .roundComplete: return "round-complete"
        case .sessionComplete: return "session-complete"
        }
    }
}
