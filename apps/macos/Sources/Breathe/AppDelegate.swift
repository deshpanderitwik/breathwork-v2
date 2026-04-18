import Cocoa
import SwiftUI

/// Menu bar app:
///   - Left-click  → toggle session (start/stop)
///   - Right-click → settings popover with the same 5 fields as the web app
///
/// Quit is in the settings popover footer.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = SettingsStore()
    private let tones = ToneEngine()

    private var config: SessionConfig = .default
    private var session: BreathSession?
    private var sessionStart = Date()
    private var tickTimer: Timer?
    private var isRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = store.load()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Breathwork")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 340)
        popover.contentViewController = NSHostingController(rootView: makeRootView())

        // Minimal main menu so ⌘Q works.
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

    private func makeRootView() -> some View {
        // SwiftUI needs an ObservableObject to track binding updates across
        // popover re-presentations — a thin box does the job.
        SettingsRoot(
            initial: config,
            onChange: { [weak self] new in
                self?.config = new
                self?.store.save(new)
            }
        )
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showSettingsPopover(from: sender)
        } else {
            toggleSession()
        }
    }

    private func showSettingsPopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.contentViewController = NSHostingController(rootView: makeRootView())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Session lifecycle

    private func toggleSession() {
        if isRunning {
            stopSession()
        } else {
            startSession()
        }
    }

    private func startSession() {
        do {
            session = try BreathSession(config: config)
        } catch let err as InvalidSessionConfig {
            let alert = NSAlert()
            alert.messageText = "Can't start"
            alert.informativeText = err.message
            alert.runModal()
            return
        } catch {
            return
        }

        isRunning = true
        sessionStart = Date()
        updateIconForState()

        let initial = session?.start(nowMs: 0) ?? []
        handleEvents(initial)

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopSession() {
        tickTimer?.invalidate()
        tickTimer = nil
        session?.stop()
        session = nil
        tones.stop()
        isRunning = false
        updateIconForState()
    }

    private func tick() {
        guard let session = session else { return }
        let elapsedMs = Date().timeIntervalSince(sessionStart) * 1000
        let events = session.tick(nowMs: elapsedMs)
        if !events.isEmpty { handleEvents(events) }
    }

    private func handleEvents(_ events: [SessionEvent]) {
        for ev in events {
            switch ev {
            case .inhaleStart(_, let durationSec, _):
                tones.playInhale(durationSec: durationSec)
            case .exhaleStart(_, let durationSec, _):
                tones.playExhale(durationSec: durationSec)
            case .restStart(_, _, let fadeOutSec, _):
                tones.fadeOut(fadeSec: fadeOutSec)
            case .roundComplete:
                break
            case .sessionComplete:
                stopSession()
            }
        }
    }

    private func updateIconForState() {
        let symbol = isRunning ? "stop.fill" : "wind"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol, accessibilityDescription: "Breathwork"
        )
    }
}

// MARK: - SwiftUI root

/// Wraps the form in an ObservableObject so two-way bindings survive
/// popover re-presentation.
private final class SettingsModel: ObservableObject {
    @Published var config: SessionConfig
    init(_ config: SessionConfig) { self.config = config }
}

private struct SettingsRoot: View {
    @StateObject private var model: SettingsModel
    let onChange: (SessionConfig) -> Void

    init(initial: SessionConfig,
         onChange: @escaping (SessionConfig) -> Void) {
        _model = StateObject(wrappedValue: SettingsModel(initial))
        self.onChange = onChange
    }

    var body: some View {
        SettingsView(config: $model.config, onChange: onChange)
    }
}
