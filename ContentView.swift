//
//  ContentView.swift
//  Runtime
//
//  Created by alvin on 7/7/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProfileManager.self) private var profiles
    @Query private var repositories: [RepositorySource]

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            ExtensionsView()
                .tabItem { Label("Providers", systemImage: "square.grid.2x2") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.blue)
        .preferredColorScheme(resolvedColorScheme)
        .task {
            profiles.bootstrap(context: context)
            registerNativeProviders()
            seedDefaultRepositoryIfNeeded()
            await InstalledPackageStore.bootstrap(into: .shared)
        }
    }

    /// The active profile's preferred appearance (Phase 6); nil follows the system.
    private var resolvedColorScheme: ColorScheme? {
        switch profiles.current?.preferences.colorScheme ?? .dark {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// Register in-app native providers (Phase: Provider Ecosystem). YouTube is a
    /// native API provider; it only registers when an API key is configured.
    private func registerNativeProviders() {
        // Shared artwork cache (reused by every provider's AsyncImage-backed art).
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024)

        let youTubeLogger = RuntimeLogger(extensionID: YouTubeProvider.providerID)
        if YouTubeConfig.isConfigured {
            MediaCatalog.shared.register(YouTubeProvider())
            youTubeLogger.install("Registered native YouTube provider")
        } else {
            youTubeLogger.warning("YouTube provider not registered: no API key configured")
        }

        // Restore a previously-connected Plex session from the persisted token.
        let plexLogger = RuntimeLogger(extensionID: PlexProvider.providerID)
        if let token = KeychainTokenStore().token(for: PlexProvider.providerID) {
            Task {
                let session = PlexSession()
                do {
                    try await session.restore(authToken: token)
                    MediaCatalog.shared.register(PlexProvider(session: session))
                    plexLogger.install("Restored native Plex provider")
                } catch {
                    plexLogger.warning("Plex session restore failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// On first launch, add the bundled sample repository so the browser has content.
    private func seedDefaultRepositoryIfNeeded() {
        guard repositories.isEmpty else { return }
        context.insert(RepositorySource(url: SampleRepository.repositoryURLString, title: "Rext Official (Sample)"))
    }
}

#Preview {
    ContentView()
        .environment(ProfileManager.shared)
        .modelContainer(for: [RepositorySource.self, LibraryItem.self, HistoryEntry.self, PlaybackEvent.self, ContentNode.self, ActivityEvent.self, UserProfile.self, QueueItem.self, ProviderAccount.self], inMemory: true)
}
