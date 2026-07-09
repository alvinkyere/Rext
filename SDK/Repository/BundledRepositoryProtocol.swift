import Foundation

// ---------------------------------------------------------------------------
// BundledRepositoryProtocol.swift  (Rext Extension Platform — local sample repo)
//
// Serves a fully-working sample repository offline, with no server and no extra
// bundled files. `SampleRepository` derives an ExtensionPackageDocument from the
// already-bundled PodcastRSS package, computes its real SHA-256, and synthesizes a
// `repository.json` that references it. `BundledRepositoryURLProtocol` serves both
// over a custom `rext-repo://` scheme, so `RepositoryService` exercises the real
// fetch → download → checksum-verify → install pipeline end to end.
//
// The encoded bytes are computed once and cached, so the checksum recorded in the
// index always matches the bytes served for download.
// ---------------------------------------------------------------------------

public nonisolated enum SampleRepository {
    public static let repositoryURLString = "rext-repo://local/repository.json"
    public static let packageURLString = "rext-repo://local/packages/com.runtime.podcast-rss"

    public struct Content: Sendable {
        public let repositoryData: Data
        public let packageData: Data
    }

    /// Built once from the bundled PodcastRSS package; `nil` if it isn't bundled.
    public static let content: Content? = build()

    /// A URLSession configuration whose requests to `rext-repo://` are served
    /// locally, while normal `http(s)` requests keep working (custom protocol is
    /// prepended, not substituted for the defaults).
    public static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BundledRepositoryURLProtocol.self] + (config.protocolClasses ?? [])
        return config
    }

    private static func build() -> Content? {
        let source = BundlePackageSource()
        guard let manifestData = try? source.manifestData(),
              let manifest = try? ManifestParser.parse(manifestData),
              let entryPoint = try? source.entryPointSource(named: manifest.entryPoint) else {
            return nil
        }

        let document = ExtensionPackageDocument(manifest: manifest, entryPoint: entryPoint)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let packageData = try? encoder.encode(document) else { return nil }

        let checksum = RepositoryChecksum(algorithm: "sha256", value: RepositoryService.sha256Hex(packageData))
        let repository = Repository(
            metadata: RepositoryMetadata(
                name: "Rext Official (Sample)",
                description: "Bundled sample repository served locally.",
                url: repositoryURLString
            ),
            publisher: Publisher(id: "com.rext.official", displayName: "Rext Official", verified: true),
            extensions: [
                ExtensionListing(
                    id: manifest.id,
                    displayName: manifest.displayName,
                    description: manifest.description,
                    category: manifest.category,
                    author: manifest.author,
                    versions: [
                        RepositoryVersion(
                            version: manifest.version,
                            downloadURL: packageURLString,
                            checksum: checksum,
                            minimumRuntimeVersion: manifest.minimumRuntimeVersion
                        )
                    ]
                )
            ]
        )
        guard let repositoryData = try? encoder.encode(repository) else { return nil }
        return Content(repositoryData: repositoryData, packageData: packageData)
    }
}

public nonisolated final class BundledRepositoryURLProtocol: URLProtocol {
    public override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "rext-repo"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        guard let url = request.url, let content = SampleRepository.content else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        let data: Data
        switch url.absoluteString {
        case SampleRepository.repositoryURLString: data = content.repositoryData
        case SampleRepository.packageURLString: data = content.packageData
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}
}
