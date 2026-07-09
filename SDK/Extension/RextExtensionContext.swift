import Foundation

// ---------------------------------------------------------------------------
// RextExtensionContext.swift  (Rext Extension SDK)
//
// The host-side handle passed to an extension at initialization. It carries the
// capabilities the host grants — a dedicated logger, the security configuration
// derived from the manifest, and the host version — without exposing any host
// internals. For JavaScript extensions the live capabilities are the injected
// `Runtime` global; this context is the Swift-side counterpart the engine uses to
// wire an extension up.
// ---------------------------------------------------------------------------

public nonisolated struct RextExtensionContext: Sendable {
    public let extensionID: String
    public let configuration: RuntimeConfiguration
    public let logger: RuntimeLogger
    public let hostVersion: SemanticVersion

    public init(
        extensionID: String,
        configuration: RuntimeConfiguration,
        logger: RuntimeLogger,
        hostVersion: SemanticVersion = RuntimeVersion.current
    ) {
        self.extensionID = extensionID
        self.configuration = configuration
        self.logger = logger
        self.hostVersion = hostVersion
    }
}
