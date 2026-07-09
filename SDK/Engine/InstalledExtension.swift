import Foundation

// ---------------------------------------------------------------------------
// InstalledExtension.swift  (Runtime SDK v1)
//
// The registered, ready-to-run record for one extension: its validated manifest,
// the entry-point JavaScript source, where it came from, its lifecycle state,
// and its dedicated logger. Immutable value type — the engine advances `state`
// by replacing the record in its registry, keeping mutation confined to the
// engine actor.
// ---------------------------------------------------------------------------

public nonisolated struct InstalledExtension: Sendable, Identifiable {
    public let manifest: ExtensionManifest
    public let entryPointSource: String
    public let origin: String
    public let logger: RuntimeLogger
    public var state: ExtensionState

    public var id: String { manifest.id }
    public var capabilities: Set<Capability> { manifest.capabilities }

    public init(
        manifest: ExtensionManifest,
        entryPointSource: String,
        origin: String,
        logger: RuntimeLogger,
        state: ExtensionState
    ) {
        self.manifest = manifest
        self.entryPointSource = entryPointSource
        self.origin = origin
        self.logger = logger
        self.state = state
    }

    /// The security configuration handed to the execution layer.
    public var runtimeConfiguration: RuntimeConfiguration {
        RuntimeConfiguration(manifest: manifest)
    }

    public func supports(_ capability: Capability) -> Bool {
        manifest.supports(capability)
    }
}
