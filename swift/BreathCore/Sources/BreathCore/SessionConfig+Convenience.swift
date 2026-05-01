import Foundation
@_exported import BreathRuntime

/// Pure-Swift sugar on the canonical `SessionConfig` from BreathRuntime.
/// The default value is owned by the JS core (`PRESETS.calm`) and read via
/// `BreathRuntime.defaultConfig` — there is no hand-typed default here.
public extension SessionConfig {
    var totalDurationSec: Double {
        Double(rounds) * (activeSec + restSec)
    }

    func formattedDuration() -> String {
        let total = Int(totalDurationSec.rounded())
        let min = total / 60
        let sec = total % 60
        return sec == 0 ? "\(min) min" : "\(min) min \(sec) sec"
    }
}
