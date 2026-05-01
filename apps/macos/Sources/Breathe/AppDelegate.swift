import Cocoa
import Combine
import SwiftUI
import BreathCore

/// macOS menu bar shell:
///   - Left-click  → toggle session
///   - Right-click → popover: live session view (when running) + settings
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    private let runtime: BreathRuntime
    private let store = SettingsStore()
    private let tones = ToneEngine()
    private let state: AppState
    private lazy var controller = SessionController(state: state, tones: tones, runtime: runtime)

    private var runningCancellable: AnyCancellable?

    override init() {
        do {
            self.runtime = try BreathRuntime()
        } catch {
            fatalError("BreathRuntime failed to load: \(error)")
        }
        self.state = AppState(config: store.load(default: runtime.defaultConfig))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Breathwork")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 380)
        popover.contentViewController = NSHostingController(
            rootView: MacPopoverView(state: state, onConfigChange: { [weak self] new in
                self?.store.save(new)
            })
        )

        // Keep the status item icon in sync with running state.
        runningCancellable = state.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                self?.statusItem.button?.image = NSImage(
                    systemSymbolName: running ? "stop.fill" : "wind",
                    accessibilityDescription: "Breathwork"
                )
            }

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "Quit Breathe",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showPopover(from: sender)
        } else {
            controller.toggle()
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

// MARK: - Popover view

private struct MacPopoverView: View {
    @ObservedObject var state: AppState
    let onConfigChange: (SessionConfig) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("BREATHE")
                .font(.system(size: 11, weight: .medium))
                .kerning(1.0)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider()

            if state.isRunning {
                VStack(spacing: 10) {
                    Text(state.currentPhase.isEmpty ? " " : state.currentPhase)
                        .font(.system(size: 20, weight: .light))
                    Text("Round \(state.currentRound) of \(state.config.rounds)")
                        .font(.system(size: 10, weight: .medium))
                        .kerning(1.0)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    TimelineView(config: state.config, elapsedMs: state.elapsedMs)
                        .frame(height: 6)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                }
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                Divider()
            }

            SettingsView(config: Binding(
                get: { state.config },
                set: { state.config = $0; onConfigChange($0) }
            ))
        }
        .frame(width: 300)
    }
}
