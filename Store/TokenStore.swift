import Foundation
import Security

// ---------------------------------------------------------------------------
// TokenStore.swift  (Rext — Provider Accounts)
//
// Secure, per-provider token storage. Rext never collects credentials: a
// provider authenticates the user inside its own web view, and only the
// resulting provider-issued session token is persisted here — in the Keychain,
// isolated by provider id. The protocol lets tests use an in-memory store.
// ---------------------------------------------------------------------------

public protocol TokenStore: Sendable {
    func save(_ token: String, for providerID: String)
    func token(for providerID: String) -> String?
    func delete(for providerID: String)
}

/// Keychain-backed token storage (generic password items, one per provider).
public struct KeychainTokenStore: TokenStore {
    private let service: String

    public init(service: String = "com.rext.provider-tokens") {
        self.service = service
    }

    public func save(_ token: String, for providerID: String) {
        delete(for: providerID)
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    public func token(for providerID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(for providerID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory token store for tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String] = [:]

    public init() {}

    public func save(_ token: String, for providerID: String) {
        lock.lock(); defer { lock.unlock() }
        tokens[providerID] = token
    }

    public func token(for providerID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return tokens[providerID]
    }

    public func delete(for providerID: String) {
        lock.lock(); defer { lock.unlock() }
        tokens[providerID] = nil
    }
}
