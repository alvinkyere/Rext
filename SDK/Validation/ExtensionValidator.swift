import Foundation

// ---------------------------------------------------------------------------
// ExtensionValidator.swift  (Runtime SDK v1, Priority 7)
//
// The gate every extension must pass before it can execute. Parsing
// (ManifestParser) has already guaranteed the manifest is structurally valid and
// that its versions, capabilities, and permission keys are well-formed; the
// validator adds the *contextual* checks that need the host and the package:
//
//   • the declared entry point actually exists in the package,
//   • the extension's SDK version is compatible with this host,
//   • the host satisfies the extension's minimum runtime version,
//   • the id is not already installed.
//
// Every failure is a typed `RuntimeError`; nothing is skipped silently.
// ---------------------------------------------------------------------------

public nonisolated struct ExtensionValidator: Sendable {
    public let hostRuntimeVersion: SemanticVersion
    public let hostSDKVersion: SemanticVersion

    public init(
        hostRuntimeVersion: SemanticVersion = RuntimeVersion.current,
        hostSDKVersion: SemanticVersion = RuntimeVersion.sdk
    ) {
        self.hostRuntimeVersion = hostRuntimeVersion
        self.hostSDKVersion = hostSDKVersion
    }

    public func validate(
        manifest: ExtensionManifest,
        source: PackageSource,
        existingIDs: Set<String>
    ) throws {
        // Entry point must exist in the package.
        guard source.fileExists(manifest.entryPoint) else {
            throw RuntimeError.entryPointMissing(expected: manifest.entryPoint)
        }

        // SDK compatibility: same major, host at least as new as the target SDK.
        guard hostSDKVersion.isCompatible(withMinimum: manifest.sdkVersion) else {
            throw RuntimeError.sdkIncompatible(required: manifest.sdkVersion, current: hostSDKVersion)
        }

        // Runtime compatibility: host must meet the declared minimum.
        guard hostRuntimeVersion.isCompatible(withMinimum: manifest.minimumRuntimeVersion) else {
            throw RuntimeError.runtimeIncompatible(required: manifest.minimumRuntimeVersion, current: hostRuntimeVersion)
        }

        // Ids are unique across installed extensions.
        guard !existingIDs.contains(manifest.id) else {
            throw RuntimeError.duplicateExtensionID(manifest.id)
        }
    }
}
