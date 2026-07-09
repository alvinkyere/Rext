import Foundation

// ---------------------------------------------------------------------------
// PodcastRSSFixtures.swift
//
// Registers all fixtures for the podcast-rss connector. Tests call this once
// in setUp to get deterministic, offline responses.
// ---------------------------------------------------------------------------

public enum PodcastRSSFixtures {
    private static let baseURL = "https://api.example-podcasts.com"
    
    public static func registerAll() {
        FixtureURLProtocol.clearFixtures()
        
        // Search: history (happy path)
        FixtureURLProtocol.register(
            url: "\(baseURL)/search?q=history&page=1",
            response: FixtureResponse(
                status: 200,
                body: """
                {
                  "results": [
                    {
                      "id": "show-42",
                      "title": "The History of Everything",
                      "author": "Jane Doe",
                      "artwork": "https://cdn.example-podcasts.com/art/show-42.jpg",
                      "episodeCount": 213
                    },
                    {
                      "id": "show-91",
                      "title": "Ancient Histories",
                      "author": "John Roe",
                      "artwork": "https://cdn.example-podcasts.com/art/show-91.jpg",
                      "episodeCount": 58
                    }
                  ]
                }
                """
            )
        )
        
        // Show: show-42 (happy path)
        FixtureURLProtocol.register(
            url: "\(baseURL)/show/show-42",
            response: FixtureResponse(
                status: 200,
                body: """
                {
                  "id": "show-42",
                  "title": "The History of Everything",
                  "author": "Jane Doe",
                  "artwork": "https://cdn.example-podcasts.com/art/show-42.jpg",
                  "description": "A sweeping tour from the big bang to last Tuesday.",
                  "categories": ["History", "Education"],
                  "firstAired": "2019-03-01",
                  "episodes": [
                    { "id": "ep-1001", "title": "In the Beginning", "number": 1, "durationSec": 2412 },
                    { "id": "ep-1002", "title": "Stars and Dust", "number": 2, "durationSec": 2733 }
                  ]
                }
                """
            )
        )
        
        // Episode stream: ep-1001 (happy path)
        FixtureURLProtocol.register(
            url: "\(baseURL)/episode/ep-1001/stream",
            response: FixtureResponse(
                status: 200,
                body: """
                {
                  "streamUrl": "https://cdn.example-podcasts.com/audio/ep-1001.mp3",
                  "bitrate": 128
                }
                """
            )
        )
        
        // Show: does-not-exist (404 test)
        FixtureURLProtocol.register(
            url: "\(baseURL)/show/does-not-exist",
            response: FixtureResponse(
                status: 404,
                body: "not found"
            )
        )
        
        // Search: broken (non-JSON test)
        FixtureURLProtocol.register(
            url: "\(baseURL)/search?q=broken&page=1",
            response: FixtureResponse(
                status: 200,
                body: "<html>not json</html>"
            )
        )
        
        // Search: slow (timeout test - 20s delay exceeds 10s request timeout)
        FixtureURLProtocol.register(
            url: "\(baseURL)/search?q=slow&page=1",
            response: FixtureResponse(
                status: 200,
                body: """
                { "results": [] }
                """,
                delayMs: 20000
            )
        )
        
        // Redirect test (redirect to disallowed host)
        FixtureURLProtocol.register(
            url: "\(baseURL)/redirect",
            response: FixtureResponse(
                status: 302,
                body: "",
                redirectTo: "https://evil.example.com/exfiltrate"
            )
        )
    }
}
