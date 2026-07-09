import Foundation

// ---------------------------------------------------------------------------
// PackageInstaller.swift  (Runtime SDK v1, Priority 9)
//
// Turns a `PackageSource` into a validated, ready-to-register `InstalledExtension`:
//
//   Parse manifest → Validate → Load entry point → (return for registration)
//
// The installer is deliberately origin-agnostic — the same code path serves a
// directory on disk today and a downloaded repository package tomorrow. It does
// not touch the registry itself; the engine owns registration so all shared
// state stays confined to the engine actor. Every step logs through the
// extension's own logger and every failure is a typed `RuntimeError`.
// ---------------------------------------------------------------------------

public nonisolated struct PackageInstaller: Sendable {
    public let validator: ExtensionValidator
    public let bus: LogBus

    public init(validator: ExtensionValidator = ExtensionValidator(), bus: LogBus = .shared) {
        self.validator = validator
        self.bus = bus
    }

    /// Parse and validate a package. On success returns an `InstalledExtension`
    /// in the `.validated` state, ready for the engine to register and mark ready.
    public func prepare(from source: PackageSource, existingIDs: Set<String>) throws -> InstalledExtension {
        // Parse — a manifest failure here is reported without an extension logger
        // because we do not yet know the extension id.
        let manifestData = try source.manifestData()
        let manifest = try ManifestParser.parse(manifestData)

        let logger = RuntimeLogger(extensionID: manifest.id, bus: bus)
        logger.install("Parsed manifest", metadata: ["origin": source.origin, "version": manifest.version.description])

        // Validate.
        do {
            try validator.validate(manifest: manifest, source: source, existingIDs: existingIDs)
        } catch let error as RuntimeError {
            logger.error("Validation failed: \(error.description)")
            throw error
        }

        // Load the entry point source.
        let entryPointSource = try source.entryPointSource(named: manifest.entryPoint)

        logger.install(
            "Validated",
            metadata: [
                "capabilities": manifest.capabilities.map(\.rawValue).sorted().joined(separator: ","),
                "permissions": manifest.permissions.declared.map(\.rawValue).sorted().joined(separator: ","),
            ]
        )

        return InstalledExtension(
            manifest: manifest,
            entryPointSource: entryPointSource,
            origin: source.origin,
            logger: logger,
            state: .validated
        )
    }
}
