import Foundation

/// One calendar day's worst observed status for a single component.
struct DayBucket: Sendable, Identifiable {
    let id: Int          // index within the window, 0 = oldest
    let date: Date       // start-of-day
    let indicator: Indicator
}

/// A component's per-day status history across the covered window (oldest → newest).
struct ComponentHistory: Sendable {
    let componentID: String
    let days: [DayBucket]
    var coverageDays: Int { days.count }
}

/// Builds per-component daily history from the Statuspage incident feed.
///
/// Honesty note: the public `incidents.json` returns only the ~50 most recent
/// incidents, so we can only be sure of full coverage back to the oldest incident
/// in the feed. We therefore start the window at that oldest incident (clamped to
/// `maxDays`) rather than always drawing a full 90-day bar that would imply
/// "operational" for days we have no data on. Days with no incident touching a
/// component render as operational (`.none`).
enum HistoryBuilder {
    static func build(incidents: [Incident],
                      components: [Component],
                      now: Date = Date(),
                      maxDays: Int = 90,
                      calendar: Calendar = .current) -> [String: ComponentHistory] {
        guard !components.isEmpty else { return [:] }

        let startOfToday = calendar.startOfDay(for: now)
        let earliestAllowed = calendar.date(byAdding: .day, value: -(maxDays - 1), to: startOfToday) ?? startOfToday

        let oldestIncident = incidents.compactMap { $0.startedAt }.min()
        let windowStart: Date = {
            guard let oldest = oldestIncident else { return startOfToday }
            return max(calendar.startOfDay(for: oldest), earliestAllowed)
        }()

        let dayCount = (calendar.dateComponents([.day], from: windowStart, to: startOfToday).day ?? 0) + 1
        let dayStarts: [Date] = (0..<dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: windowStart)
        }

        var result: [String: ComponentHistory] = [:]
        for comp in components {
            var buckets = dayStarts.enumerated().map { idx, day in
                DayBucket(id: idx, date: day, indicator: .none)
            }
            for incident in incidents {
                guard incident.components?.contains(where: { $0.id == comp.id }) == true else { continue }
                let impact = Indicator(impact: incident.impact)
                guard impact.severity > Indicator.none.severity else { continue }
                guard let start = incident.startedAt else { continue }
                let startDay = calendar.startOfDay(for: start)
                let endDay = calendar.startOfDay(for: incident.resolvedAt ?? now)
                for idx in buckets.indices {
                    let day = buckets[idx].date
                    if day >= startDay, day <= endDay, impact.severity > buckets[idx].indicator.severity {
                        buckets[idx] = DayBucket(id: idx, date: day, indicator: impact)
                    }
                }
            }
            result[comp.id] = ComponentHistory(componentID: comp.id, days: buckets)
        }
        return result
    }
}
