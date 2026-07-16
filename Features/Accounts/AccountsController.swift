import Foundation
import SwiftData
import Observation

// ---------------------------------------------------------------------------
// AccountsController.swift  (Rext — Provider Accounts)
//
// Drives the Accounts experience: reconciles ProviderAccount rows with the set
// of installed providers, and runs connect / disconnect / enable through a
// provider connection state machine. Web authentication (when a provider needs
// it) is surfaced via `authRequest`, which the view presents in an isolated
// WKWebView; the resulting token is stored in the Keychain (TokenStore).
// ---------------------------------------------------------------------------

@MainActor
@Observable
final class AccountsController {
    struct AuthRequest: Identifiable {
        let id = UUID()
        let providerID: String
        let displayName: String
        let url: URL
        let dataStoreID: String
    }

    private let context: ModelContext
    private let engine: RuntimeEngine
    private let tokenStore: TokenStore

    var accounts: [ProviderAccount] = []
    var authRequest: AuthRequest?
    /// Manifests for installed providers, keyed by id (for auth policy + permissions UI).
    private(set) var manifests: [String: ExtensionManifest] = [:]

    func manifest(for providerID: String) -> ExtensionManifest? { manifests[providerID] }

    init(context: ModelContext, engine: RuntimeEngine = .shared, tokenStore: TokenStore = KeychainTokenStore()) {
        self.context = context
        self.engine = engine
        self.tokenStore = tokenStore
    }

    // MARK: - Reconciliation

    /// Ensure a ProviderAccount exists for every installed provider, seeding its
    /// initial state from whether the provider requires authentication.
    func reload() async {
        let installed = await engine.installedExtensions
        for provider in installed {
            reconcile(provider)
        }
        // Native providers (e.g. YouTube) also get an account row.
        for native in MediaCatalog.shared.nativeProviders.values {
            reconcileNative(id: native.id, name: native.displayName)
        }
        // Connect-based native providers must be listed *before* they register, so
        // there's a row to tap "Connect" on (Plex only registers post-OAuth).
        reconcileNative(id: PlexProvider.providerID, name: "Plex")
        try? context.save()
        publish()
    }

    /// Ensure an account exists for a native provider; native providers require a
    /// sign-in (OAuth) to become usable, so they seed as `loginRequired`.
    private func reconcileNative(id: String, name: String) {
        let account = account(for: id) ?? {
            let created = ProviderAccount(extensionID: id, displayName: name)
            context.insert(created)
            return created
        }()
        account.displayName = name
        if account.state == .installed {
            account.state = .loginRequired
        }
    }

    /// Test-friendly seam: reconcile from already-known manifests.
    func reconcile(_ provider: InstalledExtension) {
        let id = provider.id
        let account = account(for: id) ?? {
            let created = ProviderAccount(extensionID: id, displayName: provider.manifest.displayName)
            context.insert(created)
            return created
        }()
        account.displayName = provider.manifest.displayName
        manifests[id] = provider.manifest
        // Seed initial state only when freshly installed / never touched.
        if account.state == .installed {
            account.state = requiresAuthentication(provider.manifest) ? .loginRequired : .connected
            if account.state == .connected { account.connectedAt = .now }
        }
    }

    // MARK: - Connection lifecycle

    /// Begin connecting a provider. Providers with a login surface open a web auth
    /// flow; those without are marked connected immediately.
    func connect(_ providerID: String) {
        guard let account = account(for: providerID) else { return }
        account.errorDetail = nil

        // YouTube connects via Sign in with Google (OAuth), not a generic web sheet.
        if providerID == YouTubeProvider.providerID {
            account.state = .connecting
            save()
            Task { await signInYouTube(account) }
            return
        }

        // Plex connects via the plex.tv OAuth PIN flow, then discovers servers.
        if providerID == PlexProvider.providerID {
            account.state = .connecting
            save()
            Task { await signInPlex(account) }
            return
        }

        if let manifest = manifests[providerID], requiresAuthentication(manifest), let url = authURL(manifest) {
            account.state = .connecting
            save()
            authRequest = AuthRequest(providerID: providerID, displayName: account.displayName, url: url, dataStoreID: account.dataStoreID)
        } else {
            markConnected(account)
        }
    }

    /// Complete a web auth flow with the captured provider session token.
    func completeAuthentication(providerID: String, token: String) {
        authRequest = nil
        guard let account = account(for: providerID) else { return }
        tokenStore.save(token, for: providerID)
        markConnected(account)
    }

    func cancelAuthentication() {
        if let providerID = authRequest?.providerID, let account = account(for: providerID) {
            // Return to a resolvable state rather than leaving it "connecting".
            account.state = tokenStore.token(for: providerID) != nil ? .connected : .loginRequired
            save()
        }
        authRequest = nil
    }

    func disconnect(_ providerID: String) {
        guard let account = account(for: providerID) else { return }
        tokenStore.delete(for: providerID)
        if providerID == PlexProvider.providerID {
            MediaCatalog.shared.unregister(providerID)
        }
        account.connectedAt = nil
        account.accountName = nil
        let nativeIDs: Set<String> = [YouTubeProvider.providerID, PlexProvider.providerID]
        let needsAuth = nativeIDs.contains(providerID)
            ? true
            : (manifests[providerID].map(requiresAuthentication) ?? true)
        account.state = needsAuth ? .loginRequired : .connected
        save()
    }

    func setEnabled(_ providerID: String, _ enabled: Bool) {
        guard let account = account(for: providerID) else { return }
        account.isEnabled = enabled
        if !enabled {
            account.state = .disabled
        } else {
            let hasToken = tokenStore.token(for: providerID) != nil
            let needsAuth = manifests[providerID].map(requiresAuthentication) ?? false
            account.state = hasToken ? .connected : (needsAuth ? .loginRequired : .connected)
        }
        save()
    }

    // MARK: - Diagnostics

    func storageBytes(of providerID: String) async -> Int {
        await engine.storageBytes(of: providerID)
    }

    func logs(of providerID: String) -> [LogEvent] {
        LogBus.shared.history(forExtension: providerID, limit: 100)
    }

    func hasToken(_ providerID: String) -> Bool {
        tokenStore.token(for: providerID) != nil
    }

    /// The current connection state for a provider, if known.
    func state(of providerID: String) -> ProviderConnectionState? {
        account(for: providerID)?.state
    }

    // MARK: - Auth policy

    /// A provider needs authentication when it talks to an external, non-open host.
    func requiresAuthentication(_ manifest: ExtensionManifest) -> Bool {
        guard let network = manifest.permissions.network else { return false }
        return !network.domains.isEmpty || (network.allowUserConfiguredHost ?? false)
    }

    func authURL(_ manifest: ExtensionManifest) -> URL? {
        if let website = manifest.website, let url = URL(string: website) { return url }
        if let domain = manifest.permissions.network?.domains.first { return URL(string: "https://\(domain)") }
        return nil
    }

    // MARK: - Internals

    /// Run Google OAuth for the YouTube provider and record the connection.
    private func signInYouTube(_ account: ProviderAccount) async {
        #if canImport(AuthenticationServices)
        do {
            let service = GoogleOAuthService()
            let tokens = try await service.signIn()
            if let data = try? JSONEncoder().encode(tokens), let json = String(data: data, encoding: .utf8) {
                tokenStore.save(json, for: account.extensionID)
            }
            account.accountName = try? await service.channelTitle(accessToken: tokens.accessToken)
            account.state = .connected
            account.connectedAt = .now
            account.errorDetail = nil
        } catch {
            account.state = .loginRequired
            account.errorDetail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        save()
        #else
        account.state = .loginRequired
        save()
        #endif
    }

    /// Run the Plex PIN OAuth flow, discover the server, and register the provider.
    private func signInPlex(_ account: ProviderAccount) async {
        #if canImport(AuthenticationServices)
        do {
            // Hold a strong reference for the whole flow — the web-auth session
            // keeps its presentation-context provider weakly, so an anonymous
            // temporary can be released mid-flow (WebAuthenticationSession error 3).
            let authenticator = PlexAuthenticator()
            let token = try await authenticator.signIn()
            tokenStore.save(token, for: PlexProvider.providerID)
            let session = PlexSession()
            try await session.connect(authToken: token)
            MediaCatalog.shared.register(PlexProvider(session: session))
            let summary = await session.summary()
            account.accountName = [summary.serverName, summary.user].compactMap { $0 }.first
            account.state = .connected
            account.connectedAt = .now
            account.errorDetail = nil
        } catch {
            account.state = .loginRequired
            account.errorDetail = Self.readableError(error)
        }
        save()
        #else
        account.state = .loginRequired
        save()
        #endif
    }

    /// Prefer a provider's structured message over the generic NSError string.
    static func readableError(_ error: Error) -> String {
        if let connector = error as? ConnectorError { return connector.message }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func markConnected(_ account: ProviderAccount) {
        account.state = .connected
        account.connectedAt = .now
        account.errorDetail = nil
        save()
    }

    private func account(for id: String) -> ProviderAccount? {
        accounts.first { $0.extensionID == id }
            ?? (try? context.fetch(FetchDescriptor<ProviderAccount>(predicate: #Predicate { $0.extensionID == id })))?.first
    }

    private func save() {
        try? context.save()
        publish()
    }

    private func publish() {
        accounts = (try? context.fetch(FetchDescriptor<ProviderAccount>(sortBy: [SortDescriptor(\.displayName)]))) ?? []
    }
}
