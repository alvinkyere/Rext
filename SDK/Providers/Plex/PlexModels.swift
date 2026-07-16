import Foundation

// ---------------------------------------------------------------------------
// PlexModels.swift  (Rext — Plex provider)
//
// Codable DTOs for the subset of the Plex account API (plex.tv) and Plex Media
// Server API that Rext consumes. These never escape the provider layer — the
// mapper turns them into canonical Rext models. Plex returns JSON when the
// request sends `Accept: application/json`; server payloads are wrapped in a
// top-level `MediaContainer`.
// ---------------------------------------------------------------------------

// MARK: - Account API (plex.tv)

nonisolated struct PlexPin: Codable, Sendable {
    let id: Int
    let code: String
    var authToken: String?
}

nonisolated struct PlexAccount: Codable, Sendable {
    let username: String?
    let title: String?
    let email: String?
}

nonisolated struct PlexResource: Codable, Sendable {
    let name: String
    let clientIdentifier: String
    let product: String?
    let provides: String?          // e.g. "server"
    let accessToken: String?
    let productVersion: String?
    let owned: Bool?
    let connections: [PlexConnection]?
}

nonisolated struct PlexConnection: Codable, Sendable {
    let uri: String
    let address: String?
    let port: Int?
    let local: Bool?
    let relay: Bool?
    let `protocol`: String?
}

// MARK: - Server API envelope

nonisolated struct PlexEnvelope<Container: Codable & Sendable>: Codable, Sendable {
    let mediaContainer: Container
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

nonisolated struct PlexSectionsContainer: Codable, Sendable {
    let directory: [PlexDirectory]?
    enum CodingKeys: String, CodingKey { case directory = "Directory" }
}

nonisolated struct PlexDirectory: Codable, Sendable {
    let key: String
    let title: String
    let type: String              // movie, show, artist, photo
    let uuid: String?
}

nonisolated struct PlexMetadataContainer: Codable, Sendable {
    let size: Int?
    let totalSize: Int?
    let metadata: [PlexMetadata]?
    enum CodingKeys: String, CodingKey {
        case size, totalSize
        case metadata = "Metadata"
    }
}

nonisolated struct PlexHubContainer: Codable, Sendable {
    let hub: [PlexHub]?
    enum CodingKeys: String, CodingKey { case hub = "Hub" }
}

nonisolated struct PlexHub: Codable, Sendable {
    let type: String?
    let title: String?
    let metadata: [PlexMetadata]?
    enum CodingKeys: String, CodingKey {
        case type, title
        case metadata = "Metadata"
    }
}

// MARK: - Metadata (movie / show / season / episode / track …)

nonisolated struct PlexMetadata: Codable, Sendable {
    let ratingKey: String
    let key: String?
    let type: String
    let title: String
    let grandparentTitle: String?
    let parentTitle: String?
    let summary: String?
    let year: Int?
    let thumb: String?
    let art: String?
    let duration: Int?            // milliseconds
    let index: Int?              // episode / track number
    let parentIndex: Int?        // season number
    let contentRating: String?
    let rating: Double?
    let viewOffset: Int?         // resume position (ms)
    let originallyAvailableAt: String?
    let genre: [PlexTag]?
    let director: [PlexTag]?
    let role: [PlexTag]?
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, type, title, grandparentTitle, parentTitle, summary
        case year, thumb, art, duration, index, parentIndex, contentRating, rating
        case viewOffset, originallyAvailableAt
        case genre = "Genre"
        case director = "Director"
        case role = "Role"
        case media = "Media"
    }
}

nonisolated struct PlexTag: Codable, Sendable {
    let tag: String?
}

nonisolated struct PlexMedia: Codable, Sendable {
    let id: Int?
    let videoResolution: String?
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let part: [PlexPart]?
    enum CodingKeys: String, CodingKey {
        case id, videoResolution, container, videoCodec, audioCodec
        case part = "Part"
    }
}

nonisolated struct PlexPart: Codable, Sendable {
    let id: Int?
    let key: String?
    let container: String?
    let file: String?
    let size: Int?
}
