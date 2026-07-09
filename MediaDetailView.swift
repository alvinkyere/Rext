import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// MediaDetailView.swift
//
// Shows full details for a selected media item.
// For series, displays episodes; for movies, shows streams directly.
// ---------------------------------------------------------------------------

struct MediaDetailView: View {
    let connectorId: String
    let item: CatalogItem
    
    @State private var details: MediaDetails?
    @State private var isLoading: Bool = true
    @State private var error: ConnectorError?
    @State private var selectedItem: CatalogItem?
    @State private var showingStreams: Bool = false
    @Environment(\.modelContext) private var context
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading details...")
                    .padding()
            } else if let error = error {
                errorView(error)
            } else if let details = details {
                detailsContent(details)
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { saveMenu }
        }
        .task {
            await loadDetails()
        }
        .sheet(isPresented: $showingStreams) {
            if let selectedItem = selectedItem {
                StreamsView(
                    connectorId: connectorId,
                    item: selectedItem,
                    title: selectedItem.title
                )
            }
        }
    }
    
    private func detailsContent(_ details: MediaDetails) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hero image
            if let backdropUrl = details.backdropUrl, let url = URL(string: backdropUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay { ProgressView() }
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
            
            // Title & metadata
            VStack(alignment: .leading, spacing: 8) {
                Text(details.title)
                    .font(.title)
                    .fontWeight(.bold)
                
                if let subtitle = details.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 12) {
                    if let year = details.metadata?["year"], case .int(let yearValue) = year {
                        Label(String(yearValue), systemImage: "calendar")
                    }
                    if let rating = details.metadata?["rating"], case .string(let ratingValue) = rating {
                        Label(ratingValue, systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
            }
            .padding(.horizontal)

            canonicalSection(details.resolvedMetadata)
            
            // Watch button (for movies)
            if details.kind == .movie {
                Button {
                    selectedItem = item
                    showingStreams = true
                } label: {
                    Label("Watch Now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
            
            // Overview
            if let overview = details.metadata?["overview"], case .string(let overviewValue) = overview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text(overviewValue)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            
            // Cast
            if let cast = details.metadata?["cast"], case .string(let castValue) = cast {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cast")
                        .font(.headline)
                    Text(castValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            
            // Episodes (for series)
            if let episodes = details.episodes, !episodes.isEmpty {
                episodesList(episodes)
            }
        }
        .padding(.vertical)
    }
    
    private func episodesList(_ episodes: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.headline)
                .padding(.horizontal)
            
            // Group by season
            let seasons = Dictionary(grouping: episodes) { episode -> Int in
                if let season = episode.metadata?["season"], case .int(let seasonValue) = season {
                    return seasonValue
                }
                return 1
            }
            .sorted { $0.key < $1.key }
            
            ForEach(seasons, id: \.key) { season, seasonEpisodes in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Season \(season)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                    
                    let sortedEpisodes = seasonEpisodes.sorted { ep1, ep2 in
                        let num1 = ep1.metadata?["episode"]
                        let num2 = ep2.metadata?["episode"]
                        if case .int(let n1) = num1, case .int(let n2) = num2 {
                            return n1 < n2
                        }
                        return false
                    }
                    
                    ForEach(sortedEpisodes) { episode in
                        Button {
                            selectedItem = episode
                            showingStreams = true
                        } label: {
                            EpisodeRow(episode: episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func errorView(_ error: ConnectorError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            
            Text("Error Loading Details")
                .font(.headline)
            
            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task { await loadDetails() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    /// Normalized, cross-provider metadata (genres as chips, creators, cast).
    @ViewBuilder
    private func canonicalSection(_ meta: ContentMetadata) -> some View {
        if !meta.genres.isEmpty || !meta.creators.isEmpty || !meta.cast.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !meta.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(meta.genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                if !meta.creators.isEmpty {
                    Text("Creators: \(meta.creators.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !meta.cast.isEmpty {
                    Text("Cast: \(meta.cast.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var saveMenu: some View {
        Menu {
            ForEach(LibraryCollection.allCases, id: \.self) { collection in
                Button {
                    LibraryActions.toggle(item, extensionID: connectorId, collection: collection, context: context)
                } label: {
                    let saved = LibraryActions.isSaved(item, extensionID: connectorId, in: collection, context: context)
                    Label(collection.title, systemImage: saved ? "checkmark" : collection.systemImage)
                }
            }
        } label: {
            Image(systemName: "plus.circle")
        }
    }

    private func loadDetails() async {
        isLoading = true
        error = nil
        
        do {
            details = try await RuntimeEngine.shared.details(connectorId, itemId: item.id)
        } catch let err as ConnectorError {
            error = err
        } catch let other {
            error = ConnectorError(.unknown, other.localizedDescription)
        }
        
        isLoading = false
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: CatalogItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Episode thumbnail
            AsyncImage(url: episode.artworkUrl.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay { ProgressView() }
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 4) {
                if let epNum = episode.metadata?["episode"], case .int(let epNumValue) = epNum {
                    Text("\(epNumValue). \(episode.title)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                } else {
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
                
                if let subtitle = episode.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        MediaDetailView(
            connectorId: "example",
            item: CatalogItem(
                id: "1",
                title: "Example Movie",
                subtitle: "A great movie",
                artworkUrl: nil,
                kind: .movie,
                metadata: nil
            )
        )
    }
}
