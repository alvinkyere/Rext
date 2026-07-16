import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// UserProfile.swift  (Rext Roadmap Phase 6 — User Platform)
//
// Local user identity. A profile scopes the per-user data (library, history,
// activity, playback) via a `profileID`, while the Universal Content Graph stays
// shared across profiles (content identity is not per-user). All profile data is
// local in this phase; the Cloud layer (Phase 7) will sync it later.
// ---------------------------------------------------------------------------

public enum UserProfileKind: String, Codable, Sendable, CaseIterable {
    case adult
    case child
    case guest

    public var title: String {
        switch self {
        case .adult: return "Adult"
        case .child: return "Child"
        case .guest: return "Guest"
        }
    }
}

/// A content maturity ceiling. Reserved for when providers expose rating
/// metadata; today it is stored and displayed, while `ParentalControls` enforces
/// via `allowedKinds` / `blockedGenres`.
public enum MaturityRating: Int, Codable, Sendable, CaseIterable, Comparable {
    case everyone = 0
    case kids = 1
    case teen = 2
    case mature = 3
    case adult = 4

    public static func < (lhs: MaturityRating, rhs: MaturityRating) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .everyone: return "Everyone"
        case .kids: return "Kids"
        case .teen: return "Teen"
        case .mature: return "Mature"
        case .adult: return "Adult"
        }
    }
}

/// Per-profile viewing preferences.
public struct ProfilePreferences: Codable, Sendable, Equatable {
    public var colorScheme: AppColorScheme
    public var autoplayNext: Bool
    public var preferredLanguage: String?

    public init(colorScheme: AppColorScheme = .system, autoplayNext: Bool = true, preferredLanguage: String? = nil) {
        self.colorScheme = colorScheme
        self.autoplayNext = autoplayNext
        self.preferredLanguage = preferredLanguage
    }
}

public enum AppColorScheme: String, Codable, Sendable, CaseIterable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Per-profile parental controls. Enforced by `ContentPolicy`.
public struct ParentalControls: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var maxRating: MaturityRating
    /// Allowed content kinds (`CatalogKind` raw values); `nil` means all kinds.
    public var allowedKinds: [String]?
    /// Canonical genres to hide.
    public var blockedGenres: [String]

    public init(isEnabled: Bool = false, maxRating: MaturityRating = .adult, allowedKinds: [String]? = nil, blockedGenres: [String] = []) {
        self.isEnabled = isEnabled
        self.maxRating = maxRating
        self.allowedKinds = allowedKinds
        self.blockedGenres = blockedGenres
    }
}

@Model
final class UserProfile {
    /// The default profile every install starts with; existing per-user rows
    /// carry this id via their column defaults, so nothing is orphaned.
    static let defaultProfileID = "default"
    static let guestProfileID = "guest"

    @Attribute(.unique) var id: String
    var name: String
    var kindRaw: String
    var avatarSymbol: String
    var colorHex: String
    var createdAt: Date

    private var preferencesData: Data
    private var parentalData: Data

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: UserProfileKind,
        avatarSymbol: String = "person.crop.circle.fill",
        colorHex: String = "#3B82F6",
        preferences: ProfilePreferences = ProfilePreferences(),
        parentalControls: ParentalControls = ParentalControls(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.avatarSymbol = avatarSymbol
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.preferencesData = (try? JSONEncoder().encode(preferences)) ?? Data()
        self.parentalData = (try? JSONEncoder().encode(parentalControls)) ?? Data()
    }

    var kind: UserProfileKind { UserProfileKind(rawValue: kindRaw) ?? .adult }
    var isGuest: Bool { kind == .guest }

    var preferences: ProfilePreferences {
        get { (try? JSONDecoder().decode(ProfilePreferences.self, from: preferencesData)) ?? ProfilePreferences() }
        set { preferencesData = (try? JSONEncoder().encode(newValue)) ?? preferencesData }
    }

    var parentalControls: ParentalControls {
        get { (try? JSONDecoder().decode(ParentalControls.self, from: parentalData)) ?? ParentalControls() }
        set { parentalData = (try? JSONEncoder().encode(newValue)) ?? parentalData }
    }
}
