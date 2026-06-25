import Foundation
import AppKit
import Combine

/// The latest known state the rest of the app renders from. Last-known component
/// data is preserved across a failed fetch; only the overall status flips to gray.
struct StatusSnapshot: Sendable {
    /// The most recent successfully decoded summary (may be nil before first success).
    var summary: Summary?
    /// True when we are currently showing a gray/unknown overall status because the
    /// last fetch failed (or we have never succeeded).
    var isError: Bool
    /// A short human-readable error note for the popover footer (nil when healthy).
    var errorNote: String?
    /// When the last fetch *attempt* completed (success or failure).
    var lastAttempt: Date?
    /// When data was last successfully refreshed.
    var lastSuccess: Date?
    /// Per-component daily history, keyed by component id (from the incident feed).
    var incidentHistory: [String: ComponentHistory] = [:]

    /// The overall indicator to render: real indicator on success, `.unknown` on error.
    var effectiveIndicator: Indicator {
        if isError { return .unknown }
        return summary?.status.indicator ?? .unknown
    }

    /// The indicator the menu-bar glyph should show for the tracked target.
    /// `tracked` is `AppSettings.overallTracking` (overall) or a component name.
    func trackedIndicator(tracked: String) -> Indicator {
        if isError { return .unknown }
        if tracked.isEmpty || tracked == AppSettings.overallTracking {
            return summary?.status.indicator ?? .unknown
        }
        if let comp = summary?.components.first(where: { $0.name == tracked }) {
            return comp.status.asIndicator
        }
        // Tracked component not found on this page — fall back to overall.
        return summary?.status.indicator ?? .unknown
    }

    /// Human-readable status text for the tracked target (tooltip + popover pill).
    func trackedStatusText(tracked: String) -> String {
        if isError { return Indicator.unknown.fallbackDescription }
        if tracked.isEmpty || tracked == AppSettings.overallTracking {
            return summary?.status.description ?? effectiveIndicator.fallbackDescription
        }
        if let comp = summary?.components.first(where: { $0.name == tracked }) {
            return "\(comp.name): \(comp.status.label)"
        }
        return summary?.status.description ?? effectiveIndicator.fallbackDescription
    }

    /// Human-readable "we last fetched" label for the popover, driven by the
    /// actual fetch time (not the status page's own `updated_at`). This is what
    /// makes a manual Refresh visibly do something even when the status is stable.
    func lastCheckedDescription(now: Date = Date()) -> String? {
        guard let last = lastSuccess else { return nil }
        if now.timeIntervalSince(last) < 5 { return "Checked just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Checked " + formatter.localizedString(for: last, relativeTo: now)
    }

    static let empty = StatusSnapshot(summary: nil, isError: false, errorNote: nil,
                                      lastAttempt: nil, lastSuccess: nil)
}

/// Timer-driven poller. Publishes the latest `StatusSnapshot`. Main-actor isolated:
/// owns a Timer and pushes UI-facing state.
@MainActor
final class StatusPoller: ObservableObject {

    @Published private(set) var snapshot: StatusSnapshot = .empty

    private let client: StatuspageClient
    private var settings: AppSettings
    private var timer: Timer?
    private var inFlight: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(client: StatuspageClient = StatuspageClient(), settings: AppSettings) {
        self.client = client
        self.settings = settings
        registerWakeObserver()
    }

    // MARK: - Lifecycle

    /// Start polling: immediate poll, then on the repeating timer.
    func start() {
        if wakeObserver == nil { registerWakeObserver() }
        scheduleTimer()
        refreshNow()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        inFlight?.cancel()
        inFlight = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// Re-read the (possibly changed) interval and URL, then poll immediately.
    func restart() {
        stop()
        start()
    }

    /// Manual / immediate poll.
    func refreshNow() {
        let base = settings.statusPageURL
        inFlight?.cancel()
        inFlight = Task { [weak self] in
            guard let self else { return }
            await self.performFetch(base: base)
        }
    }

    #if DEBUG
    /// Test-only: run one fetch and await its completion deterministically.
    /// Not compiled into release builds.
    func refreshAndWaitForTesting() async {
        await performFetch(base: settings.statusPageURL)
    }
    #endif

    // MARK: - Internals

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(AppSettings.minimumPollInterval, settings.pollInterval)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    private func performFetch(base: String) async {
        do {
            let summary = try await client.fetchSummary(base: base)
            if Task.isCancelled { return }

            // History is best-effort: a failed incidents fetch must not fail the
            // poll. Keep the last-known history if it can't be refreshed.
            var history = snapshot.incidentHistory
            if let incidents = try? await client.fetchIncidents(base: base), !Task.isCancelled {
                history = HistoryBuilder.build(incidents: incidents, components: summary.components)
            }
            if Task.isCancelled { return }

            let now = Date()
            snapshot = StatusSnapshot(
                summary: summary,
                isError: false,
                errorNote: nil,
                lastAttempt: now,
                lastSuccess: now,
                incidentHistory: history
            )
        } catch {
            if Task.isCancelled { return }
            let note: String
            if let spError = error as? StatuspageError {
                note = spError.errorDescription ?? "Fetch failed"
            } else {
                note = error.localizedDescription
            }
            // Keep last-known summary + history; flip overall to gray/unknown.
            snapshot = StatusSnapshot(
                summary: snapshot.summary,
                isError: true,
                errorNote: note,
                lastAttempt: Date(),
                lastSuccess: snapshot.lastSuccess,
                incidentHistory: snapshot.incidentHistory
            )
        }
    }

    private func registerWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }
}
