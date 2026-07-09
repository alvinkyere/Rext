import Foundation

// ---------------------------------------------------------------------------
// ExtensionCategory.swift  (Runtime SDK v1)
//
// A coarse classification used for organizing extensions in a future gallery /
// repository UI. Decoding is intentionally lenient: an unrecognized category
// maps to `.other` rather than failing the whole manifest, so new categories can
// be introduced server-side without breaking older runtimes (forward
// compatibility, Priority 2).
// ---------------------------------------------------------------------------

public nonisolated enum ExtensionCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case media
    case music
    case books
    case news
    case utility
    case developer
    case other

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExtensionCategory(rawValue: raw) ?? .other
    }
}
