import AppKit
import SwiftUI

/// Owns the settings, poller, and status-item controller; wires them together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var settings: AppSettings!
    private var poller: StatusPoller!
    private var statusItemController: StatusItemController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, lives in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        let settings = AppSettings()
        let poller = StatusPoller(settings: settings)
        let controller = StatusItemController(poller: poller, settings: settings)

        self.settings = settings
        self.poller = poller
        self.statusItemController = controller

        controller.onRefresh = { [weak poller] in poller?.refreshNow() }
        controller.onOpenSettings = { [weak self] in self?.showSettingsWindow() }
        controller.onQuit = { NSApp.terminate(nil) }

        // Immediate poll + start the repeating timer + wake observer.
        poller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller?.stop()
    }

    // MARK: - Settings window

    private func showSettingsWindow() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(settings: settings) { [weak self] in
            // Apply: re-point + re-poll, refresh glyph immediately.
            self?.poller.restart()
            self?.statusItemController.updateGlyph()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "StatusGlance Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = settingsWindowDelegate

        self.settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // Keep a delegate to clear our reference when the settings window closes.
    private lazy var settingsWindowDelegate: SettingsWindowDelegate = {
        SettingsWindowDelegate { [weak self] in self?.settingsWindow = nil }
    }()
}

/// Clears the AppDelegate's settings-window reference on close.
@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
