import SwiftUI
import AppKit

/// Settings form, persisted via `AppSettings` (UserDefaults). On apply, the
/// `onApply` callback lets the AppDelegate restart polling / re-render the glyph.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    /// Called when the user wants changes to take effect (re-point + re-poll).
    let onApply: () -> Void

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
                displayNameField
                pollIntervalField
                customLogoField
                launchAtLoginToggle
            }

            HStack {
                Spacer()
                Button("Apply") {
                    onApply()
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

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Display name (optional override)")
            TextField("Defaults to the page name", text: $settings.displayNameOverride)
                .textFieldStyle(.roundedBorder)
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

    private var customLogoField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Custom logo image (optional, local file)")
            HStack(spacing: 8) {
                TextField("Empty = built-in glyph", text: $settings.customLogoPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseLogo() }
                if !settings.customLogoPath.isEmpty {
                    Button("Clear") { settings.customLogoPath = "" }
                }
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

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image, .pdf]
        if panel.runModal() == .OK, let url = panel.url {
            settings.customLogoPath = url.path
        }
    }

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
