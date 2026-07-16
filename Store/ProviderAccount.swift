import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// ProviderAccount.swift  (Rext — Provider Accounts)
//
// The device-level connection record for one installed provider. Providers are
// the streaming services the user connects to Rext; this tracks their connection
// state, when they connected, and any last error — while the actual session
// token lives in the Keychain (TokenStore), never here.
// ---------------------------------------------------------------------------

public enum ProviderConnectionState: String, Codable, Sendable, CaseIterable {
    case notInstalled
    case installed        // installed but connection not yet attempted
    case loginRequired    // needs the user to sign in
    case connecting       // web auth in progress
    case connected        // signed in and ready
    case expired          // session expired, needs re-auth
    case offline          // network unavailable
    case disabled         // user turned it off
    case error            // last operation failed (see errorDetail)

    public var title: String {
        switch self {
        case .notInstalled: return "Not Installed"
        case .installed: return "Installed"
        case .loginRequired: return "Login Required"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .expired: return "Session Expired"
        case .offline: return "Offline"
        case .disabled: return "Disabled"
        case .error: return "Error"
        }
    }

    public var systemImage: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .loginRequired, .expired: return "person.crop.circle.badge.exclamationmark"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .disabled: return "pause.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .installed, .notInstalled: return "circle.dashed"
        }
    }

    /// Whether the provider is usable for browsing/playback right now.
    public var isActive: Bool { self == .connected }
}

@Model
final class ProviderAccount {
    @Attribute(.unique) var extensionID: String
    var displayName: String
    var stateRaw: String
    var connectedAt: Date?
    var errorDetail: String?
    var isEnabled: Bool
    /// Stable identifier for this provider's isolated web-data store.
    var dataStoreID: String
    /// The signed-in account name (e.g. YouTube channel), when connected via OAuth.
    var accountName: String?

    init(
        extensionID: String,
        displayName: String,
        state: ProviderConnectionState = .installed,
        connectedAt: Date? = nil,
        isEnabled: Bool = true,
        dataStoreID: String = UUID().uuidString,
        accountName: String? = nil
    ) {
        self.extensionID = extensionID
        self.displayName = displayName
        self.stateRaw = state.rawValue
        self.connectedAt = connectedAt
        self.isEnabled = isEnabled
        self.dataStoreID = dataStoreID
        self.accountName = accountName
    }

    var state: ProviderConnectionState {
        get { ProviderConnectionState(rawValue: stateRaw) ?? .installed }
        set { stateRaw = newValue.rawValue }
    }
}
