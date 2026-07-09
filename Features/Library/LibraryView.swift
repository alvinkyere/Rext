import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// LibraryView.swift  (Rext Phase 2 — Priority 5: Library)
//
// A centralized place for the user's media across every installed extension.
// Collections (Watching/Reading/Listening/Completed/Favorites) plus History,
// selectable via chips, shown as a poster grid. Backed by SwiftData.
// ---------------------------------------------------------------------------

struct LibraryView: View {
    @Query(sort: \LibraryItem.addedAt, order: .reverse) private var items: [LibraryItem]
    @Query(sort: \HistoryEntry.lastAccessed, order: .reverse) private var history: [HistoryEntry]

    private enum Segment: Hashable {
        case collection(LibraryCollection)
        case history
    }

    @State private var selection: Segment = .collection(.favorites)

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chips
                content
            }
            .navigationTitle("Library")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryCollection.allCases, id: \.self) { collection in
                    chip(title: collection.title, systemImage: collection.systemImage, segment: .collection(collection))
                }
                chip(title: "History", systemImage: "clock", segment: .history)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, systemImage: String, segment: Segment) -> some View {
        let isSelected = selection == segment
        return Button {
            selection = segment
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .collection(let collection):
            let shown = items.filter { $0.collectionRaw == collection.rawValue }
            if shown.isEmpty {
                emptyState(collection.title)
            } else {
                grid {
                    ForEach(shown) { item in
                        NavigationLink {
                            MediaDetailView(connectorId: item.extensionID, item: CatalogItem(library: item))
                        } label: {
                            PosterCard(title: item.title, artworkURL: item.artworkURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .history:
            if history.isEmpty {
                emptyState("History")
            } else {
                grid {
                    ForEach(history) { entry in
                        NavigationLink {
                            MediaDetailView(connectorId: entry.extensionID, item: CatalogItem(history: entry))
                        } label: {
                            PosterCard(title: entry.title, artworkURL: entry.artworkURL, progress: entry.progress)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) { content() }
                .padding()
        }
    }

    private func emptyState(_ name: String) -> some View {
        ContentUnavailableView(
            "Nothing in \(name)",
            systemImage: "books.vertical",
            description: Text("Items you save will appear here.")
        )
        .frame(maxHeight: .infinity)
    }
}
