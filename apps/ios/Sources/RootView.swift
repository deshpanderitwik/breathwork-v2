import SwiftUI
import UIKit
import BreathCore

/// Full-screen iOS UI. Setup form when idle, live session view when running.
struct RootView: View {
    @ObservedObject var state: AppState
    let controller: SessionController
    let onConfigChange: (SessionConfig) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if state.isRunning {
                    SessionView(
                        state: state,
                        onPauseToggle: {
                            state.isPaused ? controller.resume() : controller.pause()
                        },
                        onStop: { controller.stop() }
                    )
                } else {
                    SetupView(
                        state: state,
                        onStart: { controller.start() },
                        onConfigChange: onConfigChange
                    )
                }
            }
            .foregroundColor(.white)
        }
        .onChange(of: state.isRunning) { _, running in
            // Keep screen awake while running; let it sleep otherwise.
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }
}

// MARK: - Setup

private struct SetupView: View {
    @ObservedObject var state: AppState
    let onStart: () -> Void
    let onConfigChange: (SessionConfig) -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("BREATHE")
                .font(.system(size: 13, weight: .medium))
                .kerning(1.2)
                .foregroundColor(.white.opacity(0.5))

            SettingsView(config: Binding(
                get: { state.config },
                set: { state.config = $0; onConfigChange($0) }
            ))
            .background(
                VStack(spacing: 0) {
                    Divider().overlay(Color.white.opacity(0.15))
                    Spacer()
                    Divider().overlay(Color.white.opacity(0.15))
                }
            )

            HStack {
                Text("Total · \(state.config.formattedDuration())")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button(action: onStart) {
                    Text("Start")
                        .font(.system(size: 15, weight: .medium))
                        .kerning(0.5)
                        .foregroundColor(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                        )
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Session

private struct SessionView: View {
    @ObservedObject var state: AppState
    let onPauseToggle: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(phaseLabel)
                .font(.system(size: 56, weight: .light))
                .kerning(-1.0)
                .foregroundColor(.white)
                .opacity(state.isPaused ? 0.4 : 1.0)

            Text("Round \(state.currentRound) of \(state.config.rounds)")
                .font(.system(size: 13, weight: .medium))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundColor(.white.opacity(0.5))

            TimelineView(config: state.config, elapsedMs: state.elapsedMs)
                .frame(height: 6)
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .opacity(state.isPaused ? 0.5 : 1.0)

            Spacer()

            HStack(spacing: 24) {
                Button(action: onPauseToggle) {
                    Text(state.isPaused ? "Resume" : "Pause")
                        .font(.system(size: 12, weight: .medium))
                        .kerning(1.4)
                        .textCase(.uppercase)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                Button(action: onStop) {
                    Text("Stop")
                        .font(.system(size: 12, weight: .medium))
                        .kerning(1.4)
                        .textCase(.uppercase)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
            .padding(.bottom, 32)
        }
    }

    private var phaseLabel: String {
        if state.isPaused { return "Paused" }
        return state.currentPhase.isEmpty ? " " : state.currentPhase
    }
}
