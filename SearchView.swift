import SwiftUI

// ---------------------------------------------------------------------------
// SearchView.swift  (Rext Phase 2 unified search; "Ask Rext" AI mode in Phase 10)
//
// Searches every installed extension simultaneously and presents the results
// grouped by extension. In "Ask Rext" mode a natural-language request is first
// interpreted by the AI layer (Apple Intelligence on-device when available, a
// deterministic parser otherwise) into a structured intent that drives the same
// unified search — the AI consumes the platform, it doesn't bypass it.
// ---------------------------------------------------------------------------

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @State private var query: String = ""
    @State private var results: [UnifiedSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var hasSearched: Bool = false
    @State private var aiMode: Bool = false
    @State private var aiSummary: String?

    private let assistant: any AIAssistant = AIAssistantFactory.make()

    private var groups: [UnifiedSearchResult] {
        results.filter { !$0.items.isEmpty || $0.errorMessage != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView(aiMode ? "Thinking…" : "Searching…")
                } else if !hasSearched {
                    idleState
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    resultsList
                }
            }
            .navigationTitle(aiMode ? "Ask Rext" : "Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        aiMode.toggle()
                        aiSummary = nil
                    } label: {
                        Image(systemName: aiMode ? "wand.and.stars.inverse" : "wand.and.stars")
                    }
                    .accessibilityLabel(aiMode ? "Turn off Ask Rext" : "Ask Rext with natural language")
                }
            }
        }
        .searchable(text: $query, prompt: aiMode ? "Try “funny sci-fi movies”" : "Search all extensions")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty { results = []; hasSearched = false; aiSummary = nil }
        }
    }

    // MARK: - Idle state

    @ViewBuilder
    private var idleState: some View {
        if aiMode {
            ContentUnavailableView {
                Label("Ask Rext", systemImage: "wand.and.stars")
            } description: {
                Text("Describe what you're in the mood for — “a relaxing documentary,” “sci-fi movies about space” — and Rext finds it across your providers.\n\n\(AIAssistantFactory.availabilityLabel).")
            }
        } else if recentSearches.isEmpty {
            ContentUnavailableView("Search Everything", systemImage: "magnifyingglass",
                                   description: Text("Search across all your installed extensions at once."))
        } else {
            recentSearchesList
        }
    }

    /// Recent, de-duplicated queries from the Activity Graph (Phase 4/9).
    private var recentSearches: [String] {
        ActivityLog(context: context).recentSearches(limit: 8)
    }

    private var recentSearchesList: some View {
        List {
            Section("Recent Searches") {
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        query = term
                        Task { await runSearch() }
                    } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private var resultsList: some View {
        List {
            if let aiSummary {
                Section {
                    Label(aiSummary, systemImage: "wand.and.stars")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(groups) { group in
                Section(group.displayName) {
                    if let error = group.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.items) { item in
                        NavigationLink {
                            MediaDetailView(connectorId: group.extensionID, item: item)
                        } label: {
                            CatalogItemRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        hasSearched = true
        // Record the search on the activity timeline (Phase 4).
        SwiftDataActivityRecorder(context: context).record(.search(trimmed))

        if aiMode {
            let intent = await assistant.interpretSearch(trimmed)
            aiSummary = intent.summary
            results = await MediaCatalog.shared.searchAll(query: intent.query(fallback: trimmed))
        } else {
            aiSummary = nil
            results = await MediaCatalog.shared.searchAll(query: trimmed)
        }
        isSearching = false
    }
}
