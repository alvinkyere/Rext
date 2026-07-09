import Foundation

// ---------------------------------------------------------------------------
// RuntimeError.swift  (Runtime SDK v1, Priority 7)
//
// The strongly-typed error surface for the *platform*: installing, parsing,
// validating, and resolving extensions. It is deliberately separate from
// `ConnectorError`, which represents failures at the JavaScript execution
// boundary (blocked host, timeout, bad return shape). Nothing in the runtime
// fails silently — every rejected operation throws one of these.
//
//   RuntimeError   → lifecycle / packaging / validation problems
//   ConnectorError → runtime execution problems (kept as-is, caught by the UI)
// ---------------------------------------------------------------------------

public nonisolated enum RuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    /// No `manifest.json` was found in the package.
    case manifestMissing(packageOrigin: String)
    /// The manifest file exists but could not be read or is not valid JSON.
    case manifestUnreadable(reason: String)
    /// A manifest field is present but malformed.
    case manifestInvalid(field: String, reason: String)
    /// A required manifest field is absent.
    case missingRequiredField(String)
    /// A version field is not valid semver.
    case invalidVersion(field: String, value: String)
    /// The declared entry point file does not exist in the package.
    case entryPointMissing(expected: String)
    /// The extension targets an SDK version this host cannot satisfy.
    case sdkIncompatible(required: SemanticVersion, current: SemanticVersion)
    /// The extension requires a newer Runtime host than this one.
    case runtimeIncompatible(required: SemanticVersion, current: SemanticVersion)
    /// An extension with this id is already installed.
    case duplicateExtensionID(String)
    /// The manifest declared a permission the SDK does not recognize.
    case unknownPermission(String)
    /// The manifest declared a capability the SDK does not recognize.
    case unknownCapability(String)
    /// An operation required a permission the extension did not declare.
    case permissionNotDeclared(Permission)
    /// An operation required a capability the extension did not declare.
    case capabilityNotSupported(Capability)
    /// No extension with the given id is installed.
    case notInstalled(id: String)
    /// Execution reached the JavaScript boundary and failed there.
    case executionFailed(ConnectorError)
    /// A repository index could not be fetched.
    case repositoryUnreachable(url: String)
    /// A package download failed.
    case downloadFailed(reason: String)
    /// A downloaded package's checksum did not match the repository's record.
    case checksumMismatch(expected: String, actual: String)
    /// A repository was reached but is not a valid/compatible Rext repository.
    case repositoryIncompatible(String)

    public var description: String {
        switch self {
        case .manifestMissing(let origin):
            return "No manifest.json found in package at \(origin)"
        case .manifestUnreadable(let reason):
            return "Manifest could not be read: \(reason)"
        case .manifestInvalid(let field, let reason):
            return "Manifest field '\(field)' is invalid: \(reason)"
        case .missingRequiredField(let field):
            return "Manifest is missing required field '\(field)'"
        case .invalidVersion(let field, let value):
            return "Manifest field '\(field)' is not a valid version: '\(value)'"
        case .entryPointMissing(let expected):
            return "Entry point '\(expected)' does not exist in the package"
        case .sdkIncompatible(let required, let current):
            return "Extension targets SDK \(required), which is incompatible with SDK \(current)"
        case .runtimeIncompatible(let required, let current):
            return "Extension requires Runtime \(required) or newer; this host is \(current)"
        case .duplicateExtensionID(let id):
            return "An extension with id '\(id)' is already installed"
        case .unknownPermission(let raw):
            return "Unknown permission '\(raw)'"
        case .unknownCapability(let raw):
            return "Unknown capability '\(raw)'"
        case .permissionNotDeclared(let permission):
            return "Operation requires the '\(permission.rawValue)' permission, which was not declared"
        case .capabilityNotSupported(let capability):
            return "This extension does not support the '\(capability.rawValue)' capability"
        case .notInstalled(let id):
            return "No extension with id '\(id)' is installed"
        case .executionFailed(let error):
            return "Execution failed: \(error.description)"
        case .repositoryUnreachable(let url):
            return "Repository could not be reached at \(url)"
        case .downloadFailed(let reason):
            return "Package download failed: \(reason)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch — expected \(expected), got \(actual)"
        case .repositoryIncompatible(let reason):
            return reason
        }
    }

    /// A best-effort projection onto `ConnectorError` so lifecycle failures can
    /// flow through UI code that already handles the execution error type.
    public var asConnectorError: ConnectorError {
        switch self {
        case .executionFailed(let error):
            return error
        case .permissionNotDeclared:
            return ConnectorError(.permissionDenied, description)
        case .capabilityNotSupported, .notInstalled:
            return ConnectorError(.notFound, description)
        default:
            return ConnectorError(.unknown, description)
        }
    }
}
