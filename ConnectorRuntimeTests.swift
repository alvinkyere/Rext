import Testing
import Foundation
import SwiftData
@testable import Runtime

// ---------------------------------------------------------------------------
// ConnectorRuntimeTests.swift  (Runtime SDK v1)
//
// Exercises the full SDK contract end-to-end: manifest parsing & validation,
// semantic versioning, the package installer, capability gating, permission
// enforcement (network allowlist + storage quota), execution against a mocked
// network, and the repository models. Network is stubbed by FixtureURLProtocol,
// so every test is deterministic and offline.
// ---------------------------------------------------------------------------

// MARK: - Fixtures & helpers

/// The golden connector body, mirroring Extensions/PodcastRSS.runtime/main.js.
private let goldenConnectorJS = """
(function (g) {
  "use strict";
  var API = "https://api.example-podcasts.com";
  function fail(code, message) { var e = new Error(message); e.code = code; return e; }
  async function getJSON(url) {
    var res = await Runtime.request({ url: url });
    if (res.status === 404) throw fail("NOT_FOUND", "Resource not found");
    if (res.status === 401 || res.status === 403) throw fail("AUTH_REQUIRED", "Auth required");
    if (res.status >= 400) throw fail("UPSTREAM_ERROR", "HTTP " + res.status);
    try { return JSON.parse(res.body); } catch (_) { throw fail("INVALID_RESPONSE", "Non-JSON body"); }
  }
  g.connectorInstance = {
    async search(query, page) {
      var data = await getJSON(API + "/search?q=" + encodeURIComponent(query) + "&page=" + (page || 1));
      await Runtime.storage.set("lastQuery", String(query));
      return (data.results || []).map(function (r) {
        return { id: r.id, title: r.title, subtitle: r.author, artworkUrl: r.artwork,
                 kind: "podcast", metadata: { episodeCount: r.episodeCount } };
      });
    },
    async getDetails(id) {
      var data = await getJSON(API + "/show/" + encodeURIComponent(id));
      return {
        id: data.id, title: data.title, subtitle: data.author, artworkUrl: data.artwork,
        backdropUrl: data.artwork, kind: "podcast",
        metadata: { overview: data.description || "" },
        episodes: (data.episodes || []).map(function (e) {
          return { id: e.id, title: e.title, subtitle: null, artworkUrl: data.artwork,
                   kind: "episode", metadata: { number: e.number, durationSec: e.durationSec } };
        })
      };
    },
    async getStreams(itemId, episodeId) {
      if (!episodeId) throw fail("NOT_FOUND", "episode id required");
      var data = await getJSON(API + "/episode/" + encodeURIComponent(episodeId) + "/stream");
      if (!data.streamUrl) throw fail("NOT_FOUND", "no stream");
      return [{ id: "audio-" + episodeId, url: data.streamUrl,
                quality: data.bitrate ? data.bitrate + " kbps" : null, format: "mp3", metadata: null }];
    }
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
"""

private func manifestData(
    id: String = "com.test.sample",
    capabilities: [String] = ["search", "details", "streams"],
    networkDomains: [String]? = ["api.example-podcasts.com"],
    storageMaxBytes: Int? = 65536,
    sdkVersion: String = "1.0.0",
    minimumRuntimeVersion: String = "1.0.0",
    entryPoint: String = "main.js",
    overrides: [String: Any] = [:]
) -> Data {
    var permissions: [String: Any] = [:]
    if let networkDomains {
        permissions["network"] = ["domains": networkDomains, "allowUserConfiguredHost": false]
    }
    if let storageMaxBytes {
        permissions["storage"] = ["maxBytes": storageMaxBytes]
    }
    var object: [String: Any] = [
        "id": id,
        "displayName": "Sample Extension",
        "version": "1.0.0",
        "sdkVersion": sdkVersion,
        "minimumRuntimeVersion": minimumRuntimeVersion,
        "author": "Test",
        "category": "media",
        "entryPoint": entryPoint,
        "permissions": permissions,
        "capabilities": capabilities,
    ]
    for (key, value) in overrides { object[key] = value }
    // Force-unwrap avoided: a malformed test dictionary should fail loudly here.
    return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

/// Writes a package (manifest.json + entry point) into a fresh temp directory.
private func writePackage(manifest: Data, js: String = goldenConnectorJS, entryFileName: String = "main.js") throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("pkg-\(UUID().uuidString).runtime", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try manifest.write(to: dir.appendingPathComponent("manifest.json"))
    try Data(js.utf8).write(to: dir.appendingPathComponent(entryFileName))
    return dir
}

private func makeEngine() -> RuntimeEngine {
    RuntimeEngine(sessionConfiguration: FixtureURLProtocol.sessionConfiguration())
}

/// Installs the golden package into a fresh engine and returns both.
private func installedEngine(manifest: Data = manifestData(), js: String = goldenConnectorJS) async throws -> (RuntimeEngine, String) {
    PodcastRSSFixtures.registerAll()
    let engine = makeEngine()
    let dir = try writePackage(manifest: manifest, js: js)
    let installed = try await engine.install(from: DirectoryPackageSource(directory: dir))
    return (engine, installed.id)
}

// MARK: - Semantic version

@Test func semanticVersionParsingAndComparison() throws {
    let v = try #require(SemanticVersion(parsing: "1.2.3"))
    #expect(v.major == 1 && v.minor == 2 && v.patch == 3)
    #expect(SemanticVersion(parsing: "1.0") == nil)
    #expect(SemanticVersion(parsing: "x.y.z") == nil)

    let a = try #require(SemanticVersion(parsing: "1.0.0"))
    let b = try #require(SemanticVersion(parsing: "1.2.0"))
    #expect(a < b)
    #expect(b.isCompatible(withMinimum: a))
    #expect(!a.isCompatible(withMinimum: b))

    let pre = try #require(SemanticVersion(parsing: "1.0.0-beta.1"))
    #expect(pre < a) // pre-release precedes the release
    #expect(pre.description == "1.0.0-beta.1")
}

// MARK: - Manifest parser

@Test func manifestParserValidManifest() throws {
    let manifest = try ManifestParser.parse(manifestData())
    #expect(manifest.id == "com.test.sample")
    #expect(manifest.capabilities.contains(.search))
    #expect(manifest.permissions.declares(.network))
    #expect(manifest.permissions.declares(.storage))
    #expect(manifest.version == SemanticVersion(major: 1, minor: 0, patch: 0))
}

@Test func manifestParserMissingRequiredField() {
    // A manifest missing `displayName` entirely.
    let missing = try? JSONSerialization.data(withJSONObject: [
        "id": "x", "version": "1.0.0", "sdkVersion": "1.0.0",
        "minimumRuntimeVersion": "1.0.0", "entryPoint": "main.js",
        "permissions": [:], "capabilities": [],
    ])
    do {
        _ = try ManifestParser.parse(missing ?? Data())
        Issue.record("Expected missingRequiredField")
    } catch let error as RuntimeError {
        guard case .missingRequiredField("displayName") = error else {
            Issue.record("Wrong error: \(error)"); return
        }
    } catch { Issue.record("Unexpected error type: \(error)") }
}

@Test func manifestParserInvalidVersion() {
    do {
        _ = try ManifestParser.parse(manifestData(overrides: ["version": "1.x"]))
        Issue.record("Expected invalidVersion")
    } catch let error as RuntimeError {
        guard case .invalidVersion(let field, _) = error, field == "version" else {
            Issue.record("Wrong error: \(error)"); return
        }
    } catch { Issue.record("Unexpected error type: \(error)") }
}

@Test func manifestParserUnknownCapability() {
    do {
        _ = try ManifestParser.parse(manifestData(capabilities: ["search", "teleport"]))
        Issue.record("Expected unknownCapability")
    } catch let error as RuntimeError {
        guard case .unknownCapability("teleport") = error else {
            Issue.record("Wrong error: \(error)"); return
        }
    } catch { Issue.record("Unexpected error type: \(error)") }
}

@Test func manifestParserUnknownPermission() {
    do {
        _ = try ManifestParser.parse(manifestData(overrides: ["permissions": ["telepathy": true]]))
        Issue.record("Expected unknownPermission")
    } catch let error as RuntimeError {
        guard case .unknownPermission("telepathy") = error else {
            Issue.record("Wrong error: \(error)"); return
        }
    } catch { Issue.record("Unexpected error type: \(error)") }
}

// MARK: - Validation & installation

@Test func installRejectsMissingEntryPoint() async throws {
    let engine = makeEngine()
    let dir = try writePackage(manifest: manifestData(entryPoint: "nope.js")) // writes main.js, not nope.js
    do {
        _ = try await engine.install(from: DirectoryPackageSource(directory: dir))
        Issue.record("Expected entryPointMissing")
    } catch let error as RuntimeError {
        guard case .entryPointMissing("nope.js") = error else {
            Issue.record("Wrong error: \(error)"); return
        }
    }
}

@Test func installRejectsIncompatibleSDK() async throws {
    let engine = makeEngine()
    let dir = try writePackage(manifest: manifestData(sdkVersion: "2.0.0"))
    do {
        _ = try await engine.install(from: DirectoryPackageSource(directory: dir))
        Issue.record("Expected sdkIncompatible")
    } catch let error as RuntimeError {
        guard case .sdkIncompatible = error else { Issue.record("Wrong error: \(error)"); return }
    }
}

@Test func installRejectsDuplicateID() async throws {
    let engine = makeEngine()
    let dir = try writePackage(manifest: manifestData())
    _ = try await engine.install(from: DirectoryPackageSource(directory: dir))
    do {
        _ = try await engine.install(from: DirectoryPackageSource(directory: dir))
        Issue.record("Expected duplicateExtensionID")
    } catch let error as RuntimeError {
        guard case .duplicateExtensionID = error else { Issue.record("Wrong error: \(error)"); return }
    }
}

@Test func installRegistersAndExposesCapabilities() async throws {
    let (engine, id) = try await installedEngine()
    let all = await engine.installedExtensions
    #expect(all.count == 1)
    let caps = try await engine.capabilities(of: id)
    #expect(caps == [.search, .details, .streams])
    #expect(await engine.defaultExtensionID(supporting: .search) == id)
}

// MARK: - Execution (happy path)

@Test func searchHappyPath() async throws {
    let (engine, id) = try await installedEngine()
    let items = try await engine.search(id, query: "history", page: 1)
    #expect(items.count == 2)
    #expect(items.first?.id == "show-42")
    #expect(items.first?.kind == .podcast)
}

@Test func detailsIncludeEpisodes() async throws {
    let (engine, id) = try await installedEngine()
    let details = try await engine.details(id, itemId: "show-42")
    #expect(details.id == "show-42")
    #expect(details.episodes?.count == 2)
    #expect(details.episodes?.first?.kind == .episode)
}

@Test func streamsResolve() async throws {
    let (engine, id) = try await installedEngine()
    let streams = try await engine.streams(id, itemId: "show-42", episodeId: "ep-1001")
    #expect(streams.count == 1)
    #expect(streams.first?.url.hasPrefix("https://") == true)
}

// MARK: - Execution (errors, gating, enforcement)

@Test func notFoundMapsThrough() async throws {
    let (engine, id) = try await installedEngine()
    await expectConnectorError(.notFound) {
        _ = try await engine.details(id, itemId: "does-not-exist")
    }
}

@Test func capabilityNotDeclaredIsRejected() async throws {
    // Only `search` is declared; requesting streams must be refused before execution.
    let (engine, id) = try await installedEngine(manifest: manifestData(capabilities: ["search"]))
    await expectConnectorError(.notFound) {
        _ = try await engine.streams(id, itemId: "show-42", episodeId: "ep-1001")
    }
}

@Test func undeclaredDomainIsBlocked() async throws {
    let evil = """
    globalThis.connectorInstance = {
        async search() { await Runtime.request({ url: 'https://evil.example.com/x' }); return []; },
        async getDetails() { return {}; },
        async getStreams() { return []; }
    };
    """
    let (engine, id) = try await installedEngine(js: evil)
    await expectConnectorError(.permissionDenied) {
        _ = try await engine.search(id, query: "x")
    }
}

@Test func missingNetworkPermissionBlocksAllRequests() async throws {
    let manifest = manifestData(capabilities: ["search"], networkDomains: nil) // no network declared
    let requester = """
    globalThis.connectorInstance = {
        async search() { await Runtime.request({ url: 'https://api.example-podcasts.com/search?q=x&page=1' }); return []; },
        async getDetails() { return {}; },
        async getStreams() { return []; }
    };
    """
    let (engine, id) = try await installedEngine(manifest: manifest, js: requester)
    await expectConnectorError(.permissionDenied) {
        _ = try await engine.search(id, query: "x")
    }
}

@Test func storageQuotaIsEnforced() async throws {
    let manifest = manifestData(capabilities: ["search"], networkDomains: nil, storageMaxBytes: 16)
    let hog = """
    globalThis.connectorInstance = {
        async search() { await Runtime.storage.set('big', 'x'.repeat(1000)); return []; },
        async getDetails() { return {}; },
        async getStreams() { return []; }
    };
    """
    let (engine, id) = try await installedEngine(manifest: manifest, js: hog)
    await expectConnectorError(.storageQuotaExceeded) {
        _ = try await engine.search(id, query: "x")
    }
}

@Test func malformedReturnIsRejected() async throws {
    let manifest = manifestData(capabilities: ["search"], networkDomains: nil)
    let bad = """
    globalThis.connectorInstance = {
        async search() { return [{ title: 'no id', kind: 'podcast' }]; },
        async getDetails() { return {}; },
        async getStreams() { return []; }
    };
    """
    let (engine, id) = try await installedEngine(manifest: manifest, js: bad)
    await expectConnectorError(.invalidResponse) {
        _ = try await engine.search(id, query: "x")
    }
}

// MARK: - Repository models

@Test func repositoryModelRoundTrips() throws {
    let repo = Repository(
        metadata: RepositoryMetadata(name: "Official", description: "The official repo"),
        publisher: Publisher(id: "official", displayName: "Runtime Official", verified: true),
        extensions: [
            ExtensionListing(
                id: "com.runtime.podcast-rss",
                displayName: "Podcast RSS",
                category: .media,
                versions: [
                    RepositoryVersion(
                        version: SemanticVersion(major: 1, minor: 0, patch: 0),
                        downloadURL: "https://example.com/podcast-rss-1.0.0.zip",
                        checksum: RepositoryChecksum(algorithm: "sha256", value: "abc123"),
                        signature: RepositorySignature(algorithm: "ed25519", value: "sig", signedBy: "official")
                    )
                ]
            )
        ]
    )
    let data = try JSONEncoder().encode(repo)
    let decoded = try JSONDecoder().decode(Repository.self, from: data)
    #expect(decoded == repo)
    #expect(decoded.extensions.first?.latest?.version == SemanticVersion(major: 1, minor: 0, patch: 0))
    #expect(decoded.publisher.verified)
}

// MARK: - Repository pipeline

/// Writes a repository.json + package document to a temp dir and returns file URLs.
/// Uses `file://` (not the shared FixtureURLProtocol) so these tests can't race with
/// other tests clearing global fixtures.
private func writeRepository(
    manifest: Data = manifestData(),
    js: String = goldenConnectorJS,
    versionOverride: SemanticVersion? = nil,
    corruptChecksum: Bool = false
) throws -> (repoURL: URL, listing: ExtensionListing, version: RepositoryVersion) {
    let parsed = try ManifestParser.parse(manifest)
    let document = ExtensionPackageDocument(manifest: parsed, entryPoint: js)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let packageData = try encoder.encode(document)

    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("repo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let packageURL = dir.appendingPathComponent("package.json")
    try packageData.write(to: packageURL)

    let checksumValue = corruptChecksum
        ? String(repeating: "0", count: 64)
        : RepositoryService.sha256Hex(packageData)
    let version = RepositoryVersion(
        version: versionOverride ?? parsed.version,
        downloadURL: packageURL.absoluteString,
        checksum: RepositoryChecksum(algorithm: "sha256", value: checksumValue),
        minimumRuntimeVersion: parsed.minimumRuntimeVersion
    )
    let listing = ExtensionListing(id: parsed.id, displayName: parsed.displayName, category: .media, versions: [version])
    let repository = Repository(
        metadata: RepositoryMetadata(name: "Test Repo"),
        publisher: Publisher(id: "test", displayName: "Test"),
        extensions: [listing]
    )
    let repoURL = dir.appendingPathComponent("repository.json")
    try encoder.encode(repository).write(to: repoURL)
    return (repoURL, listing, version)
}

@Test func repositoryFetchAndParse() async throws {
    let fixture = try writeRepository()
    let repo = try await RepositoryService().fetchRepository(at: fixture.repoURL)
    #expect(repo.extensions.count == 1)
    #expect(repo.extensions.first?.id == "com.test.sample")
}

@Test func repositoryInstallEndToEnd() async throws {
    let fixture = try writeRepository()
    let engine = makeEngine()
    let installed = try await RepositoryService().install(fixture.version, from: fixture.listing, into: engine)
    #expect(installed.id == "com.test.sample")
    #expect(await engine.isInstalled("com.test.sample"))
}

@Test func repositoryDetectsUpdates() async throws {
    let (engine, id) = try await installedEngine()
    let installed = await engine.installedExtensions
    let fixture = try writeRepository(
        manifest: manifestData(id: id),
        versionOverride: SemanticVersion(major: 2, minor: 0, patch: 0)
    )
    let service = RepositoryService()
    let repo = try await service.fetchRepository(at: fixture.repoURL)
    #expect(service.availableUpdates(in: repo, installed: installed).contains { $0.id == id })
}

@Test func repositoryRejectsChecksumMismatch() async throws {
    let fixture = try writeRepository(corruptChecksum: true)
    do {
        _ = try await RepositoryService().install(fixture.version, from: fixture.listing, into: makeEngine())
        Issue.record("Expected checksumMismatch")
    } catch let error as RuntimeError {
        guard case .checksumMismatch = error else { Issue.record("Wrong error: \(error)"); return }
    }
}

@Test func checksumVerificationRoundTrips() throws {
    let service = RepositoryService()
    let data = Data("hello rext".utf8)
    try service.verifyChecksum(data, against: RepositoryChecksum(algorithm: "sha256", value: RepositoryService.sha256Hex(data)))
    do {
        try service.verifyChecksum(data, against: RepositoryChecksum(algorithm: "sha256", value: String(repeating: "0", count: 64)))
        Issue.record("Expected mismatch")
    } catch let error as RuntimeError {
        guard case .checksumMismatch = error else { Issue.record("Wrong error: \(error)"); return }
    }
}

// MARK: - Uninstall & the RextExtension contract

@Test func uninstallRemovesExtension() async throws {
    let (engine, id) = try await installedEngine()
    #expect(await engine.isInstalled(id))
    await engine.uninstall(id: id)
    #expect(await engine.isInstalled(id) == false)
}

@Test func executeInvokesCustomAction() async throws {
    let js = """
    globalThis.connectorInstance = {
        async search() { return []; },
        async getDetails() { return {}; },
        async getStreams() { return []; },
        async echo(payload) { return { data: { got: payload.msg }, items: null }; }
    };
    """
    let (engine, id) = try await installedEngine(manifest: manifestData(capabilities: ["search"], networkDomains: nil), js: js)
    let response = try await engine.execute(id, action: "echo", payload: ["msg": .string("hi")])
    #expect(response.data?["got"] == .string("hi"))
}

@Test func episodesCapabilityGated() async throws {
    // The golden extension declares search/details/streams but NOT episodes.
    let (engine, id) = try await installedEngine()
    await expectConnectorError(.notFound) {
        _ = try await engine.episodes(id, itemId: "show-42")
    }
}

// MARK: - Unified search, storage, multi-repo

private let inlineTwoResultConnector = """
globalThis.connectorInstance = {
    async search(q) {
        return [
            { id: "x1", title: "One", subtitle: null, artworkUrl: null, kind: "podcast", metadata: null },
            { id: "x2", title: "Two", subtitle: null, artworkUrl: null, kind: "podcast", metadata: null }
        ];
    },
    async getDetails() { return {}; },
    async getStreams() { return []; }
};
"""

@Test func searchAllGroupsByExtension() async throws {
    let engine = makeEngine()
    let dirA = try writePackage(manifest: manifestData(id: "com.test.a", capabilities: ["search"], networkDomains: nil), js: inlineTwoResultConnector)
    let dirB = try writePackage(manifest: manifestData(id: "com.test.b", capabilities: ["search"], networkDomains: nil), js: inlineTwoResultConnector)
    _ = try await engine.install(from: DirectoryPackageSource(directory: dirA))
    _ = try await engine.install(from: DirectoryPackageSource(directory: dirB))

    let results = await engine.searchAll(query: "anything")
    #expect(results.count == 2)
    #expect(results.allSatisfy { $0.items.count == 2 })
    #expect(Set(results.map(\.extensionID)) == ["com.test.a", "com.test.b"])
}

@Test func searchAllToleratesPerExtensionFailure() async throws {
    let badConnector = """
    globalThis.connectorInstance = {
        async search() { throw { code: "UPSTREAM_ERROR", message: "boom" }; },
        async getDetails() { return {}; },
        async getStreams() { return []; }
    };
    """
    let engine = makeEngine()
    _ = try await engine.install(from: DirectoryPackageSource(directory:
        try writePackage(manifest: manifestData(id: "com.test.good", capabilities: ["search"], networkDomains: nil), js: inlineTwoResultConnector)))
    _ = try await engine.install(from: DirectoryPackageSource(directory:
        try writePackage(manifest: manifestData(id: "com.test.bad", capabilities: ["search"], networkDomains: nil), js: badConnector)))

    let results = await engine.searchAll(query: "x")
    #expect(results.count == 2)
    #expect(results.first { $0.extensionID == "com.test.good" }?.items.count == 2)
    let bad = results.first { $0.extensionID == "com.test.bad" }
    #expect(bad?.items.isEmpty == true)
    #expect(bad?.errorMessage != nil)
}

@Test func storageUsageAndClear() async throws {
    let hog = """
    globalThis.connectorInstance = {
        async search() { await Runtime.storage.set("k", "x".repeat(100)); return []; },
        async getDetails() { return {}; },
        async getStreams() { return []; }
    };
    """
    let engine = makeEngine()
    let installed = try await engine.install(from: DirectoryPackageSource(directory:
        try writePackage(manifest: manifestData(capabilities: ["search"], networkDomains: nil, storageMaxBytes: 65536), js: hog)))
    _ = try await engine.search(installed.id, query: "x")

    #expect(await engine.storageBytes(of: installed.id) > 100)
    await engine.clearStorage(of: installed.id)
    #expect(await engine.storageBytes(of: installed.id) == 0)
}

@MainActor
@Test func multiRepositoryAggregation() async throws {
    let engine = makeEngine()
    let repoA = try writeRepository(manifest: manifestData(id: "com.test.a"))
    let repoB = try writeRepository(manifest: manifestData(id: "com.test.b"))
    let controller = ExtensionsController(engine: engine, repositoryService: RepositoryService())

    await controller.refresh(repositories: [
        RepoRef(url: repoA.repoURL.absoluteString, title: nil),
        RepoRef(url: repoB.repoURL.absoluteString, title: nil),
    ])

    #expect(controller.available.count == 2)
    #expect(Set(controller.available.map(\.id)) == ["com.test.a", "com.test.b"])
}

// MARK: - Playback Event Engine

@MainActor
@Test func playbackEventsRecordAndAggregate() throws {
    let container = try ModelContainer(
        for: PlaybackEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let recorder = SwiftDataPlaybackEventRecorder(context: context)

    func event(_ type: PlaybackEventType, position: Double = 0, duration: Double = 100) -> PlaybackEventInput {
        PlaybackEventInput(type: type, extensionID: "com.test", itemID: "item-1",
                           title: "Demo", kind: "movie",
                           positionSeconds: position, durationSeconds: duration)
    }

    recorder.record(event(.started))
    recorder.record(event(.paused, position: 30))
    recorder.record(event(.resumed, position: 30))
    recorder.record(event(.completed, position: 100))

    let store = PlaybackEventStore(context: context)
    #expect(store.allEvents().count == 4)
    #expect(store.events(itemID: "item-1").count == 4)
    #expect(store.events(itemID: "missing").isEmpty)
    #expect(store.count(of: .started) == 1)
    #expect(store.count(of: .completed) == 1)
    #expect(store.completionRate() == 1.0)
    // Ordered chronologically, first is `started`.
    #expect(store.allEvents().first?.type == .started)
}

// MARK: - Assertion helper

/// Runs `body`, expecting it to throw a `ConnectorError` with the given code.
///
/// The type is module-qualified as `Runtime.ConnectorError` because the project
/// compiles `ConnectorError.swift` into the test target as well as the app
/// module; the engine throws the app module's type, so the cast must name it.
private func expectConnectorError(
    _ code: Runtime.ConnectorErrorCode,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        Issue.record("Expected ConnectorError.\(code.rawValue), but no error was thrown")
    } catch let error as Runtime.ConnectorError {
        #expect(error.code == code, "Expected \(code.rawValue), got \(error.code.rawValue)")
    } catch {
        Issue.record("Expected ConnectorError, got \(error)")
    }
}
