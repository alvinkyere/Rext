import Foundation

// ---------------------------------------------------------------------------
// ConnectorError.swift  (doc 03 §7)
//
// Every failure a connector produces — whether it throws a structured error, a
// plain JS Error, or the bridge synthesizes one (blocked domain, timeout, bad
// return shape) — is normalized to this single type before host code sees it.
// ---------------------------------------------------------------------------

public enum ConnectorErrorCode: String, Codable, Sendable {
    case notFound = "NOT_FOUND"
    case permissionDenied = "PERMISSION_DENIED"
    case timeout = "TIMEOUT"
    case invalidResponse = "INVALID_RESPONSE"
    case storageQuotaExceeded = "STORAGE_QUOTA_EXCEEDED"
    case upstreamError = "UPSTREAM_ERROR"
    case authRequired = "AUTH_REQUIRED"
    case unknown = "UNKNOWN"
}

public struct ConnectorError: Error, CustomStringConvertible, Sendable, Equatable {
    public let code: ConnectorErrorCode
    public let message: String
    public let cause: String?

    public init(_ code: ConnectorErrorCode, _ message: String, cause: String? = nil) {
        self.code = code
        self.message = message
        self.cause = cause
    }

    public var description: String { "[\(code.rawValue)] \(message)" }

    /// Map an arbitrary JS thrown value (already read as a dictionary/string) to
    /// a ConnectorError. A JS object carrying a recognized `code` keeps it;
    /// anything else becomes `.unknown` with the original message preserved.
    public static func from(jsThrown value: Any?) -> ConnectorError {
        if let dict = value as? [String: Any],
           let raw = dict["code"] as? String,
           let code = ConnectorErrorCode(rawValue: raw) {
            let msg = (dict["message"] as? String) ?? raw
            return ConnectorError(code, msg, cause: dict["stack"] as? String)
        }
        if let dict = value as? [String: Any] {
            return ConnectorError(.unknown, (dict["message"] as? String) ?? "Unknown error",
                                  cause: dict["stack"] as? String)
        }
        return ConnectorError(.unknown, (value as? String) ?? "Unknown error")
    }
}
