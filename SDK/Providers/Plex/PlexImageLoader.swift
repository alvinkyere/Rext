import Foundation

// ---------------------------------------------------------------------------
// PlexImageLoader.swift  (Rext — reusable artwork pipeline)
//
// Builds self-authenticating artwork URLs for Plex media so the app's existing
// AsyncImage (backed by the shared URLCache configured at launch) renders and
// caches them with no provider-specific view code. Future providers reuse the
// same pattern: produce a plain https URL, let the shared URLCache do mem/disk
// caching. A photo-transcode variant provides server-side sizing when wanted.
// ---------------------------------------------------------------------------

enum PlexImageLoader {
    /// A direct, token-authenticated artwork URL (`{base}{path}?X-Plex-Token=…`).
    static func artworkURL(base: URL, path: String?, token: String) -> String? {
        guard let path, !path.isEmpty else { return nil }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        // `path` is a server-relative resource like "/library/metadata/123/thumb/167…".
        components.path = path
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components.url?.absoluteString
    }

    /// A server-transcoded, sized artwork URL — preferred for grids/prefetching.
    static func transcodedURL(base: URL, path: String?, token: String, width: Int, height: Int) -> String? {
        guard let path, !path.isEmpty else { return nil }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/photo/:/transcode"
        components.queryItems = [
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "1"),
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "X-Plex-Token", value: token),
        ]
        return components.url?.absoluteString
    }
}
