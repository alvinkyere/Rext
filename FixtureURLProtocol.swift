import Foundation

// ---------------------------------------------------------------------------
// FixtureURLProtocol.swift
//
// Offline HTTP stubbing for tests. Intercepts URLSession requests and serves
// canned responses. Completely deterministic - no network, no flakiness.
// ---------------------------------------------------------------------------

public struct FixtureResponse: Sendable {
    public let status: Int
    public let body: String
    public let headers: [String: String]
    public let delayMs: Int?
    public let redirectTo: String?
    
    public init(status: Int, body: String, headers: [String: String] = [:], delayMs: Int? = nil, redirectTo: String? = nil) {
        self.status = status
        self.body = body
        self.headers = headers
        self.delayMs = delayMs
        self.redirectTo = redirectTo
    }
}

public final class FixtureURLProtocol: URLProtocol {
    private nonisolated(unsafe) static var fixtures: [String: FixtureResponse] = [:]
    private nonisolated(unsafe) static let lock = NSLock()
    
    public static func register(url: String, response: FixtureResponse) {
        lock.lock()
        defer { lock.unlock() }
        fixtures[url] = response
    }
    
    public static func clearFixtures() {
        lock.lock()
        defer { lock.unlock() }
        fixtures.removeAll()
    }
    
    public static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        return config
    }
    
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        lock.lock()
        defer { lock.unlock() }
        return fixtures[url] != nil
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        guard let url = request.url?.absoluteString else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        
        Self.lock.lock()
        guard let fixture = Self.fixtures[url] else {
            Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        Self.lock.unlock()
        
        let delaySeconds = Double(fixture.delayMs ?? 0) / 1000.0
        
        DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
            guard let self else { return }
            
            if let redirectURL = fixture.redirectTo, let target = URL(string: redirectURL) {
                let response = HTTPURLResponse(
                    url: self.request.url!,
                    statusCode: fixture.status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Location": redirectURL]
                )!
                self.client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocolDidFinishLoading(self)
                return
            }
            
            var headers = fixture.headers
            headers["Content-Type"] = headers["Content-Type"] ?? "application/json"
            
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: fixture.status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            
            if let data = fixture.body.data(using: .utf8) {
                self.client?.urlProtocol(self, didLoad: data)
            }
            
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    public override func stopLoading() {}
}
