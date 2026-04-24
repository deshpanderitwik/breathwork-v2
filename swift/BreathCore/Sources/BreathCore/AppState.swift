import Foundation
import SwiftUI

/// Observable session state shared between the platform shell and the UI.
/// The shell (AppDelegate on macOS, App scene on iOS) owns an instance,
/// mutates it on events, and passes it to views as an ObservedObject.
public final class AppState: ObservableObject {
    @Published public var config: SessionConfig = .default
    @Published public var isRunning: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var elapsedMs: Double = 0
    @Published public var currentPhase: String = ""
    @Published public var currentRound: Int = 1

    public init() {}
}
