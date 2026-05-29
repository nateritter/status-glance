import SwiftUI
import AppKit

/// Settings form, persisted via `AppSettings` (UserDefaults). On apply, the
/// `onApply` callback lets the AppDelegate restart polling / re-render the glyph.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Source of the live component list for the "menu bar tracks" picker.
    @ObservedObject var poller: StatusPoller

    /// Dismisses the settings window. Changes auto-save (UserDefaults) and are
    /// applied when the window closes, so there is no separate Apply step.
    let onClose: () -> Void

    @State private var urlCheck: URLCheckState = .idle

    enum URLCheckState: Equatable {
        case idle
        case checking
        case ok(String)   // page name
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("StatusGlance Settings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                statusPageField
                trackedComponentField
                pollIntervalField
                launchAtLoginToggle
            }

            Divider().overlay(Palette.separator)

            HStack(spacing: 10) {
                aboutLink("GitHub", "https://github.com/nateritter/status-glance")
                Text("·").foregroundStyle(Palette.textSecondary)
                aboutLink("nateritter.com", "https://nateritter.com")
                Spacer()
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Palette.background)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Fields

    private var statusPageField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Status page URL")
            HStack(spacing: 8) {
                TextField("https://status.claude.com", text: $settings.statusPageURL)
                    .textFieldStyle(.roundedBorder)
                Button("Test") { Task { await testURL() } }
            }
            checkRow
        }
    }

    @ViewBuilder
    private var checkRow: some View {
        switch urlCheck {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking…", systemImage: "clock")
                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
        case .ok(let name):
            Label("Reachable — \(name)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(StatusColor.green.color)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(StatusColor.red.color)
        }
    }

    /// Names available to track: every component on the page, plus the current
    /// selection if the page hasn't loaded yet (so the default stays visible).
    private var componentNames: [String] {
        var names = poller.snapshot.summary?.components.map(\.name) ?? []
        let current = settings.trackedComponent
        if !current.isEmpty, current != AppSettings.overallTracking, !names.contains(current) {
            names.insert(current, at: 0)
        }
        return names
    }

    private var trackedComponentField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Menu bar tracks")
            Picker("", selection: $settings.trackedComponent) {
                Text("Overall status").tag(AppSettings.overallTracking)
                if !componentNames.isEmpty {
                    Divider()
                    ForEach(componentNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text("Which platform's status colors the ✽ in your menu bar.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var pollIntervalField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Poll interval (seconds, min 15)")
            HStack {
                TextField("60", value: $settings.pollInterval, formatter: Self.intervalFormatter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Stepper("", value: $settings.pollInterval, in: AppSettings.minimumPollInterval...3600, step: 5)
                    .labelsHidden()
            }
        }
    }

    private var launchAtLoginToggle: some View {
        Toggle(isOn: $settings.launchAtLogin) {
            Text("Launch at login")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textPrimary)
        }
        .toggleStyle(.switch)
    }

    // MARK: - Helpers

    /// A subtle text link in the About row. Opens in the default browser.
    @ViewBuilder
    private func aboutLink(_ title: String, _ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(title, destination: url)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.accent)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.textSecondary)
    }

    private static let intervalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimum = NSNumber(value: AppSettings.minimumPollInterval)
        f.maximum = 3600
        f.maximumFractionDigits = 0
        return f
    }()

    private func testURL() async {
        urlCheck = .checking
        let base = settings.statusPageURL
        do {
            let summary = try await StatuspageClient().fetchSummary(base: base)
            urlCheck = .ok(summary.page.name)
        } catch {
            let msg = (error as? StatuspageError)?.errorDescription ?? error.localizedDescription
            urlCheck = .failed(msg)
        }
    }
}
