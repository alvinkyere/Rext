import Foundation

// ---------------------------------------------------------------------------
// YouTubeProvider.swift  (Rext — YouTube as a native API provider)
//
// The first native provider: search + metadata via the official YouTube Data API
// v3, normalized into Rext's canonical models, with playback through the official
// embedded player (see YouTubeEmbedPlayerView). No scraping, no stream extraction
// — a legitimate, supported integration that proves the provider-type system.
// The pure `YouTubeMapper` (DTOs → canonical models) is unit-tested offline.
// ---------------------------------------------------------------------------

// MARK: - API DTOs

struct YTThumbnail: Decodable { let url: String }

struct YTThumbnails: Decodable {
    let high: YTThumbnail?
    let medium: YTThumbnail?
    let `default`: YTThumbnail?
    var best: String? { high?.url ?? medium?.url ?? `default`?.url }
}

struct YTSnippet: Decodable {
    let title: String
    let description: String?
    let channelTitle: String?
    let thumbnails: YTThumbnails?
    let publishedAt: String?
    let tags: [String]?
}

struct YTSearchID: Decodable { let videoId: String? }

struct YTSearchItem: Decodable {
    let id: YTSearchID
    let snippet: YTSnippet
}

struct YTSearchResponse: Decodable { let items: [YTSearchItem] }

struct YTStatistics: Decodable { let viewCount: String? }
struct YTContentDetails: Decodable { let duration: String? }

struct YTVideo: Decodable {
    let id: String
    let snippet: YTSnippet
    let statistics: YTStatistics?
    let contentDetails: YTContentDetails?
}

struct YTVideoListResponse: Decodable { let items: [YTVideo] }

// MARK: - Pure mapping (canonical models)

enum YouTubeMapper {
    static func catalogItems(_ response: YTSearchResponse) -> [CatalogItem] {
        response.items.compactMap { item in
            guard let videoID = item.id.videoId else { return nil }
            return CatalogItem(
                id: videoID,
                title: item.snippet.title,
                subtitle: item.snippet.channelTitle,
                artworkUrl: item.snippet.thumbnails?.best,
                kind: .video,
                metadata: nil,
                canonical: canonical(from: item.snippet)
            )
        }
    }

    static func details(_ video: YTVideo) -> MediaDetails {
        var bag: [String: JSONScalar] = [:]
        if let overview = video.snippet.description { bag["overview"] = .string(overview) }
        if let views = video.statistics?.viewCount { bag["viewCount"] = .string(views) }
        if let duration = video.contentDetails?.duration { bag["duration"] = .string(duration) }
        return MediaDetails(
            id: video.id,
            title: video.snippet.title,
            subtitle: video.snippet.channelTitle,
            artworkUrl: video.snippet.thumbnails?.best,
            backdropUrl: video.snippet.thumbnails?.best,
            kind: .video,
            metadata: bag.isEmpty ? nil : bag,
            episodes: nil,
            canonical: canonical(from: video.snippet)
        )
    }

    private static func canonical(from snippet: YTSnippet) -> ContentMetadata {
        ContentMetadata(
            topics: snippet.tags ?? [],
            creators: [snippet.channelTitle].compactMap { $0 },
            releaseDate: snippet.publishedAt
        )
    }
}

// MARK: - Provider

struct YouTubeProvider: MediaProvider {
    static let providerID = "com.runtime.youtube"

    let id = YouTubeProvider.providerID
    let displayName = "YouTube"
    let kind: MediaProviderKind = .api

    private let apiKey: String
    private let session: URLSession
    private let base = "https://www.googleapis.com/youtube/v3"
    private let logger = RuntimeLogger(extensionID: YouTubeProvider.providerID)

    init(apiKey: String = YouTubeConfig.apiKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func search(query: String) async throws -> [CatalogItem] {
        logger.network("GET search q=\(query)")
        var components = URLComponents(string: "\(base)/search")!
        components.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            // Only surface content Rext can actually play inline: embeddable and
            // syndicated (playable off youtube.com). Non-embeddable live streams
            // and owner-restricted videos are filtered out entirely.
            .init(name: "videoEmbeddable", value: "true"),
            .init(name: "videoSyndicated", value: "true"),
            .init(name: "maxResults", value: "25"),
            .init(name: "q", value: query),
            .init(name: "key", value: apiKey),
        ]
        let response: YTSearchResponse = try await get(components.url!)
        return YouTubeMapper.catalogItems(response)
    }

    func details(itemId: String) async throws -> MediaDetails {
        var components = URLComponents(string: "\(base)/videos")!
        components.queryItems = [
            .init(name: "part", value: "snippet,statistics,contentDetails"),
            .init(name: "id", value: itemId),
            .init(name: "key", value: apiKey),
        ]
        let response: YTVideoListResponse = try await get(components.url!)
        guard let video = response.items.first else {
            throw ConnectorError(.notFound, "Video not found")
        }
        return YouTubeMapper.details(video)
    }

    func streams(itemId: String, episodeId: String?) async throws -> [StreamSource] {
        // Playback uses YouTube's official embedded player, not extracted streams.
        [StreamSource(
            id: "yt-embed-\(itemId)",
            url: "https://www.youtube.com/embed/\(itemId)?playsinline=1&autoplay=1",
            quality: "YouTube",
            format: "youtube",
            metadata: nil
        )]
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError(.unknown, "No response from YouTube")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            logger.error("YouTube API error \(http.statusCode)", metadata: ["body": body])
            throw ConnectorError(http.statusCode == 404 ? .notFound : .unknown, "YouTube API error \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Malformed YouTube response")
            throw ConnectorError(.invalidResponse, "Malformed YouTube response")
        }
    }
}
