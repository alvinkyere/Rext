import Foundation

// ---------------------------------------------------------------------------
// JSExtension.swift  (Rext Extension SDK — the JavaScript adapter)
//
// Adapts a sandboxed `ConnectorRuntime` (RuntimeBridge.swift) to the host-side
// `RextExtension` protocol. Each method dispatches to the matching JS entry point
// on `connectorInstance` and decodes the result into a standardized model. This
// is the bridge between "the engine programs against RextExtension" and "the
// actual code is untrusted JavaScript running behind the security boundary".
// ---------------------------------------------------------------------------

public nonisolated final class JSExtension: RextExtension, @unchecked Sendable {
    public let id: String
    private let runtime: ConnectorRuntime
    private let logger: RuntimeLogger
    private let normalizer = MetadataNormalizer()

    public init(id: String, runtime: ConnectorRuntime, logger: RuntimeLogger) {
        self.id = id
        self.runtime = runtime
        self.logger = logger
    }

    public func initialize(context: RextExtensionContext) async {
        // The JS context is already initialized when the ConnectorRuntime is
        // created; this hook exists for the protocol and native implementations.
        logger.initialize("Extension ready")
    }

    public func search(query: String, page: Int?) async throws -> [CatalogItem] {
        try await runtime.call("search", args: [query, page], as: [CatalogItem].self).map(normalizer.normalize)
    }

    public func getDetails(id: String) async throws -> MediaDetails {
        normalizer.normalize(try await runtime.call("getDetails", args: [id], as: MediaDetails.self))
    }

    public func getEpisodes(id: String) async throws -> [CatalogItem] {
        try await runtime.call("getEpisodes", args: [id], as: [CatalogItem].self).map(normalizer.normalize)
    }

    public func getStreams(itemId: String, episodeId: String?) async throws -> [StreamSource] {
        try await runtime.call("getStreams", args: [itemId, episodeId], as: [StreamSource].self)
    }

    public func execute(action: String, payload: [String: JSONScalar]) async throws -> RextResponse {
        let jsPayload = payload.mapValues(\.anyValue)
        return try await runtime.call(action, args: [jsPayload], as: RextResponse.self)
    }
}
