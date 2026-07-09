import Foundation

/// One extension's contribution to a unified (cross-extension) search. Failures
/// are captured per-extension so one bad source never breaks the whole search.
public nonisolated struct UnifiedSearchResult: Sendable, Identifiable {
    public let extensionID: String
    public let displayName: String
    public let items: [CatalogItem]
    public let errorMessage: String?

    public var id: String { extensionID }

    public init(extensionID: String, displayName: String, items: [CatalogItem], errorMessage: String?) {
        self.extensionID = extensionID
        self.displayName = displayName
        self.items = items
        self.errorMessage = errorMessage
    }
}

// ---------------------------------------------------------------------------
// RuntimeEngine.swift  (Runtime SDK v1 — the Engine component)
//
// The single façade the app talks to. It coordinates the whole lifecycle:
// installs packages through the `PackageInstaller`, keeps the `ExtensionRegistry`,
// gates every operation on the extension's declared capabilities, and delegates
// execution to the `RuntimeHost`. It is an `actor`, so its registry is safe under
// concurrency with no locks.
//
// Execution methods surface `ConnectorError` (the type the UI already handles);
// lifecycle failures are projected onto it via `RuntimeError.asConnectorError`.
// Installation surfaces the richer `RuntimeError` directly.
// ---------------------------------------------------------------------------

public actor RuntimeEngine {
    /// The app-wide engine. Uses ephemeral URL sessions and the shared log bus.
    public static let shared = RuntimeEngine()

    private var registry = ExtensionRegistry()
    private let installer: PackageInstaller
    private let host: RuntimeHost

    public init(
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        bus: LogBus = .shared,
        validator: ExtensionValidator = ExtensionValidator()
    ) {
        self.installer = PackageInstaller(validator: validator, bus: bus)
        self.host = RuntimeHost(sessionConfiguration: sessionConfiguration)
    }

    // MARK: - Installation (Priority 9)

    /// Install a packaged extension from any source: `Validate → Parse → Register
    /// → Ready`. Throws a typed `RuntimeError` on any failure.
    @discardableResult
    public func install(from source: PackageSource) async throws -> InstalledExtension {
        var installed = try installer.prepare(from: source, existingIDs: registry.ids)
        try registry.register(installed)
        installed.state = .ready
        registry.update(installed)
        installed.logger.install("Ready", metadata: ["state": "ready"])
        return installed
    }

    /// Replace an already-installed extension with a newer package from any
    /// source (uninstall + reinstall). Used by repository updates.
    @discardableResult
    public func update(from source: PackageSource) async throws -> InstalledExtension {
        let manifest = try ManifestParser.parse(try source.manifestData())
        uninstall(id: manifest.id)
        return try await install(from: source)
    }

    /// Remove an extension and tear down its runtime.
    public func uninstall(id: String) {
        registry.remove(id)
        host.dispose(id: id)
    }

    // MARK: - Discovery (Priority 4)

    public var installedExtensions: [InstalledExtension] {
        registry.all
    }

    public func installedExtension(id: String) -> InstalledExtension? {
        registry.get(id)
    }

    public func isInstalled(_ id: String) -> Bool {
        registry.contains(id)
    }

    /// The capabilities an extension declares. Throws if it is not installed.
    public func capabilities(of id: String) throws -> Set<Capability> {
        guard let ext = registry.get(id) else { throw RuntimeError.notInstalled(id: id) }
        return ext.capabilities
    }

    /// The id of the first installed extension declaring `capability` — a
    /// convenience for UI that needs a sensible default connector.
    public func defaultExtensionID(supporting capability: Capability) -> String? {
        registry.all.first { $0.supports(capability) }?.id
    }

    // MARK: - Execution (capability- & permission-gated, via RextExtension)

    public func search(_ id: String, query: String, page: Int? = nil) async throws -> [CatalogItem] {
        try await resolve(id, capability: .search).search(query: query, page: page)
    }

    public func details(_ id: String, itemId: String) async throws -> MediaDetails {
        try await resolve(id, capability: .details).getDetails(id: itemId)
    }

    public func episodes(_ id: String, itemId: String) async throws -> [CatalogItem] {
        try await resolve(id, capability: .episodes).getEpisodes(id: itemId)
    }

    public func streams(_ id: String, itemId: String, episodeId: String?) async throws -> [StreamSource] {
        try await resolve(id, capability: .streams).getStreams(itemId: itemId, episodeId: episodeId)
    }

    /// Unified search: query every installed extension that declares `search`,
    /// concurrently, tolerating per-extension failures. Results are grouped by
    /// extension (sorted by display name).
    public func searchAll(query: String, page: Int? = nil) async -> [UnifiedSearchResult] {
        let targets: [(id: String, name: String, ext: RextExtension)] = registry.all
            .filter { $0.supports(.search) }
            .map { ($0.id, $0.manifest.displayName, rextExtension(for: $0)) }

        return await withTaskGroup(of: UnifiedSearchResult.self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let items = try await target.ext.search(query: query, page: page)
                        return UnifiedSearchResult(extensionID: target.id, displayName: target.name, items: items, errorMessage: nil)
                    } catch let error as ConnectorError {
                        return UnifiedSearchResult(extensionID: target.id, displayName: target.name, items: [], errorMessage: error.message)
                    } catch {
                        return UnifiedSearchResult(extensionID: target.id, displayName: target.name, items: [], errorMessage: "\(error)")
                    }
                }
            }
            var results: [UnifiedSearchResult] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.displayName < $1.displayName }
        }
    }

    // MARK: - Storage inspection

    /// Bytes currently used by an extension's namespaced storage (0 if idle/absent).
    public func storageBytes(of id: String) -> Int {
        guard let ext = registry.get(id) else { return 0 }
        return host.runtime(for: ext.runtimeConfiguration, source: ext.entryPointSource, logger: ext.logger).storageUsedBytes
    }

    /// Clear an extension's namespaced storage ("Clear Cache").
    public func clearStorage(of id: String) {
        guard let ext = registry.get(id) else { return }
        host.runtime(for: ext.runtimeConfiguration, source: ext.entryPointSource, logger: ext.logger).clearStorage()
    }

    /// Invoke a source-specific action. Runs fully sandboxed (permissions still
    /// enforced); gated only on the extension being installed, not a named capability.
    public func execute(_ id: String, action: String, payload: [String: JSONScalar] = [:]) async throws -> RextResponse {
        try await rextExtension(for: try installedOrThrow(id)).execute(action: action, payload: payload)
    }

    /// Resolve an installed extension to its executable `RextExtension`, enforcing
    /// that it declares `capability`. Lifecycle failures project onto `ConnectorError`.
    private func resolve(_ id: String, capability: Capability) throws -> RextExtension {
        let ext = try installedOrThrow(id)
        guard ext.supports(capability) else {
            ext.logger.warning("Rejected: capability '\(capability.rawValue)' not declared")
            throw RuntimeError.capabilityNotSupported(capability).asConnectorError
        }
        return rextExtension(for: ext)
    }

    private func installedOrThrow(_ id: String) throws -> InstalledExtension {
        guard let ext = registry.get(id) else {
            throw RuntimeError.notInstalled(id: id).asConnectorError
        }
        return ext
    }

    private func rextExtension(for ext: InstalledExtension) -> RextExtension {
        let runtime = host.runtime(for: ext.runtimeConfiguration, source: ext.entryPointSource, logger: ext.logger)
        return JSExtension(id: ext.id, runtime: runtime, logger: ext.logger)
    }

    // MARK: - Teardown

    public func disposeAll() {
        host.disposeAll()
    }
}
