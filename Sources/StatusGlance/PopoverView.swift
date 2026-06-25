import SwiftUI
import AppKit

/// The popover content: header, components, incidents, footer.
struct PopoverView: View {
    @ObservedObject var poller: StatusPoller
    @ObservedObject var settings: AppSettings

    let onRefresh: () -> Void
    let onOpenStatusPage: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    private var summary: Summary? { poller.snapshot.summary }

    /// The tracked target drives the pill (matches the menu-bar glyph color).
    private var indicator: Indicator {
        poller.snapshot.trackedIndicator(tracked: settings.trackedComponent)
    }

    private var isTrackingOverall: Bool {
        let t = settings.trackedComponent
        return t.isEmpty || t == AppSettings.overallTracking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.separator)
            // Size to content so every platform + history shows without scrolling.
            VStack(alignment: .leading, spacing: 14) {
                componentsSection
                if let incidents = summary?.incidents, !incidents.isEmpty {
                    incidentsSection(incidents)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().overlay(Palette.separator)
            footer
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.background)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(settings.effectiveName(pageName: summary?.page.name))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if let updated = relativeUpdated {
                    Text(updated)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            statusPill
            // When tracking a single component, still surface the page-wide status.
            if !isTrackingOverall, let overall = summary?.status.description {
                Text("Overall: \(overall)")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Palette.color(for: indicator))
                .frame(width: 9, height: 9)
            Text(pillText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Palette.color(for: indicator).opacity(0.16))
        )
        .overlay(
            Capsule().stroke(Palette.color(for: indicator).opacity(0.45), lineWidth: 1)
        )
    }

    private var pillText: String {
        poller.snapshot.trackedStatusText(tracked: settings.trackedComponent)
    }

    private var relativeUpdated: String? {
        guard let date = summary?.page.updatedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "updated " + formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Components

    private var visibleComponents: [Component] {
        guard let all = summary?.components else { return [] }
        return all
            .filter { comp in
                // Respect only_show_if_degraded: hide when operational.
                if comp.onlyShowIfDegraded == true && comp.status == .operational {
                    return false
                }
                // Hide group containers themselves; their members render indented.
                if comp.group == true { return false }
                return true
            }
            .sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }
    }

    /// Largest coverage window across components (for the "last N days" caption).
    private var historySpanDays: Int {
        poller.snapshot.incidentHistory.values.map(\.coverageDays).max() ?? 0
    }

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("Components")
                Spacer()
                if historySpanDays > 1 {
                    Text("last \(historySpanDays) days")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            if visibleComponents.isEmpty {
                Text(poller.snapshot.summary == nil ? "Loading…" : "No components to show")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(visibleComponents) { comp in
                    componentRow(comp)
                }
            }
        }
    }

    private func isTracked(_ comp: Component) -> Bool {
        !isTrackingOverall && comp.name == settings.trackedComponent
    }

    private func componentRow(_ comp: Component) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.color(for: comp.status))
                    .frame(width: 8, height: 8)
                Text(comp.name)
                    .font(.system(size: 12, weight: isTracked(comp) ? .semibold : .regular))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if isTracked(comp) {
                    // Marks the component the menu-bar glyph is following.
                    Image(systemName: "asterisk")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
                Spacer(minLength: 8)
                if comp.status != .operational {
                    Text(comp.status.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.color(for: comp.status))
                }
            }
            historyBar(for: comp)
        }
        // Indent grouped components.
        .padding(.leading, comp.groupId != nil ? 14 : 0)
    }

    /// A compact per-day history strip (oldest → newest), like the status page.
    @ViewBuilder
    private func historyBar(for comp: Component) -> some View {
        if let history = poller.snapshot.incidentHistory[comp.id], !history.days.isEmpty {
            GeometryReader { geo in
                let count = history.days.count
                let gap: CGFloat = 1
                let barWidth = max(1.5, (geo.size.width - CGFloat(count - 1) * gap) / CGFloat(count))
                HStack(spacing: gap) {
                    ForEach(history.days) { day in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Palette.color(for: day.indicator))
                            .frame(width: barWidth)
                            .help(historyTooltip(day))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 14)
        }
    }

    private func historyTooltip(_ day: DayBucket) -> String {
        let date = day.date.formatted(.dateTime.month(.abbreviated).day())
        let status = day.indicator == .none ? "Operational" : day.indicator.fallbackDescription
        return "\(date): \(status)"
    }

    // MARK: - Incidents

    private func incidentsSection(_ incidents: [Incident]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Active Incidents")
            ForEach(incidents) { incident in
                incidentRow(incident)
            }
        }
    }

    private func incidentRow(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(incident.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if let impact = incident.impact {
                    Text(impact.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            if let body = incident.incidentUpdates?.first?.body {
                Text(body)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(3)
            }
            if let when = incidentRelative(incident) {
                Text(when)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surface))
    }

    private func incidentRelative(_ incident: Incident) -> String? {
        guard let date = incident.incidentUpdates?.first?.createdAt ?? incident.updatedAt else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note = poller.snapshot.errorNote {
                HStack(spacing: 6) {
                    Circle().fill(StatusColor.gray.color).frame(width: 7, height: 7)
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
            }
            HStack(spacing: 14) {
                footerButton("arrow.clockwise", "Refresh", action: onRefresh)
                footerButton("safari", "Status page", action: onOpenStatusPage)
                Spacer()
                footerIconButton("gearshape", action: onOpenSettings)
                footerIconButton("power", action: onQuit)
            }
            HStack(spacing: 8) {
                footerLink("GitHub", "https://github.com/nateritter/status-glance")
                Text("·").font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                footerLink("nateritter.com", "https://nateritter.com")
                Spacer()
                // Driven by the actual fetch time so Refresh is visibly confirmed.
                if let checked = poller.snapshot.lastCheckedDescription() {
                    Text(checked)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// A subtle text link in the footer. Opens in the default browser.
    @ViewBuilder
    private func footerLink(_ title: String, _ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(title, destination: url)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func footerButton(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.accent)
        }
        .buttonStyle(.plain)
    }

    private func footerIconButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.sectionHeader)
    }
}
