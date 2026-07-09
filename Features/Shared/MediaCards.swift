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
}

struct PosterCard: View {
    let title: String
    let artworkURL: String?
    var progress: Double?

    init(title: String, artworkURL: String?, progress: Double? = nil) {
        self.title = title
        self.artworkURL = artworkURL
        self.progress = progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: artworkURL.flatMap(URL.init)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        Rectangle().fill(Color.gray.opacity(0.25)).overlay { ProgressView() }
                    default:
                        Rectangle().fill(Color.gray.opacity(0.25))
                            .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                    }
                }
                .frame(width: 120, height: 170)
                .clipped()

                if let progress, progress > 0 {
                    ProgressView(value: progress)
                        .tint(.blue)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: 120, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(title)
                .font(.caption)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
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
