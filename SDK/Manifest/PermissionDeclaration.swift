import Foundation

// ---------------------------------------------------------------------------
// PermissionDeclaration.swift  (Runtime SDK v1)
//
// Every extension must explicitly declare the permissions it needs. The runtime
// enforces these *entirely in Swift* — a permission that is not declared is not
// available, and the enforcement is total by construction:
//
//   • No `network` declaration  ⇒ empty allowlist  ⇒ every Runtime.request is
//     blocked with PERMISSION_DENIED.
//   • No `storage` declaration  ⇒ maxBytes == 0     ⇒ every Runtime.storage.set
//     is rejected with STORAGE_QUOTA_EXCEEDED.
//
// JavaScript can never grant itself a permission; it can only ask, and the host
// decides. `notifications` and `downloads` are reserved v1 vocabulary that
// authors may declare now (enforcement lands in a later milestone).
// ---------------------------------------------------------------------------

/// The set of known permission kinds. Used for declaration lookups and for
/// producing precise `RuntimeError.permissionNotDeclared` / `.unknownPermission`.
public nonisolated enum Permission: String, Codable, Sendable, CaseIterable, Hashable {
    case network
    case storage
    case cache
    case cookies
    case backgroundTasks
    case notifications   // reserved (future enforcement)
    case downloads       // reserved (future enforcement)
}

public nonisolated struct PermissionDeclaration: Sendable, Codable, Hashable {
    public let network: NetworkPermission?
    public let storage: StoragePermission?
    public let cache: CachePermission?
    public let cookies: Bool?
    public let backgroundTasks: Bool?
    public let notifications: Bool?
    public let downloads: Bool?

    public init(
        network: NetworkPermission? = nil,
        storage: StoragePermission? = nil,
        cache: CachePermission? = nil,
        cookies: Bool? = nil,
        backgroundTasks: Bool? = nil,
        notifications: Bool? = nil,
        downloads: Bool? = nil
    ) {
        self.network = network
        self.storage = storage
        self.cache = cache
        self.cookies = cookies
        self.backgroundTasks = backgroundTasks
        self.notifications = notifications
        self.downloads = downloads
    }

    /// Network access scoped to an explicit host allowlist. Redirects to hosts
    /// outside this list are re-checked and blocked by the bridge.
    public nonisolated struct NetworkPermission: Sendable, Codable, Hashable {
        public let domains: [String]
        public let allowUserConfiguredHost: Bool?

        public init(domains: [String], allowUserConfiguredHost: Bool? = nil) {
            self.domains = domains
            self.allowUserConfiguredHost = allowUserConfiguredHost
        }
    }

    /// Namespaced key/value storage bounded by a hard byte budget.
    public nonisolated struct StoragePermission: Sendable, Codable, Hashable {
        public let maxBytes: Int

        public init(maxBytes: Int) {
            self.maxBytes = maxBytes
        }
    }

    /// HTTP response cache budget (declaration only in v1).
    public nonisolated struct CachePermission: Sendable, Codable, Hashable {
        public let maxBytes: Int

        public init(maxBytes: Int) {
            self.maxBytes = maxBytes
        }
    }

    /// The concrete set of permissions this manifest declares, used for gating.
    public var declared: Set<Permission> {
        var result: Set<Permission> = []
        if network != nil { result.insert(.network) }
        if storage != nil { result.insert(.storage) }
        if cache != nil { result.insert(.cache) }
        if cookies == true { result.insert(.cookies) }
        if backgroundTasks == true { result.insert(.backgroundTasks) }
        if notifications == true { result.insert(.notifications) }
        if downloads == true { result.insert(.downloads) }
        return result
    }

    public func declares(_ permission: Permission) -> Bool {
        declared.contains(permission)
    }
}
