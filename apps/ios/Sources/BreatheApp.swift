import SwiftUI
import BreathCore

@main
struct BreatheApp: App {
    @StateObject private var state: AppState
    private let store = SettingsStore()
    private let tones: ToneEngine
    private let runtime: BreathRuntime
    private let controller: SessionController

    init() {
        let runtime: BreathRuntime
        do {
            runtime = try BreathRuntime()
        } catch {
            fatalError("BreathRuntime failed to load: \(error)")
        }
        self.runtime = runtime
        self.tones = ToneEngine(design: runtime.toneDesign)

        let store = SettingsStore()
        let loadedState = AppState(config: store.load(default: runtime.defaultConfig))
        _state = StateObject(wrappedValue: loadedState)

        self.controller = SessionController(state: loadedState, tones: tones, runtime: runtime)
    }

    var body: some Scene {
        WindowGroup {
            RootView(state: state, controller: controller, onConfigChange: { new in
                store.save(new)
            })
            .preferredColorScheme(.dark)
        }
    }
}
