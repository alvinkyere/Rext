import Foundation

// ---------------------------------------------------------------------------
// PlexAPI.swift  (Rext — Plex provider)
//
// Networking only — builds authenticated requests and returns decoded DTOs. No
// mapping, no UI. Covers the plex.tv account API (PIN auth, resource discovery)
// and the Plex Media Server API (sections, items, metadata, search). URLSession
// is injected so tests can stub responses.
// ---------------------------------------------------------------------------

struct PlexAPI: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Account API (plex.tv)

    func createPin() async throws -> PlexPin {
        var components = URLComponents(url: PlexConfig.accountAPI.appendingPathComponent("pins"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "strong", value: "true")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        return try await send(request, token: nil)
    }

    func checkPin(id: Int) async throws -> PlexPin {
        let url = PlexConfig.accountAPI.appendingPathComponent("pins").appendingPathComponent(String(id))
        return try await send(URLRequest(url: url), token: nil)
    }

    func resources(token: String) async throws -> [PlexResource] {
        var components = URLComponents(url: PlexConfig.accountAPI.appendingPathComponent("resources"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
        ]
        return try await send(URLRequest(url: components.url!), token: token)
    }

    func account(token: String) async throws -> PlexAccount {
        try await send(URLRequest(url: PlexConfig.accountAPI.appendingPathComponent("user")), token: token)
    }

    // MARK: - Reachability

    /// Whether a specific server connection actually responds (short timeout).
    /// Used to pick a reachable connection among local / remote / relay.
    func isReachable(base: URL, token: String, timeout: TimeInterval = 3) async -> Bool {
        var request = serverRequest(base: base, path: "/identity")
        request.timeoutInterval = timeout
        for (key, value) in PlexConfig.headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<400).contains(code)
        } catch {
            return false
        }
    }

    // MARK: - Server API

    func sections(base: URL, token: String) async throws -> [PlexDirectory] {
        let env: PlexEnvelope<PlexSectionsContainer> = try await send(serverRequest(base: base, path: "/library/sections"), token: token)
        return env.mediaContainer.directory ?? []
    }

    func items(base: URL, token: String, sectionKey: String, start: Int = 0, size: Int = 50) async throws -> PlexMetadataContainer {
        var components = serverComponents(base: base, path: "/library/sections/\(sectionKey)/all")
        components.queryItems = [
            URLQueryItem(name: "X-Plex-Container-Start", value: String(start)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(size)),
        ]
        let env: PlexEnvelope<PlexMetadataContainer> = try await send(URLRequest(url: components.url!), token: token)
        return env.mediaContainer
    }

    func metadata(base: URL, token: String, ratingKey: String) async throws -> PlexMetadataContainer {
        let env: PlexEnvelope<PlexMetadataContainer> = try await send(serverRequest(base: base, path: "/library/metadata/\(ratingKey)"), token: token)
        return env.mediaContainer
    }

    func search(base: URL, token: String, query: String, limit: Int = 30) async throws -> [PlexMetadata] {
        var components = serverComponents(base: base, path: "/hubs/search")
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let env: PlexEnvelope<PlexHubContainer> = try await send(URLRequest(url: components.url!), token: token)
        var results: [PlexMetadata] = []
        var seen = Set<String>()
        for hub in env.mediaContainer.hub ?? [] {
            for item in hub.metadata ?? [] where seen.insert(item.ratingKey).inserted {
                results.append(item)
            }
        }
        return results
    }

    // MARK: - Request plumbing

    private func serverComponents(base: URL, path: String) -> URLComponents {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = path
        return components
    }

    private func serverRequest(base: URL, path: String) -> URLRequest {
        URLRequest(url: serverComponents(base: base, path: path).url ?? base)
    }

    private func send<T: Decodable>(_ request: URLRequest, token: String?) async throws -> T {
        var request = request
        for (key, value) in PlexConfig.headers { request.setValue(value, forHTTPHeaderField: key) }
        if let token { request.setValue(token, forHTTPHeaderField: "X-Plex-Token") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError(.unknown, "No response from Plex")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ConnectorError(http.statusCode == 404 ? .notFound : .unknown, "Plex error \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ConnectorError(.invalidResponse, "Malformed Plex response")
        }
    }
}
