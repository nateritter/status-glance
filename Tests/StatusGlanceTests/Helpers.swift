import Foundation
import XCTest
@testable import StatusGlance

// MARK: - Fixture loading (real captured status.claude.com payloads, 2026-06-25)

enum Fixture {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            fatalError("missing fixture \(name).json — check Package.swift resources")
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }
    static func summary() throws -> Summary {
        try StatuspageClient.makeDecoder().decode(Summary.self, from: data("summary"))
    }
    static func incidents() throws -> [Incident] {
        try StatuspageClient.makeDecoder().decode(IncidentsResponse.self, from: data("incidents")).incidents
    }
}

// MARK: - Model builders (memberwise; only the fields a test cares about)

func makeComponent(id: String = "c1",
                   name: String = "Comp",
                   status: ComponentStatus = .operational,
                   groupId: String? = nil,
                   group: Bool? = false,
                   onlyShowIfDegraded: Bool? = false) -> Component {
    Component(id: id, name: name, status: status, position: 0, description: nil,
              showcase: true, startDate: nil, groupId: groupId, group: group,
              onlyShowIfDegraded: onlyShowIfDegraded, updatedAt: nil)
}

func makeIncident(id: String = "i1",
                  name: String = "Inc",
                  status: String = "resolved",
                  impact: String? = "major",
                  startedAt: Date? = nil,
                  monitoringAt: Date? = nil,
                  resolvedAt: Date? = nil,
                  updatedAt: Date? = nil,
                  components: [Component]? = nil) -> Incident {
    Incident(id: id, name: name, status: status, impact: impact, shortlink: nil,
             startedAt: startedAt, monitoringAt: monitoringAt, resolvedAt: resolvedAt,
             updatedAt: updatedAt, components: components, incidentUpdates: nil)
}

func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

// MARK: - URLProtocol mock (no network in tests)

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func mockSession(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
    MockURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

func okResponse(_ url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
}
