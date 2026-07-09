import Foundation

// ---------------------------------------------------------------------------
// RuntimeVersion.swift  (Runtime SDK v1)
//
// The single source of truth for the versions the host advertises. Extensions
// declare the `sdkVersion` they were built against and a `minimumRuntimeVersion`
// they require; the validator compares those against these constants so an
// extension built for a newer platform is rejected cleanly rather than failing
// at runtime.
// ---------------------------------------------------------------------------

public nonisolated enum RuntimeVersion {
    /// The version of the running Runtime host/engine.
    public static let current = SemanticVersion(major: 1, minor: 0, patch: 0)

    /// The version of the SDK contract this host implements. An extension whose
    /// `sdkVersion` has a different major, or is newer than this, is incompatible.
    public static let sdk = SemanticVersion(major: 1, minor: 0, patch: 0)
}
