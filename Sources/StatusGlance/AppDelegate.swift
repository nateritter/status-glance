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

        // Settings auto-save (UserDefaults); the Close button just dismisses the
        // window. Changes are applied in windowWillClose (below), so closing via
        // the Close button or the window's red button both take effect.
        let view = SettingsView(settings: settings, poller: poller) { [weak self] in
            self?.settingsWindow?.close()
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

    // On settings-window close: apply changes (re-point + re-poll, refresh glyph)
    // and clear our reference. Covers both the Close button and the red button.
    private lazy var settingsWindowDelegate: SettingsWindowDelegate = {
        SettingsWindowDelegate { [weak self] in
            self?.poller.restart()
            self?.statusItemController.updateGlyph()
            self?.settingsWindow = nil
        }
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
