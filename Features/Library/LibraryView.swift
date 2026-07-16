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
    @Query(sort: \QueueItem.position, order: .forward) private var queue: [QueueItem]
    @Environment(ProfileManager.self) private var profiles
    @Environment(\.modelContext) private var context

    // Rows are scoped to the active profile (Phase 6).
    private var scopedItems: [LibraryItem] { items.filter { $0.profileID == profiles.currentProfileID } }
    private var scopedHistory: [HistoryEntry] { history.filter { $0.profileID == profiles.currentProfileID } }
    private var scopedQueue: [QueueItem] { queue.filter { $0.profileID == profiles.currentProfileID } }

    private enum Segment: Hashable {
        case collection(LibraryCollection)
        case history
        case queue
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
                chip(title: "Up Next", systemImage: "text.badge.plus", segment: .queue)
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
            let shown = scopedItems.filter { $0.collectionRaw == collection.rawValue }
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
            if scopedHistory.isEmpty {
                emptyState("History")
            } else {
                grid {
                    ForEach(scopedHistory) { entry in
                        NavigationLink {
                            MediaDetailView(connectorId: entry.extensionID, item: CatalogItem(history: entry))
                        } label: {
                            PosterCard(title: entry.title, artworkURL: entry.artworkURL, progress: entry.progress)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .queue:
            queueList
        }
    }

    /// The reorderable, deletable watch queue (Phase 9).
    @ViewBuilder
    private var queueList: some View {
        if scopedQueue.isEmpty {
            emptyState("Up Next")
        } else {
            List {
                ForEach(scopedQueue) { entry in
                    NavigationLink {
                        MediaDetailView(connectorId: entry.extensionID, item: CatalogItem(queue: entry))
                    } label: {
                        HStack(spacing: 12) {
                            PosterCard(title: entry.title, artworkURL: entry.artworkURL)
                                .frame(width: 60)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.subheadline).lineLimit(2)
                                if let subtitle = entry.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let queue = scopedQueue
                    let store = WatchQueue(context: context, profileID: profiles.currentProfileID)
                    for index in offsets { store.remove(queue[index]) }
                }
                .onMove { source, destination in
                    WatchQueue(context: context, profileID: profiles.currentProfileID).move(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .toolbar { EditButton() }
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
