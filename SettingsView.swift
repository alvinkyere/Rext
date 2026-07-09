import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// SettingsView.swift  (Rext Phase 2 — Priority 1: repositories + general)
//
// Manages the repositories the user has added (the source of the Repository
// Browser) alongside general app settings. Repositories are stored in SwiftData;
// toggling one off excludes it from browsing without removing it.
// ---------------------------------------------------------------------------

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RepositorySource.addedAt) private var repositories: [RepositorySource]

    @AppStorage("defaultVideoQuality") private var defaultQuality = "1080p"
    @AppStorage("enableDebugLogging") private var debugLogging = false

    @State private var newRepositoryURL: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Repositories") {
                    ForEach(repositories) { repo in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.title ?? repo.url).font(.body)
                                Text(repo.url).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { repo.isEnabled },
                                set: { repo.isEnabled = $0 }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(repositories[index]) }
                    }

                    HStack {
                        TextField("Add repository URL", text: $newRepositoryURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") { addRepository() }
                            .disabled(newRepositoryURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Playback") {
                    Picker("Default Quality", selection: $defaultQuality) {
                        Text("Auto").tag("auto")
                        Text("4K").tag("2160p")
                        Text("1080p").tag("1080p")
                        Text("720p").tag("720p")
                        Text("480p").tag("480p")
                    }
                }

                Section("Advanced") {
                    Toggle("Enable Debug Logging", isOn: $debugLogging)
                    Button("Clear All Connector Data") {
                        Task { await RuntimeEngine.shared.disposeAll() }
                    }
                    .foregroundStyle(.red)
                }

                Section("About") {
                    LabeledContent("Runtime", value: RuntimeVersion.current.description)
                    LabeledContent("SDK", value: RuntimeVersion.sdk.description)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func addRepository() {
        let trimmed = newRepositoryURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !repositories.contains(where: { $0.url == trimmed }) else { return }
        context.insert(RepositorySource(url: trimmed))
        newRepositoryURL = ""
    }
}
