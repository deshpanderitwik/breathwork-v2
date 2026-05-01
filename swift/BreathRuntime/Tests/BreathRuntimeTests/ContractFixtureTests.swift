import XCTest
@testable import BreathRuntime

/// Contract-parity tests: drive the JS core through the Swift bridge and
/// assert the emitted event sequence is byte-equal to the fixture written
/// by `packages/core/test/fixtures/generate.mjs`.
///
/// If these fail, either:
///   - The TS scheduler changed and you need to rerun `gen-fixtures.sh`
///     and commit the diff, or
///   - The Swift ↔ JS marshalling has drifted (real bug).
///
/// Either way you'll know.
final class ContractFixtureTests: XCTestCase {

    func testCalmFixtureMatches() throws { try assertParity(preset: "calm") }
    func testFocusFixtureMatches() throws { try assertParity(preset: "focus") }
    func testDeepFixtureMatches() throws { try assertParity(preset: "deep") }

    // MARK: - helpers

    private func assertParity(
        preset id: String, file: StaticString = #file, line: UInt = #line
    ) throws {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json") else {
            XCTFail(
                "fixture \(id).json missing from test bundle — run scripts/sync-core.sh",
                file: file, line: line
            )
            return
        }
        let data = try Data(contentsOf: url)
        let expected = try JSONDecoder().decode([FixtureEvent].self, from: data)

        let runtime = try BreathRuntime()
        let config = try runtime.preset(id)
        let session = try runtime.createSession(config: config)

        var actual: [FixtureEvent] = session.start(nowMs: 0).map(FixtureEvent.init)
        let totalMs = session.totalDurationSec * 1000
        let stepMs: Double = 100
        var t = stepMs
        while t <= totalMs + stepMs {
            actual.append(contentsOf: session.tick(nowMs: t).map(FixtureEvent.init))
            t += stepMs
        }

        XCTAssertEqual(
            actual.count, expected.count,
            "preset '\(id)': event count drift (Swift \(actual.count) vs fixture \(expected.count))",
            file: file, line: line
        )
        for (i, pair) in zip(actual, expected).enumerated() {
            XCTAssertEqual(
                pair.0, pair.1,
                "preset '\(id)' event #\(i) differs",
                file: file, line: line
            )
        }
    }
}

/// JSON-shaped event used for both fixture decoding and Swift event encoding.
/// Keys mirror the JS-emitted POJO exactly; absent fields stay `nil`.
private struct FixtureEvent: Codable, Equatable {
    let kind: String
    let round: Int?
    let durationSec: Double?
    let fadeOutSec: Double?
    let atMs: Double

    init(kind: String, round: Int? = nil, durationSec: Double? = nil,
         fadeOutSec: Double? = nil, atMs: Double) {
        self.kind = kind
        self.round = round
        self.durationSec = durationSec
        self.fadeOutSec = fadeOutSec
        self.atMs = atMs
    }

    init(_ event: SessionEvent) {
        switch event {
        case let .inhaleStart(round, dur, at):
            self.init(kind: "inhale-start", round: round, durationSec: dur, atMs: at)
        case let .exhaleStart(round, dur, at):
            self.init(kind: "exhale-start", round: round, durationSec: dur, atMs: at)
        case let .restStart(round, dur, fade, at):
            self.init(kind: "rest-start", round: round, durationSec: dur,
                      fadeOutSec: fade, atMs: at)
        case let .roundComplete(round, at):
            self.init(kind: "round-complete", round: round, atMs: at)
        case let .sessionComplete(at):
            self.init(kind: "session-complete", atMs: at)
        }
    }
}
