import Foundation

/// Persists SessionConfig across launches. Same key as the web app's
/// localStorage: `breathe.session-config.v1`.
public final class SettingsStore {
    private let key = "breathe.session-config.v1"
    private let defaults = UserDefaults.standard

    public init() {}

    public func load() -> SessionConfig {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SessionConfig.self, from: data),
              decoded.inhaleSec > 0, decoded.exhaleSec > 0,
              decoded.activeSec > 0, decoded.restSec > 0, decoded.rounds > 0
        else {
            return .default
        }
        return decoded
    }

    public func save(_ config: SessionConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }
}
