import Foundation

// ---------------------------------------------------------------------------
// ExtensionRegistry.swift  (Runtime SDK v1, Priority 9)
//
// The in-memory catalog of installed extensions, keyed by id. A pure value type
// so the owning engine actor can mutate it without additional synchronization.
// Enforces id uniqueness — installing a duplicate id is an error, never a silent
// overwrite.
// ---------------------------------------------------------------------------

public nonisolated struct ExtensionRegistry: Sendable {
    private var extensionsByID: [String: InstalledExtension] = [:]

    public init() {}

    public var all: [InstalledExtension] {
        extensionsByID.values.sorted { $0.manifest.displayName < $1.manifest.displayName }
    }

    public var ids: Set<String> {
        Set(extensionsByID.keys)
    }

    public func contains(_ id: String) -> Bool {
        extensionsByID[id] != nil
    }

    public func get(_ id: String) -> InstalledExtension? {
        extensionsByID[id]
    }

    /// Insert a new extension. Throws `.duplicateExtensionID` if the id is taken.
    public mutating func register(_ ext: InstalledExtension) throws {
        guard extensionsByID[ext.id] == nil else {
            throw RuntimeError.duplicateExtensionID(ext.id)
        }
        extensionsByID[ext.id] = ext
    }

    /// Replace an existing record (e.g. to advance its lifecycle state).
    public mutating func update(_ ext: InstalledExtension) {
        extensionsByID[ext.id] = ext
    }

    public mutating func remove(_ id: String) {
        extensionsByID.removeValue(forKey: id)
    }

    public mutating func removeAll() {
        extensionsByID.removeAll()
    }
}
