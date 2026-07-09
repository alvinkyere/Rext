import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// HomeView.swift  (Rext Phase 2 — Priority 4: Home dashboard)
//
// Opens the app to a dashboard rather than a search bar. Sections are backed by
// real data: Continue (in-progress history), Recently Added (library), Installed
// Extensions, and Recent Activity (structured logs). Sections with no data hide
// themselves, so the dashboard fills in as the user uses the app.
// ---------------------------------------------------------------------------

struct HomeView: View {
    @Query(sort: \HistoryEntry.lastAccessed, order: .reverse) private var history: [HistoryEntry]
    @Query(sort: \LibraryItem.addedAt, order: .reverse) private var library: [LibraryItem]

    @State private var installed: [InstalledExtension] = []
    @State private var activity: [LogEvent] = []

    private var continueItems: [HistoryEntry] { history.filter(\.isInProgress) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero

                    if !continueItems.isEmpty {
                        rail("Continue") {
                            ForEach(continueItems) { entry in
                                NavigationLink {
                                    MediaDetailView(connectorId: entry.extensionID, item: CatalogItem(history: entry))
                                } label: {
                                    PosterCard(title: entry.title, artworkURL: entry.artworkURL, progress: entry.progress)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !library.isEmpty {
                        rail("Recently Added") {
                            ForEach(library.prefix(12)) { item in
                                NavigationLink {
                                    MediaDetailView(connectorId: item.extensionID, item: CatalogItem(library: item))
                                } label: {
                                    PosterCard(title: item.title, artworkURL: item.artworkURL)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    installedSection
                    activitySection
                }
                .padding(.vertical)
            }
            .navigationTitle("Home")
            .task {
                installed = await RuntimeEngine.shared.installedExtensions
                activity = LogBus.shared.history(limit: 20)
            }
        }
    }

    private var hero: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(height: 150)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rext").font(.largeTitle.bold()).foregroundStyle(.white)
                    Text("Your extensions, your content.").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                .padding()
            }
            .padding(.horizontal)
    }

    private func rail<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) { content() }.padding(.horizontal)
            }
        }
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installed Extensions").font(.title3.bold()).padding(.horizontal)
            if installed.isEmpty {
                Text("No extensions installed yet.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                ForEach(installed) { ext in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8).fill(.blue.gradient).frame(width: 36, height: 36)
                            .overlay { Image(systemName: "puzzlepiece.extension.fill").font(.caption).foregroundStyle(.white) }
                        VStack(alignment: .leading) {
                            Text(ext.manifest.displayName).font(.subheadline)
                            Text("v\(ext.manifest.version.description)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !activity.isEmpty {
                Text("Recent Activity").font(.title3.bold()).padding(.horizontal)
                ForEach(activity.suffix(8).reversed()) { event in
                    Text("· \(event.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
            }
        }
    }
}
