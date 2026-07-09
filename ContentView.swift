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
    @Query private var repositories: [RepositorySource]

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            ExtensionsView()
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.blue)
        .preferredColorScheme(.dark)
        .task {
            seedDefaultRepositoryIfNeeded()
            await InstalledPackageStore.bootstrap(into: .shared)
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
        .modelContainer(for: [RepositorySource.self, LibraryItem.self, HistoryEntry.self, PlaybackEvent.self], inMemory: true)
}
