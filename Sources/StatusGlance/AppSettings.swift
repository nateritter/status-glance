import Foundation
import Combine
import ServiceManagement

/// UserDefaults-backed, observable settings model. Main-actor isolated because it
/// drives UI and is read/written from AppKit/SwiftUI.
@MainActor
final class AppSettings: ObservableObject {

    enum Keys {
        static let statusPageURL = "statusPageURL"
        static let displayNameOverride = "displayNameOverride"
        static let pollInterval = "pollInterval"
        static let customLogoPath = "customLogoPath"
    }

    static let defaultStatusPageURL = "https://status.claude.com"
    static let defaultPollInterval: Double = 60
    static let minimumPollInterval: Double = 15

    private let defaults: UserDefaults

    @Published var statusPageURL: String {
        didSet { defaults.set(statusPageURL, forKey: Keys.statusPageURL) }
    }

    @Published var displayNameOverride: String {
        didSet { defaults.set(displayNameOverride, forKey: Keys.displayNameOverride) }
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

    @Published var customLogoPath: String {
        didSet { defaults.set(customLogoPath, forKey: Keys.customLogoPath) }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.statusPageURL = (defaults.string(forKey: Keys.statusPageURL)?.isEmpty == false
            ? defaults.string(forKey: Keys.statusPageURL)!
            : Self.defaultStatusPageURL)

        self.displayNameOverride = defaults.string(forKey: Keys.displayNameOverride) ?? ""

        let storedInterval = defaults.object(forKey: Keys.pollInterval) as? Double
        self.pollInterval = max(Self.minimumPollInterval, storedInterval ?? Self.defaultPollInterval)

        self.customLogoPath = defaults.string(forKey: Keys.customLogoPath) ?? ""

        self.launchAtLogin = Self.currentLaunchAtLoginState()
    }

    /// The effective display name shown in the UI (override wins, else falls back).
    func effectiveName(pageName: String?) -> String {
        let trimmed = displayNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
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
