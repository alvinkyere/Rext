import Foundation

// ---------------------------------------------------------------------------
// Capability.swift  (Runtime SDK v1)
//
// A capability is an operation an extension declares it can perform. The host
// never assumes an extension supports an operation — it must be listed in the
// manifest's `capabilities`. The engine gates execution on these declarations
// (see RuntimeEngine) and the UI can adapt to them without hard-coding which
// extensions do what.
//
// `downloads`, `recommendations`, `subtitles`, and `authentication` are part of
// the stable v1 vocabulary so extension authors can target them now; only the
// operations the runtime currently executes (search/details/streams) are wired
// to methods today.
// ---------------------------------------------------------------------------

public nonisolated enum Capability: String, Codable, Sendable, CaseIterable, Hashable {
    case search
    case details
    case episodes
    case streams
    case downloads
    case recommendations
    case subtitles
    case authentication

    /// Decodes leniently: an unrecognized capability string does not crash
    /// decoding here — `ManifestParser` validates the raw set and raises
    /// `RuntimeError.unknownCapability` with the offending value.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Capability(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown capability '\(raw)'"
            )
        }
        self = value
    }
}
