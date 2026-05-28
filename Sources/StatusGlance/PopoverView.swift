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
    private var indicator: Indicator { poller.snapshot.effectiveIndicator }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.separator)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    componentsSection
                    if let incidents = summary?.incidents, !incidents.isEmpty {
                        incidentsSection(incidents)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 360)
            Divider().overlay(Palette.separator)
            footer
        }
        .frame(width: 300)
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
        if poller.snapshot.isError {
            return indicator.fallbackDescription
        }
        return summary?.status.description ?? indicator.fallbackDescription
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

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Components")
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

    private func componentRow(_ comp: Component) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Palette.color(for: comp.status))
                .frame(width: 8, height: 8)
            Text(comp.name)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if comp.status != .operational {
                Text(comp.status.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.color(for: comp.status))
            }
        }
        // Indent grouped components.
        .padding(.leading, comp.groupId != nil ? 14 : 0)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
