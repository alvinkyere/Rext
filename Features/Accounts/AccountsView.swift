import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// AccountsView.swift  (Rext — Provider Accounts, experience layer)
//
// A native Accounts screen for managing connected providers: connection status,
// sign in / sign out, enable / disable, and per-provider diagnostics. Feels like
// adding streaming services to Rext, not managing plugins. Data-driven from
// AccountsController; sign-in happens inside the provider's own web view.
// ---------------------------------------------------------------------------

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @State private var controller: AccountsController?

    var body: some View {
        List {
            if let controller {
                if controller.accounts.isEmpty {
                    ContentUnavailableView("No Providers Yet", systemImage: "person.crop.circle.badge.plus",
                                           description: Text("Install a provider to connect your accounts."))
                } else {
                    Section {
                        ForEach(controller.accounts) { account in
                            NavigationLink {
                                ProviderAccountDetailView(providerID: account.extensionID, controller: controller)
                            } label: {
                                AccountRow(account: account)
                            }
                            .swipeActions {
                                connectSwipe(account, controller: controller)
                            }
                        }
                    } footer: {
                        Text("Rext never sees your passwords. You sign in on each provider's own site, and only the resulting session is stored securely in the Keychain.")
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Accounts")
        .task {
            if controller == nil { controller = AccountsController(context: context) }
            await controller?.reload()
        }
        .sheet(item: authBinding) { request in
            #if canImport(WebKit)
            ProviderAuthSheet(
                request: request,
                onComplete: { controller?.completeAuthentication(providerID: request.providerID, token: $0) },
                onCancel: { controller?.cancelAuthentication() }
            )
            #endif
        }
    }

    private var authBinding: Binding<AccountsController.AuthRequest?> {
        Binding(get: { controller?.authRequest }, set: { controller?.authRequest = $0 })
    }

    @ViewBuilder
    private func connectSwipe(_ account: ProviderAccount, controller: AccountsController) -> some View {
        if account.state.isActive {
            Button(role: .destructive) { controller.disconnect(account.extensionID) } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } else {
            Button { controller.connect(account.extensionID) } label: {
                Label("Connect", systemImage: "link")
            }
            .tint(.blue)
        }
    }
}

// MARK: - Rows & badges

struct ConnectionBadge: View {
    let state: ProviderConnectionState

    var body: some View {
        Label(state.title, systemImage: state.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .blue
        case .loginRequired, .expired, .error: return .orange
        case .offline, .disabled, .installed, .notInstalled: return .secondary
        }
    }
}

private struct AccountRow: View {
    let account: ProviderAccount

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.blue.gradient)
                .frame(width: 40, height: 40)
                .overlay { Image(systemName: "person.crop.circle.fill").foregroundStyle(.white) }
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName).font(.headline)
                if let accountName = account.accountName, !accountName.isEmpty {
                    Text(accountName).font(.caption).foregroundStyle(.secondary)
                }
                ConnectionBadge(state: account.state)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct ProviderAccountDetailView: View {
    let providerID: String
    let controller: AccountsController

    @State private var storageBytes: Int = 0
    @State private var plexLibraries: [PlexLibrary] = []
    @State private var plexServerName: String?
    @State private var plexServerVersion: String?

    private var account: ProviderAccount? {
        controller.accounts.first { $0.extensionID == providerID }
    }
    private var manifest: ExtensionManifest? { controller.manifest(for: providerID) }
    private var isPlex: Bool { providerID == PlexProvider.providerID }

    var body: some View {
        List {
            if let account {
                Section("Status") {
                    LabeledContent("Connection") { ConnectionBadge(state: account.state) }
                    if let accountName = account.accountName, !accountName.isEmpty {
                        LabeledContent("Signed in as", value: accountName)
                    }
                    if let connectedAt = account.connectedAt {
                        LabeledContent("Connected") { Text(connectedAt, format: .relative(presentation: .named)) }
                    }
                    if let detail = account.errorDetail {
                        Label(detail, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }

                Section {
                    if account.state.isActive {
                        Button(role: .destructive) { controller.disconnect(providerID) } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button { controller.connect(providerID) } label: {
                            Label("Connect", systemImage: "link")
                        }
                    }
                    Toggle("Enabled", isOn: Binding(
                        get: { account.isEnabled },
                        set: { controller.setEnabled(providerID, $0) }
                    ))
                }

                if isPlex, account.state == .connected {
                    Section("Plex Server") {
                        LabeledContent("Server", value: plexServerName ?? "—")
                        if let version = plexServerVersion {
                            LabeledContent("Version", value: version)
                        }
                        Button { Task { await loadPlexInfo() } } label: {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    if !plexLibraries.isEmpty {
                        Section("Libraries") {
                            ForEach(plexLibraries) { library in
                                Label(library.title, systemImage: plexIcon(for: library.type))
                            }
                        }
                    }
                }

                if let manifest {
                    Section("Permissions") {
                        let permissions = manifest.permissions.declared.map(\.rawValue).sorted()
                        if permissions.isEmpty {
                            Text("None requested").foregroundStyle(.secondary)
                        } else {
                            ForEach(permissions, id: \.self) { Label($0, systemImage: "lock.shield.fill") }
                        }
                    }
                    if let network = manifest.permissions.network, !network.domains.isEmpty {
                        Section("Network Access") {
                            ForEach(network.domains, id: \.self) { Text($0).font(.caption.monospaced()) }
                        }
                    }
                }

                Section("Storage") {
                    LabeledContent("Cached Data", value: ByteCountFormatter.string(fromByteCount: Int64(storageBytes), countStyle: .file))
                }

                Section("Diagnostics") {
                    let logs = controller.logs(of: providerID)
                    if logs.isEmpty {
                        Text("No recent activity").foregroundStyle(.secondary)
                    } else {
                        ForEach(logs.prefix(10)) { event in
                            Text(event.message).font(.caption.monospaced()).lineLimit(2)
                        }
                    }
                }
            }
        }
        .navigationTitle(account?.displayName ?? "Provider")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            storageBytes = await controller.storageBytes(of: providerID)
            if isPlex { await loadPlexInfo() }
        }
    }

    @MainActor
    private func loadPlexInfo() async {
        guard let provider = MediaCatalog.shared.nativeProvider(providerID) as? PlexProvider else { return }
        let summary = await provider.serverSummary()
        plexServerName = summary.serverName
        plexServerVersion = summary.version
        plexLibraries = await provider.libraries()
    }

    private func plexIcon(for type: String) -> String {
        switch type {
        case "movie": return "film"
        case "show": return "tv"
        case "artist", "album": return "music.note"
        case "photo": return "photo"
        default: return "square.stack"
        }
    }
}
