import SwiftUI
import BreathCore

@main
struct BreatheApp: App {
    @StateObject private var state = AppState()
    private let store = SettingsStore()
    private let tones = ToneEngine()
    private let controller: SessionController

    init() {
        let loadedState = AppState()
        loadedState.config = SettingsStore().load()
        _state = StateObject(wrappedValue: loadedState)
        self.controller = SessionController(state: loadedState, tones: tones)
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
