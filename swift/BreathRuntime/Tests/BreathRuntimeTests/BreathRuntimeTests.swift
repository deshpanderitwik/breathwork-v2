import XCTest
@testable import BreathRuntime

final class BreathRuntimeTests: XCTestCase {
    func testRuntimeInitialises() throws {
        let runtime = try BreathRuntime()
        _ = runtime
    }

    // TODO(phase-1): mirror the contract tests from
    // packages/core/test/session.test.ts here, driving the runtime with a fake
    // clock and asserting the same event sequence. Same spec, both languages.
}
