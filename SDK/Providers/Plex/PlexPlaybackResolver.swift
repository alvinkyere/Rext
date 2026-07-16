import Foundation

// ---------------------------------------------------------------------------
// PlexPlaybackResolver.swift  (Rext — Plex provider)
//
// Resolves a Plex metadata node into playable StreamSources for AVPlayer. V1
// uses direct play: the Part `key` yields a token-authenticated file URL the
// system player streams natively. Structured so a transcode HLS source
// (`/video/:/transcode/universal/start.m3u8`) can be appended later without
// changing any caller.
// ---------------------------------------------------------------------------

enum PlexPlaybackResolver {
    static func streams(from m: PlexMetadata, base: URL, token: String) -> [StreamSource] {
        var sources: [StreamSource] = []
        for media in m.media ?? [] {
            for part in media.part ?? [] {
                guard let key = part.key, let url = directURL(base: base, partKey: key, token: token) else { continue }
                sources.append(StreamSource(
                    id: "plex-\(part.id ?? 0)",
                    url: url,
                    quality: media.videoResolution.map { $0.hasSuffix("p") ? $0 : "\($0)p" } ?? "Original",
                    format: part.container ?? media.container,
                    metadata: nil
                ))
            }
        }
        return sources
    }

    static func directURL(base: URL, partKey: String, token: String) -> String? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.path = partKey
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components.url?.absoluteString
    }
}
