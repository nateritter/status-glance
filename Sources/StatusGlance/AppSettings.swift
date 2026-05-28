import Foundation
import Combine
import ServiceManagement

/// UserDefaults-backed, observable settings model. Main-actor isolated because it
/// drives UI and is read/written from AppKit/SwiftUI.
@MainActor
final class AppSettings: ObservableObject {

    enum Keys {
        static let statusPageURL = "statusPageURL"
        static let pollInterval = "pollInterval"
        static let trackedComponent = "trackedComponent"
    }

    static let defaultStatusPageURL = "https://status.claude.com"
    static let defaultPollInterval: Double = 60
    static let minimumPollInterval: Double = 15

    /// Sentinel `trackedComponent` value meaning "follow the page's overall status".
    nonisolated static let overallTracking = "__overall__"
    /// Default tracked component (the menu-bar glyph follows this one's status).
    static let defaultTrackedComponent = "claude.ai"

    private let defaults: UserDefaults

    @Published var statusPageURL: String {
        didSet { defaults.set(statusPageURL, forKey: Keys.statusPageURL) }
    }

    /// Always clamped to at least `minimumPollInterval`.
    @Published var pollInterval: Double {
        didSet {
            let clamped = max(Self.minimumPollInterval, pollInterval)
            if clamped != pollInterval {
                pollInterval = clamped
                return
            }
            defaults.set(pollInterval, forKey: Keys.pollInterval)
        }
    }

    /// Which component's status drives the menu-bar glyph color. `overallTracking`
    /// (the default sentinel) means follow the page's overall indicator; otherwise
    /// the value is a component name.
    @Published var trackedComponent: String {
        didSet { defaults.set(trackedComponent, forKey: Keys.trackedComponent) }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.statusPageURL = (defaults.string(forKey: Keys.statusPageURL)?.isEmpty == false
            ? defaults.string(forKey: Keys.statusPageURL)!
            : Self.defaultStatusPageURL)

        let storedInterval = defaults.object(forKey: Keys.pollInterval) as? Double
        self.pollInterval = max(Self.minimumPollInterval, storedInterval ?? Self.defaultPollInterval)

        self.trackedComponent = defaults.string(forKey: Keys.trackedComponent) ?? Self.defaultTrackedComponent

        self.launchAtLogin = Self.currentLaunchAtLoginState()
    }

    /// The display name shown in the UI — the status page's own name, or a
    /// neutral fallback before the first successful fetch.
    func effectiveName(pageName: String?) -> String {
        if let pageName, !pageName.isEmpty { return pageName }
        return "Status"
    }

    // MARK: - Launch at login (best-effort, availability-guarded)

    private static func currentLaunchAtLoginState() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Best-effort: log and leave the toggle reflecting the user's intent.
            NSLog("StatusGlance: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
