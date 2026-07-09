import Foundation

// ---------------------------------------------------------------------------
// ExtensionManifest.swift  (Runtime SDK v1, Priority 2)
//
// The canonical, strongly-typed description of an extension. Once a package is
// installed, its manifest is the single source of truth for identity, metadata,
// the permissions it may use, and the capabilities it advertises.
//
// FORWARD COMPATIBILITY
// The decoder ignores unknown top-level keys, every non-essential field is
// optional, and `ExtensionCategory` degrades unknown values to `.other`. New
// fields can therefore be added in future SDK versions without breaking
// extensions built against — or runtimes that predate — them.
//
// Prefer parsing through `ManifestParser`, which validates raw JSON and produces
// precise `RuntimeError`s, rather than decoding this type directly.
// ---------------------------------------------------------------------------

public nonisolated struct ExtensionManifest: Sendable, Codable, Hashable, Identifiable {
    /// Reverse-DNS unique identifier, e.g. `com.runtime.podcast-rss`.
    public let id: String
    /// Human-readable name shown in the UI.
    public let displayName: String
    /// The extension's own version.
    public let version: SemanticVersion
    /// The SDK contract version this extension targets.
    public let sdkVersion: SemanticVersion
    /// The minimum Runtime host version required to load this extension.
    public let minimumRuntimeVersion: SemanticVersion
    public let author: String?
    public let description: String?
    public let website: String?
    public let repository: String?
    public let category: ExtensionCategory
    /// Package-relative path to the icon asset, e.g. `icon.png`.
    public let icon: String?
    /// Package-relative path to the JavaScript entry point, e.g. `main.js`.
    public let entryPoint: String
    public let permissions: PermissionDeclaration
    public let capabilities: Set<Capability>

    public init(
        id: String,
        displayName: String,
        version: SemanticVersion,
        sdkVersion: SemanticVersion,
        minimumRuntimeVersion: SemanticVersion,
        author: String? = nil,
        description: String? = nil,
        website: String? = nil,
        repository: String? = nil,
        category: ExtensionCategory = .other,
        icon: String? = nil,
        entryPoint: String,
        permissions: PermissionDeclaration,
        capabilities: Set<Capability>
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.sdkVersion = sdkVersion
        self.minimumRuntimeVersion = minimumRuntimeVersion
        self.author = author
        self.description = description
        self.website = website
        self.repository = repository
        self.category = category
        self.icon = icon
        self.entryPoint = entryPoint
        self.permissions = permissions
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, version, sdkVersion, minimumRuntimeVersion
        case author, description, website, repository, category, icon
        case entryPoint, permissions, capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        version = try container.decode(SemanticVersion.self, forKey: .version)
        sdkVersion = try container.decode(SemanticVersion.self, forKey: .sdkVersion)
        minimumRuntimeVersion = try container.decode(SemanticVersion.self, forKey: .minimumRuntimeVersion)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        repository = try container.decodeIfPresent(String.self, forKey: .repository)
        category = try container.decodeIfPresent(ExtensionCategory.self, forKey: .category) ?? .other
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        entryPoint = try container.decode(String.self, forKey: .entryPoint)
        permissions = try container.decode(PermissionDeclaration.self, forKey: .permissions)
        capabilities = try container.decode(Set<Capability>.self, forKey: .capabilities)
    }

    public func supports(_ capability: Capability) -> Bool {
        capabilities.contains(capability)
    }
}
