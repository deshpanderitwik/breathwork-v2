import Foundation

/// Swift port of packages/core/src/session.ts. Same schedule, same events —
/// if we ever spot drift between platforms, this file is the suspect.

public struct SessionConfig: Codable, Equatable {
    public var inhaleSec: Double
    public var exhaleSec: Double
    public var activeSec: Double
    public var restSec: Double
    public var rounds: Int

    public init(inhaleSec: Double, exhaleSec: Double, activeSec: Double, restSec: Double, rounds: Int) {
        self.inhaleSec = inhaleSec
        self.exhaleSec = exhaleSec
        self.activeSec = activeSec
        self.restSec = restSec
        self.rounds = rounds
    }

    public static let `default` = SessionConfig(
        inhaleSec: 4, exhaleSec: 4, activeSec: 120, restSec: 15, rounds: 4
    )

    public var totalDurationSec: Double {
        Double(rounds) * (activeSec + restSec)
    }

    public func formattedDuration() -> String {
        let total = Int(totalDurationSec.rounded())
        let min = total / 60
        let sec = total % 60
        return sec == 0 ? "\(min) min" : "\(min) min \(sec) sec"
    }
}

public enum SessionEvent: Equatable {
    case inhaleStart(round: Int, durationSec: Double, atMs: Double)
    case exhaleStart(round: Int, durationSec: Double, atMs: Double)
    case restStart(round: Int, durationSec: Double, fadeOutSec: Double, atMs: Double)
    case roundComplete(round: Int, atMs: Double)
    case sessionComplete(atMs: Double)

    public var atMs: Double {
        switch self {
        case .inhaleStart(_, _, let t), .exhaleStart(_, _, let t),
             .restStart(_, _, _, let t), .roundComplete(_, let t),
             .sessionComplete(let t):
            return t
        }
    }
}

public struct InvalidSessionConfig: Error { public let message: String }

/// The fade duration used at active → rest boundary.
public let activeToRestFadeSec: Double = 1.5

public final class BreathSession {
    private let config: SessionConfig
    private var queue: [(atMs: Double, event: SessionEvent)] = []
    private var cursor = 0
    private var stopped = false

    public init(config: SessionConfig) throws {
        let positives: [(String, Double)] = [
            ("inhaleSec", config.inhaleSec),
            ("exhaleSec", config.exhaleSec),
            ("activeSec", config.activeSec),
            ("restSec", config.restSec),
            ("rounds", Double(config.rounds)),
        ]
        for (name, v) in positives where !v.isFinite || v <= 0 {
            throw InvalidSessionConfig(
                message: "\(name) must be a finite positive number, got \(v)"
            )
        }
        let cycle = config.inhaleSec + config.exhaleSec
        if cycle > config.activeSec {
            throw InvalidSessionConfig(
                message: "activeSec (\(config.activeSec)) must fit one breath cycle (\(cycle))"
            )
        }
        self.config = config
    }

    public func start(nowMs: Double) -> [SessionEvent] {
        guard !stopped else { return [] }
        queue = Self.buildSchedule(config: config, startMs: nowMs)
        cursor = 0
        return drain(nowMs: nowMs)
    }

    public func tick(nowMs: Double) -> [SessionEvent] {
        guard !stopped, !queue.isEmpty else { return [] }
        return drain(nowMs: nowMs)
    }

    public func stop() {
        stopped = true
        queue = []
    }

    private func drain(nowMs: Double) -> [SessionEvent] {
        var out: [SessionEvent] = []
        while cursor < queue.count {
            let entry = queue[cursor]
            if entry.atMs > nowMs { break }
            cursor += 1
            out.append(entry.event)
        }
        return out
    }

    private static func buildSchedule(
        config: SessionConfig, startMs: Double
    ) -> [(atMs: Double, event: SessionEvent)] {
        var out: [(Double, SessionEvent)] = []
        let cycle = config.inhaleSec + config.exhaleSec

        for r in 1...config.rounds {
            let roundStart = startMs + Double(r - 1) * (config.activeSec + config.restSec) * 1000

            var c = 0
            while true {
                let inhaleOffset = Double(c) * cycle
                let exhaleOffset = inhaleOffset + config.inhaleSec
                if inhaleOffset >= config.activeSec { break }

                let inhaleAt = roundStart + inhaleOffset * 1000
                out.append((inhaleAt, .inhaleStart(
                    round: r, durationSec: config.inhaleSec, atMs: inhaleAt
                )))

                if exhaleOffset < config.activeSec {
                    let exhaleAt = roundStart + exhaleOffset * 1000
                    out.append((exhaleAt, .exhaleStart(
                        round: r, durationSec: config.exhaleSec, atMs: exhaleAt
                    )))
                }
                c += 1
            }

            let restAt = roundStart + config.activeSec * 1000
            out.append((restAt, .restStart(
                round: r, durationSec: config.restSec,
                fadeOutSec: activeToRestFadeSec, atMs: restAt
            )))

            let roundCompleteAt = restAt + config.restSec * 1000
            out.append((roundCompleteAt, .roundComplete(round: r, atMs: roundCompleteAt)))
        }

        let sessionCompleteAt = startMs + config.totalDurationSec * 1000
        out.append((sessionCompleteAt, .sessionComplete(atMs: sessionCompleteAt)))

        let indexed = out.enumerated().map { ($0, $1.0, $1.1) }
        let sorted = indexed.sorted { a, b in
            a.1 == b.1 ? a.0 < b.0 : a.1 < b.1
        }
        return sorted.map { ($0.1, $0.2) }
    }
}
