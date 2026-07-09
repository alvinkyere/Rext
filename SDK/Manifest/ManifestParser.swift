import Foundation

// ---------------------------------------------------------------------------
// ManifestParser.swift  (Runtime SDK v1, Priority 2 & 7)
//
// Turns raw manifest bytes into a strongly-typed `ExtensionManifest`, producing
// a precise `RuntimeError` for every failure mode rather than a generic decoding
// message. It validates the raw JSON first (required fields, version formats,
// known capabilities/permissions) so the errors name the offending field, then
// decodes into the typed model. Nothing here fails silently.
// ---------------------------------------------------------------------------

public nonisolated enum ManifestParser {

    /// Required top-level keys. Absence yields `.missingRequiredField`.
    private static let requiredFields = [
        "id", "displayName", "version", "sdkVersion",
        "minimumRuntimeVersion", "entryPoint", "permissions", "capabilities",
    ]

    private static let versionFields = ["version", "sdkVersion", "minimumRuntimeVersion"]

    public static func parse(_ data: Data) throws -> ExtensionManifest {
        // 1. Must be a JSON object.
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw RuntimeError.manifestUnreadable(reason: error.localizedDescription)
        }
        guard let object = json as? [String: Any] else {
            throw RuntimeError.manifestUnreadable(reason: "Top-level manifest value must be a JSON object")
        }

        // 2. Required fields present.
        for field in requiredFields where object[field] == nil {
            throw RuntimeError.missingRequiredField(field)
        }

        // 3. Version fields are valid semver.
        for field in versionFields {
            guard let raw = object[field] as? String else {
                throw RuntimeError.manifestInvalid(field: field, reason: "expected a version string")
            }
            guard SemanticVersion(parsing: raw) != nil else {
                throw RuntimeError.invalidVersion(field: field, value: raw)
            }
        }

        // 4. Capabilities are an array of recognized strings.
        guard let rawCapabilities = object["capabilities"] as? [Any] else {
            throw RuntimeError.manifestInvalid(field: "capabilities", reason: "expected an array of capability strings")
        }
        for value in rawCapabilities {
            guard let raw = value as? String else {
                throw RuntimeError.manifestInvalid(field: "capabilities", reason: "capability values must be strings")
            }
            guard Capability(rawValue: raw) != nil else {
                throw RuntimeError.unknownCapability(raw)
            }
        }

        // 5. Permission keys are recognized (unknown keys are rejected, not ignored).
        guard let rawPermissions = object["permissions"] as? [String: Any] else {
            throw RuntimeError.manifestInvalid(field: "permissions", reason: "expected an object")
        }
        let knownPermissions = Set(Permission.allCases.map(\.rawValue))
        for key in rawPermissions.keys where !knownPermissions.contains(key) {
            throw RuntimeError.unknownPermission(key)
        }

        // 6. Decode into the typed model, translating any residual decode error.
        do {
            return try JSONDecoder().decode(ExtensionManifest.self, from: data)
        } catch let error as RuntimeError {
            throw error
        } catch let DecodingError.keyNotFound(key, _) {
            throw RuntimeError.missingRequiredField(key.stringValue)
        } catch let DecodingError.typeMismatch(_, context) {
            throw RuntimeError.manifestInvalid(
                field: context.codingPath.last?.stringValue ?? "manifest",
                reason: context.debugDescription
            )
        } catch let DecodingError.valueNotFound(_, context) {
            throw RuntimeError.manifestInvalid(
                field: context.codingPath.last?.stringValue ?? "manifest",
                reason: context.debugDescription
            )
        } catch let DecodingError.dataCorrupted(context) {
            throw RuntimeError.manifestInvalid(
                field: context.codingPath.last?.stringValue ?? "manifest",
                reason: context.debugDescription
            )
        } catch {
            throw RuntimeError.manifestUnreadable(reason: "\(error)")
        }
    }
}
