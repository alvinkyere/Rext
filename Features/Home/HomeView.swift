import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// HomeView.swift  (Rext dynamic feed — premium redesign)
//
// A premium, Apple-TV/Music-grade home: a featured spotlight up top, then rich
// horizontal rails built dynamically by HomeFeedBuilder (Continue, Up Next,
// Trending, affinity collections, Recently Added) with network-backed
// recommendations layered in. Large artwork, gradient backdrop, graceful empty
// state. Everything is data-driven from the platform services and reactive to
// the active profile.
// ---------------------------------------------------------------------------

struct HomeView: View {
    @Query private var history: [HistoryEntry]
    @Query private var library: [LibraryItem]
    @Query private var queue: [QueueItem]

    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileManager.self) private var profiles

    @State private var installed: [InstalledExtension] = []
    @State private var recommendations: [Recommendation] = []
    @State private var showingSwitcher = false

    private var feed: [HomeSection] {
        HomeFeedBuilder(context: modelContext, profileID: profiles.currentProfileID).build()
    }

    /// The top pick for the featured spotlight: best recommendation, else the
    /// first item of the first available rail.
    private var featured: (extensionID: String, item: CatalogItem, tagline: String?)? {
        if let rec = recommendations.first {
            return (rec.extensionID, rec.item, rec.reason.headline)
        }
        if let section = feed.first, let entry = section.items.first {
            return (entry.extensionID, entry.item, section.title)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RextBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        if let featured {
                            NavigationLink {
                                MediaDetailView(connectorId: featured.extensionID, item: featured.item)
                            } label: {
                                FeaturedSpotlight(title: featured.item.title, subtitle: featured.tagline,
                                                  artworkURL: featured.item.artworkUrl)
                            }
                            .buttonStyle(.plain)
                        }

                        if feed.isEmpty && recommendations.isEmpty {
                            emptyFeed
                        }

                        if let continueSection = feed.first(where: { $0.id == "continue" }) {
                            rail(continueSection.title, subtitle: nil, items: continueSection.items, size: .large)
                        }

                        if !recommendations.isEmpty {
                            recommendedRail
                        }

                        ForEach(feed.filter { $0.id != "continue" }) { section in
                            rail(section.title, subtitle: section.subtitle, items: section.items)
                        }

                        installedSection
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let current = profiles.current {
                        Button { showingSwitcher = true } label: {
                            ProfileAvatarView(profile: current, size: 30)
                        }
                        .accessibilityLabel("Switch profile")
                    }
                }
            }
            .sheet(isPresented: $showingSwitcher) {
                ProfileSwitcher().environment(profiles)
            }
            .task(id: profiles.currentProfileID) {
                installed = await RuntimeEngine.shared.installedExtensions
                recommendations = await RecommendationService(context: modelContext).recommendations()
            }
        }
    }

    // MARK: - Rails

    private func rail(_ title: String, subtitle: String?, items: [HomeFeedItem], size: PosterSize = .regular) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RailHeader(title: title, subtitle: subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.railSpacing) {
                    ForEach(items) { entry in
                        NavigationLink {
                            MediaDetailView(connectorId: entry.extensionID, item: entry.item)
                        } label: {
                            PosterCard(title: entry.item.title, artworkURL: entry.item.artworkUrl,
                                       subtitle: entry.item.subtitle, progress: entry.progress, size: size)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var recommendedRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            RailHeader(title: "Recommended for You", subtitle: "Because of what you watch")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.railSpacing) {
                    ForEach(recommendations) { rec in
                        NavigationLink {
                            MediaDetailView(connectorId: rec.extensionID, item: rec.item)
                        } label: {
                            PosterCard(title: rec.item.title, artworkURL: rec.item.artworkUrl,
                                       subtitle: rec.reason.headline, size: .large)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Empty & installed

    private var emptyFeed: some View {
        ContentUnavailableView {
            Label("Nothing here yet", systemImage: "sparkles.tv")
        } description: {
            Text("Connect a provider and start watching — your Home fills in with what you're into.")
        } actions: {
            NavigationLink { ExtensionsView() } label: { Text("Browse Providers") }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !installed.isEmpty {
                RailHeader(title: "Your Providers", subtitle: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(installed) { ext in
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(brandGradient(for: ext.manifest.displayName))
                                    .frame(width: 64, height: 64)
                                    .overlay { Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.white) }
                                Text(ext.manifest.displayName).font(.caption2).lineLimit(1).frame(width: 72)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
