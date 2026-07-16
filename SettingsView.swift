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
    @Environment(ProfileManager.self) private var profiles
    @Query(sort: \RepositorySource.addedAt) private var repositories: [RepositorySource]

    @AppStorage("defaultVideoQuality") private var defaultQuality = "1080p"
    @AppStorage("enableDebugLogging") private var debugLogging = false

    @State private var newRepositoryURL: String = ""
    @State private var sync: SyncEngine?

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                appearanceSection
                syncSection

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
            .task { if sync == nil { sync = SyncEngine(context: context) } }
        }
    }

    // MARK: - Cloud Sync (Phase 7)

    @ViewBuilder
    private var syncSection: some View {
        Section("Cloud Sync") {
            if let sync {
                LabeledContent("Backend") { Text(sync.backendName).foregroundStyle(.secondary) }
                LabeledContent("Status") { syncStatusView(sync.status) }
                if let last = sync.lastSyncedAt {
                    LabeledContent("Last Synced") { Text(last, format: .relative(presentation: .named)) }
                }
                Button {
                    Task { await sync.syncNow() }
                } label: {
                    if sync.isSyncing {
                        HStack(spacing: 8) { ProgressView(); Text("Syncing…") }
                    } else {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(sync.isSyncing)
                Text("Your library, activity, profiles, and settings are backed up on this device, ready to sync to the cloud in a future update.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func syncStatusView(_ status: SyncStatus) -> some View {
        switch status {
        case .idle:
            Text("Idle").foregroundStyle(.secondary)
        case .syncing:
            Text("Syncing…").foregroundStyle(.blue)
        case .succeeded:
            Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    // MARK: - Profile (Phase 6)

    @ViewBuilder
    private var profileSection: some View {
        Section("Profile") {
            if let current = profiles.current {
                HStack(spacing: 12) {
                    ProfileAvatarView(profile: current, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.name).font(.body)
                        Text(current.kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if current.isGuest {
                        Text("Guest").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            NavigationLink {
                ProfilesView()
            } label: {
                Label("Manage Profiles", systemImage: "person.2.crop.square.stack.fill")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: colorSchemeBinding) {
                ForEach(AppColorScheme.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Autoplay Next", isOn: autoplayBinding)
        }
    }

    private var colorSchemeBinding: Binding<AppColorScheme> {
        Binding(
            get: { profiles.current?.preferences.colorScheme ?? .system },
            set: { newValue in
                guard let current = profiles.current else { return }
                current.preferences.colorScheme = newValue
                profiles.save()
            }
        )
    }

    private var autoplayBinding: Binding<Bool> {
        Binding(
            get: { profiles.current?.preferences.autoplayNext ?? true },
            set: { newValue in
                guard let current = profiles.current else { return }
                current.preferences.autoplayNext = newValue
                profiles.save()
            }
        )
    }

    private func addRepository() {
        let trimmed = newRepositoryURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !repositories.contains(where: { $0.url == trimmed }) else { return }
        context.insert(RepositorySource(url: trimmed))
        newRepositoryURL = ""
    }
}
