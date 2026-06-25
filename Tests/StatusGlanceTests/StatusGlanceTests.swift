import XCTest
@testable import StatusGlance

// MARK: - Decoding (real fixtures)

final class DecodingTests: XCTestCase {

    func testSummaryDecodes() throws {
        let s = try Fixture.summary()
        XCTAssertEqual(s.page.name, "Claude")
        XCTAssertEqual(s.components.count, 6)
        XCTAssertTrue(s.components.allSatisfy { $0.status == .operational },
                      "fixture captured an all-operational page")
    }

    // ISC-11: monitoring_at decodes; the lone unresolved incident is the critical one.
    func testUnresolvedIncidentDecodesMonitoringAt() throws {
        let incidents = try Fixture.incidents()
        let open = incidents.filter { $0.resolvedAt == nil }
        XCTAssertEqual(open.count, 1, "fixture has exactly one open incident")
        let inc = try XCTUnwrap(open.first)
        XCTAssertNotNil(inc.monitoringAt, "monitoring_at must decode into monitoringAt")
        XCTAssertEqual(inc.status, "monitoring")
        XCTAssertEqual(inc.impact, "critical")
        XCTAssertNil(inc.resolvedAt)
    }
}

// MARK: - History builder (the streak bug)

final class HistoryBuilderTests: XCTestCase {

    private let cal = Calendar.current

    /// ISC-12 / ISC-15 / ISC-19: the open monitoring/critical incident must NOT
    /// paint a critical streak past its monitoring date. Isolated to that one
    /// incident so legitimate *resolved* incidents (e.g. the real Jun-23 critical)
    /// don't confound the check — those correctly still paint their own days.
    func testUnresolvedCriticalDoesNotStreakToToday() throws {
        let summary = try Fixture.summary()
        let incidents = try Fixture.incidents()
        let openIncident = try XCTUnwrap(incidents.first { $0.resolvedAt == nil },
                                         "fixture has the open monitoring/critical incident")
        let now = iso("2026-06-25T18:00:00Z")
        let hist = HistoryBuilder.build(incidents: [openIncident], components: summary.components, now: now)

        let claudeAI = try XCTUnwrap(summary.components.first { $0.name == "claude.ai" })
        let h = try XCTUnwrap(hist[claudeAI.id])

        // Everything strictly after the monitoring day (Jun 13) and before today
        // must be operational — the 12-day red streak is the bug.
        let afterMonitoring = cal.startOfDay(for: iso("2026-06-14T12:00:00Z"))
        let today = cal.startOfDay(for: now)
        let streakDays = h.days.filter { $0.date >= afterMonitoring && $0.date < today }
        XCTAssertFalse(streakDays.isEmpty, "window should cover days after monitoring")
        XCTAssertTrue(streakDays.allSatisfy { $0.indicator == Indicator.none },
                      "open monitoring incident must not streak past its monitoring date")
    }

    /// ISC-16 / ISC-18: the newest bar per component equals the live component status.
    func testTodayBucketMatchesLiveStatus() throws {
        let summary = try Fixture.summary()
        let incidents = try Fixture.incidents()
        let now = iso("2026-06-25T18:00:00Z")
        let hist = HistoryBuilder.build(incidents: incidents, components: summary.components, now: now)

        for comp in summary.components {
            let h = try XCTUnwrap(hist[comp.id])
            let last = try XCTUnwrap(h.days.last)
            XCTAssertEqual(last.indicator, comp.status.asIndicator,
                           "today's bar for \(comp.name) must match its live status")
        }
    }

    /// ISC-17: a properly resolved incident still paints its [start, resolved] range.
    func testResolvedIncidentStillPaintsRange() throws {
        let now = cal.startOfDay(for: iso("2026-06-25T00:00:00Z"))
        let comp = makeComponent(id: "x", name: "X", status: .operational)
        let inc = makeIncident(status: "resolved", impact: "major",
                               startedAt: cal.date(byAdding: .day, value: -5, to: now),
                               resolvedAt: cal.date(byAdding: .day, value: -3, to: now),
                               components: [makeComponent(id: "x")])
        let h = try XCTUnwrap(HistoryBuilder.build(incidents: [inc], components: [comp], now: now)["x"])
        func ind(_ offset: Int) -> Indicator? {
            let d = cal.date(byAdding: .day, value: offset, to: now)!
            return h.days.first { cal.isDate($0.date, inSameDayAs: d) }?.indicator
        }
        XCTAssertEqual(ind(-5), .major)
        XCTAssertEqual(ind(-3), .major)
        XCTAssertEqual(ind(-2), Indicator.none, "after resolution → operational")
    }

    /// ISC-38 (advisor hardening): a monitoring incident that REGRESSED to
    /// investigating/identified must keep painting past its (now stale) monitoringAt —
    /// impact resumed, so trust monitoringAt only while still in the monitoring state.
    func testMonitoringRegressionKeepsPainting() throws {
        let now = cal.startOfDay(for: iso("2026-06-25T00:00:00Z"))
        let comp = makeComponent(id: "x")
        let inc = makeIncident(status: "identified", impact: "major",
                               startedAt: cal.date(byAdding: .day, value: -8, to: now),
                               monitoringAt: cal.date(byAdding: .day, value: -6, to: now),
                               resolvedAt: nil,
                               updatedAt: cal.date(byAdding: .day, value: -1, to: now),
                               components: [makeComponent(id: "x")])
        let h = try XCTUnwrap(HistoryBuilder.build(incidents: [inc], components: [comp], now: now)["x"])
        func ind(_ offset: Int) -> Indicator? {
            let d = cal.date(byAdding: .day, value: offset, to: now)!
            return h.days.first { cal.isDate($0.date, inSameDayAs: d) }?.indicator
        }
        XCTAssertEqual(ind(-5), .major, "regressed incident must paint past its stale monitoringAt")
        XCTAssertEqual(ind(-1), .major, "painted up to the last update")
    }

    /// ISC-13: an unresolved incident with no monitoringAt ends at updatedAt, not now.
    func testUnresolvedWithoutMonitoringEndsAtUpdatedAt() throws {
        let now = cal.startOfDay(for: iso("2026-06-25T00:00:00Z"))
        let comp = makeComponent(id: "x")
        let inc = makeIncident(status: "investigating", impact: "major",
                               startedAt: cal.date(byAdding: .day, value: -8, to: now),
                               monitoringAt: nil, resolvedAt: nil,
                               updatedAt: cal.date(byAdding: .day, value: -6, to: now),
                               components: [makeComponent(id: "x")])
        let h = try XCTUnwrap(HistoryBuilder.build(incidents: [inc], components: [comp], now: now)["x"])
        func ind(_ offset: Int) -> Indicator? {
            let d = cal.date(byAdding: .day, value: offset, to: now)!
            return h.days.first { cal.isDate($0.date, inSameDayAs: d) }?.indicator
        }
        XCTAssertEqual(ind(-8), .major)
        XCTAssertEqual(ind(-6), .major, "painted up to updatedAt")
        XCTAssertEqual(ind(-5), Indicator.none, "not painted past updatedAt")
    }
}

// MARK: - Color source of truth

final class StatusColorTests: XCTestCase {

    // ISC-20
    func testIndicatorPalette() {
        XCTAssertEqual(StatusColor.hex(for: .none), StatusHex(0x3FB950))
        XCTAssertEqual(StatusColor.hex(for: .minor), StatusHex(0xF0B429))
        XCTAssertEqual(StatusColor.hex(for: .major), StatusHex(0xF0883E))
        XCTAssertEqual(StatusColor.hex(for: .critical), StatusHex(0xE5484D))
        XCTAssertEqual(StatusColor.hex(for: .maintenance), StatusHex(0x3B82F6))
        XCTAssertEqual(StatusColor.hex(for: Indicator.unknown), StatusHex(0x8B949E))
    }

    // ISC-21
    func testComponentStatusPaletteMatchesIndicator() {
        let pairs: [(ComponentStatus, Indicator)] = [
            (.operational, .none), (.degradedPerformance, .minor),
            (.partialOutage, .major), (.majorOutage, .critical),
            (.underMaintenance, .maintenance), (ComponentStatus.unknown, Indicator.unknown)
        ]
        for (status, indicator) in pairs {
            XCTAssertEqual(StatusColor.hex(for: status), StatusColor.hex(for: indicator),
                           "\(status) must share the palette of \(indicator)")
        }
    }
}

// MARK: - Snapshot "last checked" indicator (refresh feedback)

final class SnapshotTests: XCTestCase {

    // ISC-25
    func testLastCheckedJustNow() {
        var s = StatusSnapshot.empty
        let now = Date()
        s.lastSuccess = now
        XCTAssertEqual(s.lastCheckedDescription(now: now), "Checked just now")
    }

    // ISC-26
    func testLastCheckedRelative() {
        var s = StatusSnapshot.empty
        let now = Date()
        s.lastSuccess = now.addingTimeInterval(-120)
        let text = s.lastCheckedDescription(now: now)
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.hasPrefix("Checked"))
    }

    func testLastCheckedNilBeforeFirstSuccess() {
        XCTAssertNil(StatusSnapshot.empty.lastCheckedDescription(now: Date()))
    }
}

// MARK: - Poller (refresh actually fetches + updates state)

@MainActor
final class PollerTests: XCTestCase {

    private func freshSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "sg-test-\(UUID().uuidString)")!)
    }

    // ISC-22 / ISC-23
    func testRefreshPopulatesSnapshot() async throws {
        let summaryData = Fixture.data("summary")
        let incidentsData = Fixture.data("incidents")
        let session = mockSession { req in
            let url = req.url!
            let data = url.absoluteString.contains("incidents") ? incidentsData : summaryData
            return (okResponse(url), data)
        }
        let poller = StatusPoller(client: StatuspageClient(session: session), settings: freshSettings())
        await poller.refreshAndWaitForTesting()

        XCTAssertNotNil(poller.snapshot.summary)
        XCTAssertFalse(poller.snapshot.isError)
        XCTAssertNotNil(poller.snapshot.lastSuccess)
        XCTAssertFalse(poller.snapshot.incidentHistory.isEmpty)
    }

    // ISC-24 / ISC-27
    func testFailedFetchKeepsLastSummary() async throws {
        let summaryData = Fixture.data("summary")
        let incidentsData = Fixture.data("incidents")
        let box = FailBox()
        let session = mockSession { req in
            if box.fail { throw URLError(.notConnectedToInternet) }
            let url = req.url!
            let data = url.absoluteString.contains("incidents") ? incidentsData : summaryData
            return (okResponse(url), data)
        }
        let poller = StatusPoller(client: StatuspageClient(session: session), settings: freshSettings())
        await poller.refreshAndWaitForTesting()
        XCTAssertNotNil(poller.snapshot.summary)

        box.fail = true
        await poller.refreshAndWaitForTesting()
        XCTAssertTrue(poller.snapshot.isError)
        XCTAssertNotNil(poller.snapshot.errorNote)
        XCTAssertNotNil(poller.snapshot.summary, "a transient failure must not clear last-known data")
    }
}

/// Thread-safe-ish flag box for toggling mock failure between awaits.
final class FailBox: @unchecked Sendable {
    var fail = false
}
