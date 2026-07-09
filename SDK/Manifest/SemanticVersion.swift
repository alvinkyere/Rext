import Foundation

// ---------------------------------------------------------------------------
// SemanticVersion.swift  (Runtime SDK v1)
//
// A strict Semantic Versioning 2.0.0 value type used for every version field in
// the SDK: an extension's `version`, the `sdkVersion` it targets, and the
// `minimumRuntimeVersion` it requires. Parsing is total and non-throwing at the
// call site (`init?`) so the manifest layer can surface a precise validation
// error rather than crashing on malformed input.
//
// Build metadata (`+meta`) is accepted and ignored for comparison, matching the
// semver spec. Pre-release identifiers participate in ordering.
// ---------------------------------------------------------------------------

public nonisolated struct SemanticVersion: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Dot-separated pre-release identifiers, e.g. `["beta", "1"]` for `1.0.0-beta.1`.
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parse a semver string like `1.2.3`, `1.2.3-beta.1`, or `1.2.3+build.5`.
    /// Returns `nil` for anything that is not three dot-separated non-negative
    /// integers (with an optional pre-release / build-metadata suffix).
    public init?(parsing raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Strip build metadata (everything after the first '+'); it is ignored.
        let withoutBuild = trimmed.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]

        // Split off the pre-release segment (everything after the first '-').
        let coreAndPre = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = coreAndPre[0]
        let preSegment = coreAndPre.count > 1 ? String(coreAndPre[1]) : ""

        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part), value >= 0 else {
                return nil
            }
            numbers.append(value)
        }

        var preIdentifiers: [String] = []
        if !preSegment.isEmpty {
            for identifier in preSegment.split(separator: ".", omittingEmptySubsequences: false) {
                guard !identifier.isEmpty else { return nil }
                preIdentifiers.append(String(identifier))
            }
        }

        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2], prerelease: preIdentifiers)
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    /// `true` when the receiver satisfies the given minimum (same major, and at
    /// least as new). Used for `minimumRuntimeVersion` / `sdkVersion` checks.
    public func isCompatible(withMinimum minimum: SemanticVersion) -> Bool {
        major == minimum.major && self >= minimum
    }

    // MARK: Comparable (semver precedence)

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // A version with a pre-release has lower precedence than one without.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false   // lhs is a release, rhs is pre-release
        case (false, true): return true    // lhs is pre-release, rhs is release
        case (false, false): break
        }

        for (l, r) in zip(lhs.prerelease, rhs.prerelease) where l != r {
            switch (Int(l), Int(r)) {
            case let (l?, r?): return l < r
            case (_?, nil): return true      // numeric identifiers rank lower than alphanumeric
            case (nil, _?): return false
            case (nil, nil): return l < r
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    // MARK: Codable (encoded as a plain string)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = SemanticVersion(parsing: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(raw)' is not a valid semantic version (expected MAJOR.MINOR.PATCH)"
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
