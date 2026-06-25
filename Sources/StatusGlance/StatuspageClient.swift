import Foundation

// MARK: - Codable models (match Atlassian Statuspage v2 summary.json exactly).
// Decoded with JSONDecoder().keyDecodingStrategy = .convertFromSnakeCase, so
// property names are camelCase and map to the snake_case JSON keys automatically.

struct Summary: Codable, Sendable {
    let page: PageInfo
    let status: OverallStatus
    let components: [Component]
    let incidents: [Incident]
    let scheduledMaintenances: [Incident]
}

struct PageInfo: Codable, Sendable {
    let id: String
    let name: String
    let url: String
    let timeZone: String?
    let updatedAt: Date?
}

struct OverallStatus: Codable, Sendable {
    let indicator: Indicator
    let description: String
}

struct Component: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let status: ComponentStatus
    let position: Int?
    /// `description` is frequently null in the live feed.
    let description: String?
    let showcase: Bool?
    let startDate: String?
    /// `group_id` is null for top-level components.
    let groupId: String?
    let group: Bool?
    let onlyShowIfDegraded: Bool?
    let updatedAt: Date?
}

struct Incident: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let status: String
    let impact: String?
    let shortlink: String?
    let startedAt: Date?
    /// When the incident moved to `monitoring` (a fix was implemented). For an
    /// unresolved incident this is the best signal that visible impact has ended.
    let monitoringAt: Date?
    let resolvedAt: Date?
    let updatedAt: Date?
    /// Components this incident affected (present in `incidents.json`, absent in
    /// `summary.json`'s unresolved list — hence optional).
    let components: [Component]?
    let incidentUpdates: [IncidentUpdate]?
}

/// Wrapper for `{base}/api/v2/incidents.json` (returns the most recent ~50 incidents).
struct IncidentsResponse: Codable, Sendable {
    let incidents: [Incident]
}

struct IncidentUpdate: Codable, Sendable, Identifiable {
    let id: String?
    let body: String
    let status: String?
    let createdAt: Date?

    // Synthesize a stable identity when the API omits an id.
    var resolvedID: String { id ?? "\(createdAt?.timeIntervalSince1970 ?? 0)-\(body.hashValue)" }
}
extension IncidentUpdate {
    var idForList: String { resolvedID }
}

// MARK: - Errors

enum StatuspageError: Error, LocalizedError {
    case invalidURL
    case nonHTTPResponse
    case badStatus(Int)
    case decodingFailed(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid status page URL"
        case .nonHTTPResponse: return "Unexpected (non-HTTP) response"
        case .badStatus(let code): return "Server returned HTTP \(code)"
        case .decodingFailed(let detail): return "Could not read status data (\(detail))"
        case .transport(let detail): return detail
        }
    }
}

// MARK: - Client

/// Stateless async fetcher for `{base}/api/v2/summary.json`.
struct StatuspageClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Build a Statuspage v2 endpoint URL (e.g. `summary.json`, `incidents.json`)
    /// from a base origin like `https://status.claude.com`. Also normalizes a
    /// directly-pasted `…/api/v2/<anything>.json` URL to the requested endpoint.
    static func endpointURL(forBase base: String, endpoint: String) -> URL? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return nil }
        if let range = components.path.range(of: "/api/v2/") {
            // User pasted a full api/v2 URL — swap in the requested endpoint.
            components.path = String(components.path[..<range.lowerBound]) + "/api/v2/" + endpoint
        } else {
            var path = components.path
            if path.hasSuffix("/") { path.removeLast() }
            components.path = path + "/api/v2/" + endpoint
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func summaryURL(forBase base: String) -> URL? {
        endpointURL(forBase: base, endpoint: "summary.json")
    }

    static func incidentsURL(forBase base: String) -> URL? {
        endpointURL(forBase: base, endpoint: "incidents.json")
    }

    /// Parse Statuspage ISO8601 timestamps (with or without fractional seconds).
    /// Builds formatters locally to avoid capturing non-Sendable state in the
    /// `@Sendable` date-decoding closure.
    private static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// Internal (not private) so the test target can decode the same way the app does.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Statuspage uses ISO8601 with fractional seconds (e.g. 2026-05-28T19:34:10.080Z).
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = StatuspageClient.parseDate(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable date: \(raw)")
        }
        return decoder
    }

    /// Shared fetch + decode for any Statuspage v2 JSON endpoint.
    private func fetchDecoded<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StatuspageError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw StatuspageError.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StatuspageError.badStatus(http.statusCode)
        }
        do {
            return try StatuspageClient.makeDecoder().decode(T.self, from: data)
        } catch {
            throw StatuspageError.decodingFailed(error.localizedDescription)
        }
    }

    /// Fetch and decode the summary. Throws `StatuspageError` on any failure.
    func fetchSummary(base: String) async throws -> Summary {
        guard let url = StatuspageClient.summaryURL(forBase: base) else {
            throw StatuspageError.invalidURL
        }
        return try await fetchDecoded(url)
    }

    /// Fetch the recent incident feed (resolved + unresolved) for building history.
    func fetchIncidents(base: String) async throws -> [Incident] {
        guard let url = StatuspageClient.incidentsURL(forBase: base) else {
            throw StatuspageError.invalidURL
        }
        let response: IncidentsResponse = try await fetchDecoded(url)
        return response.incidents
    }
}
