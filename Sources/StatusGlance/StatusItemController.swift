import AppKit
import SwiftUI
import Combine

/// Owns the NSStatusItem, renders/tints the glyph, manages the popover and the
/// right-click menu (Refresh / Settings / Quit). Main-actor isolated.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let poller: StatusPoller
    private let settings: AppSettings

    private var cancellables = Set<AnyCancellable>()

    // Callbacks wired by the AppDelegate.
    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    init(poller: StatusPoller, settings: AppSettings) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.poller = poller
        self.settings = settings
        super.init()

        configureButton()
        configurePopover()
        observeState()
        updateGlyph() // initial draw before first poll completes
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imageScaling = .scaleProportionallyUpOrDown
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let content = PopoverView(
            poller: poller,
            settings: settings,
            onRefresh: { [weak self] in self?.onRefresh() },
            onOpenStatusPage: { [weak self] in self?.openStatusPage() },
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.onOpenSettings()
            },
            onQuit: { [weak self] in self?.onQuit() }
        )
        popover.contentViewController = NSHostingController(rootView: content)
    }

    private func observeState() {
        // Redraw the glyph whenever the snapshot or relevant settings change.
        poller.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateGlyph() }
            .store(in: &cancellables)

        // The tracked target changes which component drives the glyph color.
        settings.$trackedComponent
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateGlyph() }
            .store(in: &cancellables)
    }

    // MARK: - Glyph

    func updateGlyph() {
        guard let button = statusItem.button else { return }
        let indicator = poller.snapshot.trackedIndicator(tracked: settings.trackedComponent)
        button.image = GlyphRenderer.menuBarImage(color: StatusColor.nsColor(for: indicator))
        updateTooltip()
    }

    private func updateTooltip() {
        guard let button = statusItem.button else { return }
        let name = settings.effectiveName(pageName: poller.snapshot.summary?.page.name)
        let desc = poller.snapshot.trackedStatusText(tracked: settings.trackedComponent)
        button.toolTip = "\(name) — \(desc)"
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            // Refresh on open for fresh data.
            onRefresh()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // Accessory (LSUIElement) apps aren't the active app, so without this the
            // FIRST click inside the popover is consumed just to activate the app —
            // making buttons like Refresh feel dead until a (rarely-tried) second click.
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    private func showMenu() {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(menuRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openItem = NSMenuItem(title: "Open Status Page", action: #selector(menuOpenStatusPage), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit StatusGlance", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Show the menu, then immediately clear so left-click reverts to popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuRefresh() { onRefresh() }
    @objc private func menuOpenStatusPage() { openStatusPage() }
    @objc private func menuSettings() { onOpenSettings() }
    @objc private func menuQuit() { onQuit() }

    // MARK: - Actions

    private func openStatusPage() {
        let urlString = poller.snapshot.summary?.page.url ?? settings.statusPageURL
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        closePopover()
    }
}
