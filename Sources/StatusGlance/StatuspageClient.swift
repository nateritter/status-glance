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
    let updatedAt: Date?
    let incidentUpdates: [IncidentUpdate]?
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

    /// Build the summary endpoint from a base origin like `https://status.claude.com`.
    static func summaryURL(forBase base: String) -> URL? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return nil }
        // If the user pasted the full summary URL, accept it as-is.
        if components.path.hasSuffix("/api/v2/summary.json") {
            return components.url
        }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/api/v2/summary.json"
        components.query = nil
        components.fragment = nil
        return components.url
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

    private static func makeDecoder() -> JSONDecoder {
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

    /// Fetch and decode the summary. Throws `StatuspageError` on any failure.
    func fetchSummary(base: String) async throws -> Summary {
        guard let url = StatuspageClient.summaryURL(forBase: base) else {
            throw StatuspageError.invalidURL
        }
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
            return try StatuspageClient.makeDecoder().decode(Summary.self, from: data)
        } catch {
            throw StatuspageError.decodingFailed(error.localizedDescription)
        }
    }
}
