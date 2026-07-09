import SwiftUI

// ---------------------------------------------------------------------------
// SearchView.swift  (Rext Phase 2 — Priority 3: Unified Search)
//
// Searches every installed extension simultaneously and presents the results
// grouped by extension in a single experience. One of Rext's defining features:
// the user never picks a source first — they just search.
// ---------------------------------------------------------------------------

struct SearchView: View {
    @State private var query: String = ""
    @State private var results: [UnifiedSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var hasSearched: Bool = false

    private var groups: [UnifiedSearchResult] {
        results.filter { !$0.items.isEmpty || $0.errorMessage != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView("Searching…")
                } else if !hasSearched {
                    ContentUnavailableView("Search Everything", systemImage: "magnifyingglass",
                                           description: Text("Search across all your installed extensions at once."))
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
        }
        .searchable(text: $query, prompt: "Search all extensions")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty { results = []; hasSearched = false }
        }
    }

    private var resultsList: some View {
        List {
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
        results = await RuntimeEngine.shared.searchAll(query: trimmed)
        isSearching = false
    }
}
