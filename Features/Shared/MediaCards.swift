import SwiftUI

// ---------------------------------------------------------------------------
// MediaCards.swift  (Rext Phase 2 — shared UI)
//
// Reusable poster card + conveniences to reconstruct a CatalogItem from stored
// library/history rows, so Home and Library can deep-link into Media Details
// regardless of which extension provided the content.
// ---------------------------------------------------------------------------

extension CatalogItem {
    init(library: LibraryItem) {
        self.init(id: library.itemID, title: library.title, subtitle: library.subtitle,
                  artworkUrl: library.artworkURL, kind: library.contentKind, metadata: nil,
                  canonical: library.genres.isEmpty ? nil : ContentMetadata(genres: library.genres))
    }

    init(history: HistoryEntry) {
        self.init(id: history.itemID, title: history.title, subtitle: nil,
                  artworkUrl: history.artworkURL, kind: history.contentKind, metadata: nil)
    }

    init(trending: TrendingItem) {
        self.init(id: trending.itemID, title: trending.title, subtitle: nil,
                  artworkUrl: nil, kind: trending.kind, metadata: nil)
    }

    init(queue: QueueItem) {
        self.init(id: queue.itemID, title: queue.title, subtitle: queue.subtitle,
                  artworkUrl: queue.artworkURL, kind: queue.contentKind, metadata: nil)
    }
}

enum PosterSize {
    case regular, large
    var width: CGFloat { self == .large ? 150 : 120 }
    var height: CGFloat { self == .large ? 212 : 170 }
}

struct PosterCard: View {
    let title: String
    let artworkURL: String?
    var subtitle: String?
    var progress: Double?
    var size: PosterSize = .regular

    init(title: String, artworkURL: String?, subtitle: String? = nil, progress: Double? = nil, size: PosterSize = .regular) {
        self.title = title
        self.artworkURL = artworkURL
        self.subtitle = subtitle
        self.progress = progress
        self.size = size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                Artwork(url: artworkURL, title: title)
                    .frame(width: size.width, height: size.height)

                if let progress, progress > 0 {
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                        ProgressView(value: progress)
                            .tint(.white)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: size.width, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: size.width, alignment: .leading)
            }
        }
    }
}

struct CatalogItemRow: View {
    let item: CatalogItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.artworkUrl.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                default: Rectangle().fill(Color.gray.opacity(0.25))
                }
            }
            .frame(width: 50, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline).lineLimit(2)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(item.kind.rawValue.capitalized).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}
