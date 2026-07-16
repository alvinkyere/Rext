import Foundation

// ---------------------------------------------------------------------------
// ProviderCatalog.swift  (Rext Roadmap Phase 8 — Provider Ecosystem)
//
// A curated directory of the media providers Rext is designed around, grouped by
// category. Every provider is a Rext extension implementing the same protocol and
// feeding the Universal Content Graph; this catalog is the discovery surface that
// makes the ecosystem visible. Provider *availability* is resolved from live
// runtime state (installed + repository-available extensions), so a provider
// moves from "Coming Soon" → "Available" → "Installed" purely from data as
// packages ship — no code change to the UI.
// ---------------------------------------------------------------------------

public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case youTube, plex, jellyfin, rss, podcasts, audiobooks, books, localFiles
}

/// Where a provider stands for this user right now.
public enum ProviderStatus: String, Sendable, Equatable {
    case installed     // a matching extension is installed
    case available     // installable from an enabled repository now
    case comingSoon    // architected for, not yet shipped as an extension
}

public struct ProviderDescriptor: Identifiable, Sendable, Equatable {
    public let kind: ProviderKind
    public let name: String
    public let summary: String
    public let iconSystemName: String
    public let colorHex: String
    public let category: ExtensionCategory
    /// The official extension id that fulfils this provider, when one exists.
    public let extensionID: String?
    public internal(set) var status: ProviderStatus

    public var id: String { kind.rawValue }
}

public enum ProviderCatalog {
    /// The static, ordered catalog. `status` here is the baseline; call
    /// `resolved(...)` to reflect the user's installed / available extensions.
    public static let all: [ProviderDescriptor] = [
        ProviderDescriptor(kind: .youTube, name: "YouTube", summary: "Videos, channels, and playlists.",
                           iconSystemName: "play.rectangle.fill", colorHex: "#FF0000", category: .media,
                           extensionID: "com.runtime.youtube", status: .comingSoon),
        ProviderDescriptor(kind: .podcasts, name: "Podcasts", summary: "Browse and stream podcast shows.",
                           iconSystemName: "mic.fill", colorHex: "#8B5CF6", category: .media,
                           extensionID: "com.runtime.podcast-rss", status: .comingSoon),
        ProviderDescriptor(kind: .rss, name: "RSS Feeds", summary: "Any RSS or Atom feed as a source.",
                           iconSystemName: "dot.radiowaves.up.forward", colorHex: "#F59E0B", category: .news,
                           extensionID: "com.runtime.rss", status: .comingSoon),
        ProviderDescriptor(kind: .plex, name: "Plex", summary: "Your personal Plex media server.",
                           iconSystemName: "play.tv.fill", colorHex: "#E5A00D", category: .media,
                           extensionID: "com.runtime.plex", status: .comingSoon),
        ProviderDescriptor(kind: .jellyfin, name: "Jellyfin", summary: "Your self-hosted Jellyfin library.",
                           iconSystemName: "film.stack.fill", colorHex: "#00A4DC", category: .media,
                           extensionID: "com.runtime.jellyfin", status: .comingSoon),
        ProviderDescriptor(kind: .audiobooks, name: "Audiobooks", summary: "Public-domain and hosted audiobooks.",
                           iconSystemName: "headphones", colorHex: "#10B981", category: .books,
                           extensionID: "com.runtime.audiobooks", status: .comingSoon),
        ProviderDescriptor(kind: .books, name: "Books", summary: "Read from open book libraries.",
                           iconSystemName: "books.vertical.fill", colorHex: "#EC4899", category: .books,
                           extensionID: "com.runtime.books", status: .comingSoon),
        ProviderDescriptor(kind: .localFiles, name: "Local Files", summary: "Media stored on this device.",
                           iconSystemName: "folder.fill", colorHex: "#8E8E93", category: .utility,
                           extensionID: "com.runtime.local-files", status: .comingSoon),
    ]

    /// Resolve each provider's status against the runtime state.
    public static func resolved(installedIDs: Set<String>, availableIDs: Set<String>) -> [ProviderDescriptor] {
        all.map { descriptor in
            var resolved = descriptor
            if let id = descriptor.extensionID, installedIDs.contains(id) {
                resolved.status = .installed
            } else if let id = descriptor.extensionID, availableIDs.contains(id) {
                resolved.status = .available
            } else {
                resolved.status = .comingSoon
            }
            return resolved
        }
    }

    /// Providers grouped by category, in a stable display order.
    public static func grouped(_ providers: [ProviderDescriptor]) -> [(category: ExtensionCategory, providers: [ProviderDescriptor])] {
        let order = ExtensionCategory.allCases
        return order.compactMap { category in
            let matches = providers.filter { $0.category == category }
            return matches.isEmpty ? nil : (category, matches)
        }
    }
}

public extension ExtensionCategory {
    /// A human title for section headers.
    var displayTitle: String {
        switch self {
        case .media: return "Media"
        case .music: return "Music"
        case .books: return "Books & Audiobooks"
        case .news: return "News & Feeds"
        case .utility: return "Utilities"
        case .developer: return "Developer"
        case .other: return "Other"
        }
    }
}
