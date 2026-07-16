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

// MARK: - Recommendation Engine v1

/// Build a candidate whose canonical metadata carries the given genres/creators.
private func candidate(
    _ id: String,
    title: String,
    kind: CatalogKind = .movie,
    genres: [String] = [],
    creators: [String] = [],
    extensionID: String = "com.test"
) -> RecommendationCandidate {
    let item = CatalogItem(
        id: id, title: title, subtitle: nil, artworkUrl: nil, kind: kind, metadata: nil,
        canonical: ContentMetadata(genres: genres, creators: creators)
    )
    return RecommendationCandidate(extensionID: extensionID, item: item)
}

@Test func deterministicRecommenderRanksExplainsAndFilters() {
    var profile = TasteProfile()
    profile.genreScores = ["Science Fiction": 6.0, "Drama": 2.0]
    profile.genreExemplars = ["Science Fiction": "Interstellar", "Drama": "The Godfather"]
    profile.kindScores = ["movie": 3.0]
    profile.signalCount = 3

    let candidates = [
        candidate("a", title: "Arrival", genres: ["Science Fiction"]),        // strong match
        candidate("b", title: "Some Drama", genres: ["Drama"]),               // weaker match
        candidate("c", title: "Unrelated Cooking Show", genres: ["Cooking"]), // no overlap → dropped
        candidate("d", title: "No Metadata"),                                 // nothing → dropped
    ]

    let ranked = DeterministicRecommender().rank(candidates, against: profile, limit: 10)

    // Only the two matching candidates survive, sci-fi first (higher affinity).
    #expect(ranked.map(\.item.id) == ["a", "b"])
    #expect(ranked.first?.reason.genres.first == "Science Fiction")
    #expect(ranked.first?.reason.seedTitle == "Interstellar")
    #expect(ranked.first?.reason.headline == "Because you watched Interstellar")
    #expect(ranked.first!.score > ranked.last!.score)
}

@Test func deterministicRecommenderIsQuietWithoutSignals() {
    let empty = TasteProfile()
    #expect(empty.isEmpty)
    let ranked = DeterministicRecommender().rank(
        [candidate("a", title: "Arrival", genres: ["Science Fiction"])],
        against: empty, limit: 10
    )
    #expect(ranked.isEmpty)
}

@MainActor
@Test func tasteProfileBuilderWeightsFavoritesHighest() throws {
    let container = try ModelContainer(
        for: LibraryItem.self, HistoryEntry.self, PlaybackEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    context.insert(LibraryItem(
        extensionID: "com.test", itemID: "fav", title: "Interstellar",
        kind: "movie", collection: .favorites, genres: ["Science Fiction"]
    ))
    context.insert(LibraryItem(
        extensionID: "com.test", itemID: "saved", title: "Some Comedy",
        kind: "movie", collection: .watching, genres: ["Comedy"]
    ))

    let profile = TasteProfileBuilder(context: context).build()

    #expect(profile.signalCount == 2)
    #expect((profile.genreScores["Science Fiction"] ?? 0) > (profile.genreScores["Comedy"] ?? 0))
    #expect(profile.topGenres.first == "Science Fiction")
    #expect(profile.genreExemplars["Science Fiction"] == "Interstellar")
}

// MARK: - Universal Content Graph (Phase 3)

private func graphItem(
    _ id: String,
    title: String = "Untitled",
    kind: CatalogKind = .movie,
    genres: [String] = [],
    creators: [String] = [],
    artwork: String? = nil
) -> CatalogItem {
    CatalogItem(
        id: id, title: title, subtitle: nil, artworkUrl: artwork, kind: kind, metadata: nil,
        canonical: ContentMetadata(genres: genres, creators: creators)
    )
}

@MainActor
@Test func contentGraphIngestIsIdempotentAndEnriches() throws {
    let container = try ModelContainer(
        for: ContentNode.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let graph = ContentGraph(context: container.mainContext)

    let first = graph.ingest(graphItem("v1", title: "Dune", genres: ["Science Fiction"]), extensionID: "com.test")
    // Re-ingesting the same locator enriches rather than duplicating.
    let second = graph.ingest(graphItem("v1", title: "Dune (2021)", genres: ["Drama"], artwork: "art.png"), extensionID: "com.test")

    #expect(first == second)
    #expect(graph.allContent().count == 1)

    let content = try #require(graph.content(for: first))
    #expect(content.title == "Dune (2021)")                 // latest non-empty title wins
    #expect(content.artworkURL == "art.png")                // newly supplied artwork filled in
    #expect(content.metadata.genres == ["Science Fiction", "Drama"]) // unioned, order-preserving
    #expect(content.availability.count == 1)                // same provider locator, not duplicated
    #expect(content.availability.first?.extensionID == "com.test")
}

@MainActor
@Test func contentGraphLinksEpisodesToParent() throws {
    let container = try ModelContainer(
        for: ContentNode.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let graph = ContentGraph(context: container.mainContext)

    let details = MediaDetails(
        id: "show-1", title: "A Show", subtitle: nil, artworkUrl: nil, backdropUrl: nil,
        kind: .series, metadata: nil,
        episodes: [graphItem("ep-1", title: "Pilot", kind: .episode),
                   graphItem("ep-2", title: "Second", kind: .episode)],
        canonical: ContentMetadata(genres: ["Drama"])
    )
    let parentID = graph.ingest(details, extensionID: "com.test")

    #expect(graph.allContent().count == 3) // parent + 2 episodes
    let episodeID = ContentID.provider(extensionID: "com.test", itemID: "ep-1")
    #expect(graph.related(to: episodeID, type: .episodeOf) == [parentID])
    #expect(graph.content(for: parentID)?.kind == .series)
}

@MainActor
@Test func librarySaveCreatesContentGraphReference() throws {
    let container = try ModelContainer(
        for: RepositorySource.self, LibraryItem.self, HistoryEntry.self, PlaybackEvent.self, ContentNode.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let item = graphItem("v9", title: "Interstellar", genres: ["Science Fiction"])

    let saved = LibraryActions.toggle(item, extensionID: "com.test", collection: .favorites, context: context)
    #expect(saved)

    // The library row references the canonical node rather than owning the truth.
    let rows = try context.fetch(FetchDescriptor<LibraryItem>())
    #expect(rows.first?.contentID == "com.test|v9")

    let content = ContentGraph(context: context).content(for: ContentID.provider(extensionID: "com.test", itemID: "v9"))
    #expect(content?.metadata.genres == ["Science Fiction"])
}

// MARK: - Activity Graph (Phase 4)

@MainActor
@Test func activityTimelineRecordsAndQueriesAcrossDomains() throws {
    let container = try ModelContainer(
        for: ActivityEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let session = ActivitySession()
    let recorder = SwiftDataActivityRecorder(context: context, session: session)

    let item = graphItem("v1", title: "Dune", kind: .movie, genres: ["Science Fiction"])
    recorder.record(.search("dune"))
    recorder.record(.content(.view, extensionID: "com.test", item: item))
    recorder.record(.content(.favorite, extensionID: "com.test", item: item))
    recorder.record(.content(.playbackStarted, extensionID: "com.test", item: item, positionSeconds: 0, durationSeconds: 120))
    recorder.record(.content(.playbackCompleted, extensionID: "com.test", item: item, positionSeconds: 120, durationSeconds: 120))

    let log = ActivityLog(context: context)
    #expect(log.recent().count == 5)
    // Newest first: the last recorded event leads the timeline.
    #expect(log.recent().first?.action == .playbackCompleted)
    #expect(log.count(of: .search) == 1)
    #expect(log.count(of: .favorite) == 1)

    // Content-scoped query resolves through the Phase 3 ContentID.
    let contentID = ContentID.provider(extensionID: "com.test", itemID: "v1")
    #expect(log.events(contentID: contentID).count == 4) // all but the search
    #expect(log.recentSearches() == ["dune"])

    // Session + device context is stamped on every event.
    let first = try #require(log.recent().last)
    #expect(first.sessionID == session.id.uuidString)
    #expect(!first.appVersion.isEmpty)
}

@Test func playbackEventTypeMapsToActivityAction() {
    #expect(PlaybackEventType.started.activityAction == .playbackStarted)
    #expect(PlaybackEventType.completed.activityAction == .playbackCompleted)
    #expect(PlaybackEventType.abandoned.activityAction == .playbackAbandoned)
    // Seek-level noise is not mirrored onto the coarse timeline.
    #expect(PlaybackEventType.skipped.activityAction == nil)
    #expect(PlaybackEventType.replayed.activityAction == nil)
}

@MainActor
@Test func librarySaveRecordsActivity() throws {
    let container = try ModelContainer(
        for: RepositorySource.self, LibraryItem.self, HistoryEntry.self,
        PlaybackEvent.self, ContentNode.self, ActivityEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let item = graphItem("v2", title: "Arrival", genres: ["Science Fiction"])

    _ = LibraryActions.toggle(item, extensionID: "com.test", collection: .favorites, context: context)
    _ = LibraryActions.toggle(item, extensionID: "com.test", collection: .favorites, context: context) // un-favorite

    let log = ActivityLog(context: context)
    #expect(log.count(of: .favorite) == 1)
    #expect(log.count(of: .unfavorite) == 1)
}

// MARK: - Intelligence backfill (Phase 5): semantic index, matching, trending

@Test func semanticIndexScoresSimilarityByOverlap() {
    let index = SemanticIndex()
    func sig(_ id: String, _ title: String, kind: CatalogKind = .movie, creators: [String] = []) -> ContentSignature {
        index.signature(for: Content(
            id: ContentID(rawValue: id), title: title, kind: kind,
            metadata: ContentMetadata(creators: creators)
        ))
    }
    let a = sig("a", "The Matrix Reloaded", creators: ["Wachowski"])
    let b = sig("b", "Matrix Reloaded", creators: ["Wachowski"]) // near-identical
    let c = sig("c", "Cooking with Fire")                        // unrelated

    #expect(index.similarity(a, b) > index.similarity(a, c))
    #expect(index.similarity(a, c) < 0.2)
    #expect(index.similarity(a, b) > 0.6)
}

@MainActor
@Test func contentMatcherDetectsCrossProviderDuplicatesAndMerges() throws {
    let container = try ModelContainer(
        for: ContentNode.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let graph = ContentGraph(context: container.mainContext)

    // Same movie from two providers, plus an unrelated one.
    graph.ingest(graphItem("m1", title: "Blade Runner 2049", genres: ["Science Fiction"]), extensionID: "com.provider.a")
    graph.ingest(graphItem("m1", title: "Blade Runner 2049", genres: ["Science Fiction"]), extensionID: "com.provider.b")
    graph.ingest(graphItem("z9", title: "A Cooking Show", genres: ["Food"]), extensionID: "com.provider.a")

    let service = ContentMatchingService(context: container.mainContext)
    let cross = service.crossProviderMatches()
    #expect(cross.count == 1)
    #expect(cross.first?.all.count == 2)

    let merged = service.applyMerges()
    #expect(merged == 1)

    // The primary now carries both providers' availability and a `.sameAs` link exists.
    let primary = try #require(cross.first?.primary)
    #expect(graph.content(for: primary)?.availability.count == 2)
    let dup = try #require(cross.first?.duplicates.first)
    #expect(graph.related(to: dup, type: .sameAs) == [primary])
}

@Test func trendingScorerRanksByDecayedActivity() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func snap(_ item: String, _ action: ActivityAction, daysAgo: Double) -> ActivitySnapshot {
        ActivitySnapshot(action: action, extensionID: "com.test", itemID: item,
                         title: item.uppercased(), kind: .movie,
                         timestamp: now.addingTimeInterval(-daysAgo * 86_400))
    }
    let snapshots = [
        snap("hot", .playbackCompleted, daysAgo: 0),   // heavy, fresh
        snap("hot", .favorite, daysAgo: 0),
        snap("old", .playbackCompleted, daysAgo: 60),  // heavy but stale → decayed
        snap("meh", .view, daysAgo: 0),                // light
    ]
    let ranked = TrendingScorer(halfLifeDays: 7).rank(snapshots, now: now, limit: 10)

    #expect(ranked.first?.itemID == "hot")
    #expect(ranked.map(\.itemID) == ["hot", "meh", "old"]) // fresh light beats stale heavy
    // Searches / pauses carry no trend weight, so they never appear.
    #expect(!ranked.contains { $0.itemID == "missing" })
}

@MainActor
@Test func smartCollectionsSurfaceTrendingAndAffinity() throws {
    let container = try ModelContainer(
        for: RepositorySource.self, LibraryItem.self, HistoryEntry.self,
        PlaybackEvent.self, ContentNode.self, ActivityEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let graph = ContentGraph(context: context)

    // Seed a couple of sci-fi titles into the graph the user hasn't finished.
    graph.ingest(graphItem("s1", title: "Arrival", genres: ["Science Fiction"]), extensionID: "com.test")
    graph.ingest(graphItem("s2", title: "Dune", genres: ["Science Fiction"]), extensionID: "com.test")

    // A favorite establishes a Science Fiction affinity in the taste profile.
    context.insert(LibraryItem(extensionID: "com.test", itemID: "fav", title: "Interstellar",
                               kind: "movie", collection: .favorites, genres: ["Science Fiction"]))

    let collections = SmartCollectionsBuilder(context: context).build()
    #expect(collections.contains { $0.title == "More Science Fiction" })
    let sciFi = try #require(collections.first { $0.title == "More Science Fiction" })
    #expect(sciFi.items.count == 2) // Arrival + Dune, not the already-favorited Interstellar
}

// MARK: - User Platform (Phase 6)

@MainActor
@Test func profileManagerSeedsSwitchesAndDeletes() throws {
    let container = try ModelContainer(
        for: UserProfile.self, LibraryItem.self, HistoryEntry.self, PlaybackEvent.self, ActivityEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let manager = ProfileManager(persists: false)
    manager.bootstrap(context: container.mainContext)

    // First launch seeds exactly one default profile and makes it active.
    #expect(manager.profiles.count == 1)
    #expect(manager.currentProfileID == UserProfile.defaultProfileID)

    let kid = manager.create(name: "Kiddo", kind: .child, parentalControls: ParentalControls(isEnabled: true, blockedGenres: ["Horror"]))
    manager.switchTo(kid)
    #expect(manager.current?.name == "Kiddo")
    #expect(manager.contentPolicy.controls.isEnabled)

    // The default profile is protected from deletion; others delete cleanly.
    manager.delete(kid)
    #expect(manager.profiles.count == 1)
    #expect(manager.currentProfileID == UserProfile.defaultProfileID)
}

@MainActor
@Test func libraryAndActivityAreProfileScoped() throws {
    let container = try ModelContainer(
        for: RepositorySource.self, LibraryItem.self, HistoryEntry.self,
        PlaybackEvent.self, ContentNode.self, ActivityEvent.self, UserProfile.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    // Two profiles each favorite the *same* item — must not collide, and each
    // profile only sees its own row.
    let item = graphItem("v1", title: "Dune", genres: ["Science Fiction"])
    context.insert(LibraryItem(extensionID: "com.test", itemID: item.id, title: item.title,
                               kind: item.kind.rawValue, collection: .favorites,
                               genres: ["Science Fiction"], profileID: "alice"))
    context.insert(LibraryItem(extensionID: "com.test", itemID: item.id, title: item.title,
                               kind: item.kind.rawValue, collection: .favorites,
                               genres: ["Science Fiction"], profileID: "bob"))

    let all = try context.fetch(FetchDescriptor<LibraryItem>())
    #expect(all.count == 2) // no unique-key collision across profiles

    // Taste is computed per profile.
    let aliceTaste = TasteProfileBuilder(context: context, profileID: "alice").build()
    #expect(aliceTaste.signalCount == 1)
    let ghostTaste = TasteProfileBuilder(context: context, profileID: "nobody").build()
    #expect(ghostTaste.isEmpty)
}

@Test func contentPolicyBlocksByGenreAndKind() {
    let controls = ParentalControls(isEnabled: true, allowedKinds: ["movie"], blockedGenres: ["Horror"])
    let policy = ContentPolicy(controls: controls)

    let ok = CatalogItem(id: "1", title: "Family Film", subtitle: nil, artworkUrl: nil, kind: .movie,
                         metadata: nil, canonical: ContentMetadata(genres: ["Comedy"]))
    let blockedGenre = CatalogItem(id: "2", title: "Scary", subtitle: nil, artworkUrl: nil, kind: .movie,
                                   metadata: nil, canonical: ContentMetadata(genres: ["Horror"]))
    let blockedKind = CatalogItem(id: "3", title: "A Podcast", subtitle: nil, artworkUrl: nil, kind: .podcast,
                                  metadata: nil, canonical: ContentMetadata(genres: ["Comedy"]))

    #expect(policy.allows(ok))
    #expect(!policy.allows(blockedGenre))
    #expect(!policy.allows(blockedKind))
    // A disabled policy allows everything.
    #expect(ContentPolicy.unrestricted.allows(blockedGenre))
}

// MARK: - Cloud Platform (Phase 7): sync

@MainActor
private func makeSyncContainer() throws -> ModelContainer {
    try ModelContainer(
        for: RepositorySource.self, LibraryItem.self, HistoryEntry.self,
        PlaybackEvent.self, ContentNode.self, ActivityEvent.self, UserProfile.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

@MainActor
@Test func syncSnapshotRoundTripsThroughBackend() async throws {
    // Device A: seed a profile + a saved item + a history row, then export+push.
    let deviceA = try makeSyncContainer()
    let ctxA = deviceA.mainContext
    ctxA.insert(UserProfile(id: "p1", name: "Alice", kind: .adult))
    ctxA.insert(LibraryItem(extensionID: "com.test", itemID: "v1", title: "Dune",
                            kind: "movie", collection: .favorites, genres: ["Science Fiction"], profileID: "p1"))
    ctxA.insert(HistoryEntry(extensionID: "com.test", itemID: "v2", title: "Arrival", kind: "movie",
                             profileID: "p1", positionSeconds: 30, durationSeconds: 100))
    try ctxA.save()

    let backend = InMemorySyncBackend()
    let snapshot = SyncService(context: ctxA).export()
    try await backend.push(snapshot)

    // Device B: a fresh empty store pulls + applies → data reconstructed.
    let deviceB = try makeSyncContainer()
    let ctxB = deviceB.mainContext
    let remote = try #require(try await backend.pull())
    SyncService(context: ctxB).apply(remote)

    #expect(try ctxB.fetchCount(FetchDescriptor<UserProfile>()) == 1)
    #expect(try ctxB.fetchCount(FetchDescriptor<LibraryItem>()) == 1)
    let history = try ctxB.fetch(FetchDescriptor<HistoryEntry>())
    #expect(history.first?.itemID == "v2")
    #expect(history.first?.positionSeconds == 30)
    #expect(history.first?.profileID == "p1")
}

@MainActor
@Test func syncApplyIsIdempotentAndLastWriteWins() throws {
    let device = try makeSyncContainer()
    let context = device.mainContext
    let service = SyncService(context: context)

    let base = SyncSnapshot(
        deviceID: "dev",
        profiles: [ProfileDTO(id: "p1", name: "Alice", kindRaw: "adult", avatarSymbol: "person.crop.circle.fill",
                              colorHex: "#3B82F6", createdAt: .now, preferences: ProfilePreferences(), parentalControls: ParentalControls())],
        history: [HistoryEntryDTO(extensionID: "com.test", itemID: "v1", title: "Dune", kind: "movie",
                                  artworkURL: nil, lastAccessed: Date(timeIntervalSince1970: 1000),
                                  positionSeconds: 10, durationSeconds: 100, profileID: "p1")],
        preferences: PreferencesDTO(defaultVideoQuality: "1080p", enableDebugLogging: false)
    )
    service.apply(base)
    service.apply(base) // re-applying must not duplicate
    #expect(try context.fetchCount(FetchDescriptor<HistoryEntry>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 1)

    // A newer resume position for the same item wins; an older one is ignored.
    var newer = base
    newer.history[0].lastAccessed = Date(timeIntervalSince1970: 5000)
    newer.history[0].positionSeconds = 80
    service.apply(newer)
    #expect(try context.fetch(FetchDescriptor<HistoryEntry>()).first?.positionSeconds == 80)

    var older = base
    older.history[0].lastAccessed = Date(timeIntervalSince1970: 100)
    older.history[0].positionSeconds = 5
    service.apply(older)
    #expect(try context.fetch(FetchDescriptor<HistoryEntry>()).first?.positionSeconds == 80) // unchanged
}

// MARK: - Provider Ecosystem (Phase 8): catalog

@Test func providerCatalogResolvesStatusFromRuntimeState() {
    let resolved = ProviderCatalog.resolved(
        installedIDs: ["com.runtime.podcast-rss"],
        availableIDs: ["com.runtime.rss"]
    )
    func status(_ kind: ProviderKind) -> ProviderStatus? {
        resolved.first { $0.kind == kind }?.status
    }
    #expect(status(.podcasts) == .installed)  // installed extension
    #expect(status(.rss) == .available)       // available in a repo
    #expect(status(.plex) == .comingSoon)     // architected, not shipped
    #expect(status(.youTube) == .comingSoon)
    // The full roadmap set is represented.
    #expect(resolved.count == ProviderKind.allCases.count)
}

@Test func providerCatalogGroupsByCategory() {
    let groups = ProviderCatalog.grouped(ProviderCatalog.all)
    let categories = groups.map(\.category)
    // Media, News & Feeds, and Books & Audiobooks are all represented, in order.
    #expect(categories.contains(.media))
    #expect(categories.contains(.news))
    #expect(categories.contains(.books))
    // Books group holds both Books and Audiobooks.
    let books = groups.first { $0.category == .books }?.providers.map(\.kind) ?? []
    #expect(Set(books) == [.books, .audiobooks])
    // No empty groups are emitted.
    #expect(groups.allSatisfy { !$0.providers.isEmpty })
}

// MARK: - Experience Evolution (Phase 9): watch queue + home feed

@MainActor
private func makeExperienceContainer() throws -> ModelContainer {
    try ModelContainer(
        for: RepositorySource.self, LibraryItem.self, HistoryEntry.self, PlaybackEvent.self,
        ContentNode.self, ActivityEvent.self, UserProfile.self, QueueItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

@MainActor
@Test func watchQueueEnqueuesOrdersAndScopes() throws {
    let context = try makeExperienceContainer().mainContext
    let alice = WatchQueue(context: context, profileID: "alice")

    let a = graphItem("a", title: "First")
    let b = graphItem("b", title: "Second")
    #expect(alice.toggle(a, extensionID: "com.test"))   // enqueued
    #expect(alice.toggle(b, extensionID: "com.test"))
    #expect(alice.items().map(\.itemID) == ["a", "b"])  // FIFO order preserved
    #expect(alice.next?.itemID == "a")
    #expect(alice.contains(a, extensionID: "com.test"))

    // Toggling again removes and reindexes.
    #expect(!alice.toggle(a, extensionID: "com.test"))
    #expect(alice.items().map(\.itemID) == ["b"])
    #expect(alice.items().first?.position == 0)

    // A different profile has an independent queue.
    let bob = WatchQueue(context: context, profileID: "bob")
    #expect(bob.items().isEmpty)
    bob.toggle(a, extensionID: "com.test")
    #expect(bob.items().count == 1)
    #expect(alice.items().count == 1) // unaffected
}

@MainActor
@Test func homeFeedAssemblesScopedSectionsAndOmitsEmpty() throws {
    let context = try makeExperienceContainer().mainContext

    // In-progress history → Continue Watching.
    context.insert(HistoryEntry(extensionID: "com.test", itemID: "h1", title: "Half-Watched", kind: "movie",
                                profileID: "alice", positionSeconds: 50, durationSeconds: 100))
    // A queued item → Up Next.
    WatchQueue(context: context, profileID: "alice").toggle(graphItem("q1", title: "Queued"), extensionID: "com.test")
    // A recently-added library item → Recently Added.
    context.insert(LibraryItem(extensionID: "com.test", itemID: "l1", title: "Saved", kind: "movie",
                               collection: .favorites, profileID: "alice"))

    let sections = HomeFeedBuilder(context: context, profileID: "alice").build()
    let ids = sections.map(\.id)
    #expect(ids.contains("continue"))
    #expect(ids.contains("queue"))
    #expect(ids.contains("recently-added"))
    #expect(sections.allSatisfy { !$0.items.isEmpty }) // no empty sections surfaced

    // A profile with no data gets an empty feed.
    #expect(HomeFeedBuilder(context: context, profileID: "empty").build().isEmpty)
}

// MARK: - Related Content ("More Like This")

@MainActor
@Test func relatedContentRanksBySimilarityAndExcludesSelf() throws {
    let context = try makeExperienceContainer().mainContext
    let graph = ContentGraph(context: context)

    // Seed the graph with a family of similar sci-fi titles plus an outlier.
    graph.ingest(graphItem("m1", title: "Blade Runner", genres: ["Science Fiction"], creators: ["Ridley Scott"]), extensionID: "com.test")
    graph.ingest(graphItem("m2", title: "Blade Runner 2049", genres: ["Science Fiction"], creators: ["Denis Villeneuve"]), extensionID: "com.test")
    graph.ingest(graphItem("z9", title: "A Cooking Show", genres: ["Food"]), extensionID: "com.test")

    let subject = graphItem("m1", title: "Blade Runner", genres: ["Science Fiction"], creators: ["Ridley Scott"])
    let related = RelatedContentService(context: context, policy: .unrestricted)
        .related(to: subject, extensionID: "com.test")

    #expect(!related.contains { $0.item.id == "m1" })     // never the subject itself
    #expect(related.first?.item.id == "m2")               // the sci-fi sibling ranks first
    #expect(related.allSatisfy { $0.item.id != "z9" || $0.score < related.first!.score }) // outlier ranks below
}

// MARK: - AI Platform (Phase 10): natural-language search

@Test func deterministicAssistantParsesGenresKindsAndKeywords() async {
    let intent = await DeterministicAIAssistant().interpretSearch("show me funny sci-fi movies about space")

    #expect(intent.genres.contains("Science Fiction"))
    #expect(intent.genres.contains("Comedy"))       // "funny" → Comedy via vocabulary
    #expect(intent.kinds == [.movie])
    #expect(intent.keywords.contains("space"))       // real subject survives
    #expect(!intent.keywords.contains("show"))       // filler stripped
    #expect(!intent.keywords.contains("movies"))     // kind word not a keyword
}

@Test func searchIntentBuildsQueryAndMatches() {
    let intent = SearchIntent(keywords: ["space"], genres: ["Science Fiction"], kinds: [.movie])
    #expect(intent.query(fallback: "x").contains("space"))
    #expect(intent.query(fallback: "x").contains("Science Fiction"))
    #expect(intent.summary.contains("movies"))

    let sciFiMovie = CatalogItem(id: "1", title: "Arrival", subtitle: nil, artworkUrl: nil, kind: .movie,
                                 metadata: nil, canonical: ContentMetadata(genres: ["Science Fiction"]))
    let comedyPodcast = CatalogItem(id: "2", title: "Chuckles", subtitle: nil, artworkUrl: nil, kind: .podcast,
                                    metadata: nil, canonical: ContentMetadata(genres: ["Comedy"]))
    #expect(intent.matches(sciFiMovie))
    #expect(!intent.matches(comedyPodcast))          // wrong kind and genre

    // An empty intent falls back to the raw query and matches anything.
    let empty = SearchIntent()
    #expect(empty.query(fallback: "raw") == "raw")
    #expect(empty.matches(comedyPodcast))
}

// MARK: - Provider Accounts (Providers + Accounts sprint)

@MainActor
@Test func accountsConnectDisconnectStateMachine() throws {
    let container = try ModelContainer(
        for: ProviderAccount.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let tokens = InMemoryTokenStore()
    let controller = AccountsController(context: context, tokenStore: tokens)

    // A networked provider seeds as "login required"; a local one as "connected".
    let networked = installedProvider(id: "com.test.net", domains: ["api.example.com"], website: "https://example.com")
    let local = installedProvider(id: "com.test.local", domains: [], website: nil)
    controller.reconcile(networked)
    controller.reconcile(local)

    #expect(controller.state(of: "com.test.net") == .loginRequired)
    #expect(controller.state(of: "com.test.local") == .connected)

    // Connecting the networked provider opens web auth (connecting).
    controller.connect("com.test.net")
    #expect(controller.state(of: "com.test.net") == .connecting)
    #expect(controller.authRequest?.providerID == "com.test.net")

    // Completing auth stores a token and marks it connected.
    controller.completeAuthentication(providerID: "com.test.net", token: "session:1")
    #expect(controller.state(of: "com.test.net") == .connected)
    #expect(tokens.token(for: "com.test.net") == "session:1")

    // Disconnect clears the token and drops back to login-required.
    controller.disconnect("com.test.net")
    #expect(controller.state(of: "com.test.net") == .loginRequired)
    #expect(tokens.token(for: "com.test.net") == nil)

    // Disable / enable toggles the disabled state.
    controller.setEnabled("com.test.local", false)
    #expect(controller.state(of: "com.test.local") == .disabled)
    controller.setEnabled("com.test.local", true)
    #expect(controller.state(of: "com.test.local") == .connected)
}

@MainActor
private func installedProvider(id: String, domains: [String], website: String?) -> InstalledExtension {
    let network = domains.isEmpty ? nil : PermissionDeclaration.NetworkPermission(domains: domains, allowUserConfiguredHost: false)
    let manifest = ExtensionManifest(
        id: id, displayName: id, version: SemanticVersion(major: 1, minor: 0, patch: 0),
        sdkVersion: SemanticVersion(major: 1, minor: 0, patch: 0),
        minimumRuntimeVersion: SemanticVersion(major: 1, minor: 0, patch: 0),
        website: website, entryPoint: "main.js",
        permissions: PermissionDeclaration(network: network, storage: nil),
        capabilities: [.search]
    )
    return InstalledExtension(manifest: manifest, entryPointSource: "", origin: "test",
                              logger: RuntimeLogger(extensionID: id), state: .ready)
}

// MARK: - YouTube provider (native API provider)

@Test func youTubeMapperNormalizesSearchAndDetails() throws {
    let searchJSON = """
    { "items": [
        { "id": { "videoId": "abc123" },
          "snippet": { "title": "Interstellar Trailer", "description": "Space epic",
                       "channelTitle": "Movie Trailers",
                       "thumbnails": { "high": { "url": "https://i.ytimg.com/hi.jpg" } },
                       "publishedAt": "2014-07-30T00:00:00Z", "tags": ["space", "sci-fi"] } },
        { "id": { "videoId": null }, "snippet": { "title": "A channel, skipped" } }
    ] }
    """
    let search = try JSONDecoder().decode(YTSearchResponse.self, from: Data(searchJSON.utf8))
    let items = YouTubeMapper.catalogItems(search)

    #expect(items.count == 1) // the channel result (no videoId) is dropped
    let item = try #require(items.first)
    #expect(item.id == "abc123")
    #expect(item.title == "Interstellar Trailer")
    #expect(item.subtitle == "Movie Trailers")
    #expect(item.kind == .video)
    #expect(item.artworkUrl == "https://i.ytimg.com/hi.jpg")
    #expect(item.resolvedMetadata.creators == ["Movie Trailers"])
    #expect(item.resolvedMetadata.topics.contains("space"))

    let videoJSON = """
    { "items": [
        { "id": "abc123",
          "snippet": { "title": "Interstellar Trailer", "description": "Space epic", "channelTitle": "Movie Trailers",
                       "thumbnails": { "medium": { "url": "https://i.ytimg.com/md.jpg" } } },
          "statistics": { "viewCount": "1000000" },
          "contentDetails": { "duration": "PT2M30S" } }
    ] }
    """
    let list = try JSONDecoder().decode(YTVideoListResponse.self, from: Data(videoJSON.utf8))
    let video = try #require(list.items.first)
    let details = YouTubeMapper.details(video)
    #expect(details.id == "abc123")
    #expect(details.kind == .video)
    #expect(details.artworkUrl == "https://i.ytimg.com/md.jpg") // falls back to medium thumbnail
    #expect(details.metadata?["viewCount"] == .string("1000000"))
    #expect(details.metadata?["duration"] == .string("PT2M30S"))
}

@MainActor
@Test func youTubeProviderReturnsEmbedStream() async throws {
    let streams = try await YouTubeProvider(apiKey: "test").streams(itemId: "abc123", episodeId: nil)
    #expect(streams.count == 1)
    #expect(streams.first?.format == "youtube")
    #expect(streams.first?.url.contains("youtube.com/embed/abc123") == true)
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

// MARK: - Plex provider (native self-hosted provider)

private let plexBase = URL(string: "https://192-168-1-2.hash.plex.direct:32400")!
private let plexToken = "TESTTOKEN"

private func decodePlex<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private let plexMovieJSON = """
{
  "ratingKey": "101", "key": "/library/metadata/101", "type": "movie", "title": "Dune",
  "summary": "Paul Atreides travels to Arrakis.", "year": 2021,
  "thumb": "/library/metadata/101/thumb/1", "art": "/library/metadata/101/art/1",
  "duration": 9360000, "contentRating": "PG-13", "rating": 8.1,
  "Genre": [{"tag": "Sci-Fi"}, {"tag": "Adventure"}],
  "Director": [{"tag": "Denis Villeneuve"}],
  "Role": [{"tag": "Timothee Chalamet"}, {"tag": "Zendaya"}],
  "Media": [{"id": 1, "videoResolution": "1080", "container": "mkv",
             "Part": [{"id": 9, "key": "/library/parts/9/file.mkv", "container": "mkv"}]}]
}
"""

@Test func plexMapperNormalizesMovie() throws {
    let movie = try decodePlex(PlexMetadata.self, plexMovieJSON)
    let item = PlexLibraryMapper.catalogItem(movie, base: plexBase, token: plexToken)

    #expect(item.id == "101")
    #expect(item.title == "Dune")
    #expect(item.subtitle == "2021")
    #expect(item.kind == .movie)
    #expect(item.artworkUrl == "https://192-168-1-2.hash.plex.direct:32400/library/metadata/101/thumb/1?X-Plex-Token=TESTTOKEN")
    #expect(item.resolvedMetadata.genres == ["Sci-Fi", "Adventure"])
    #expect(item.resolvedMetadata.creators == ["Denis Villeneuve"])
    #expect(item.resolvedMetadata.cast.contains("Zendaya"))
    #expect(item.resolvedMetadata.durationSeconds == 9360)

    let details = PlexLibraryMapper.details(movie, base: plexBase, token: plexToken)
    #expect(details.metadata?["overview"] == .string("Paul Atreides travels to Arrakis."))
    #expect(details.backdropUrl?.contains("/library/metadata/101/art/1") == true)
}

@Test func plexMapperFormatsEpisode() throws {
    let json = """
    {"ratingKey": "55", "type": "episode", "title": "Pilot", "grandparentTitle": "The Show",
     "parentIndex": 1, "index": 2, "duration": 1800000, "thumb": "/t"}
    """
    let episode = try decodePlex(PlexMetadata.self, json)
    let item = PlexLibraryMapper.catalogItem(episode, base: plexBase, token: plexToken)
    #expect(item.kind == .episode)
    #expect(item.title == "The Show — Pilot")
    #expect(item.subtitle == "S1 · E2")
}

@Test func plexKindMapping() {
    #expect(PlexLibraryMapper.kind(for: "movie") == .movie)
    #expect(PlexLibraryMapper.kind(for: "show") == .series)
    #expect(PlexLibraryMapper.kind(for: "episode") == .episode)
    #expect(PlexLibraryMapper.kind(for: "track") == .track)
    #expect(PlexLibraryMapper.kind(for: "artist") == .music)
    #expect(PlexLibraryMapper.kind(for: "banana") == .other)
}

@Test func plexPlaybackResolvesDirectURL() throws {
    let movie = try decodePlex(PlexMetadata.self, plexMovieJSON)
    let sources = PlexPlaybackResolver.streams(from: movie, base: plexBase, token: plexToken)
    let source = try #require(sources.first)
    #expect(sources.count == 1)
    #expect(source.url == "https://192-168-1-2.hash.plex.direct:32400/library/parts/9/file.mkv?X-Plex-Token=TESTTOKEN")
    #expect(source.quality == "1080p")
    #expect(source.format == "mkv")
}

@Test func plexPinDecodes() throws {
    let pending = try decodePlex(PlexPin.self, #"{"id": 123, "code": "ABCD"}"#)
    #expect(pending.id == 123)
    #expect(pending.authToken == nil)
    let authorized = try decodePlex(PlexPin.self, #"{"id": 123, "code": "ABCD", "authToken": "tok-xyz"}"#)
    #expect(authorized.authToken == "tok-xyz")
}

@Test func plexPickServerPrefersLocalHTTPS() throws {
    let json = """
    [{"name": "Home Server", "clientIdentifier": "srv1", "provides": "server",
      "accessToken": "srvtok", "productVersion": "1.40",
      "connections": [
        {"uri": "https://relay.plex.direct", "relay": true, "protocol": "https"},
        {"uri": "https://192-168-1-2.hash.plex.direct:32400", "local": true, "protocol": "https"}
      ]}]
    """
    let resources = try decodePlex([PlexResource].self, json)
    let connection = try #require(PlexSession.pickServer(resources))
    #expect(connection.name == "Home Server")
    #expect(connection.accessToken == "srvtok")
    #expect(connection.version == "1.40")
    #expect(connection.baseURL.absoluteString == "https://192-168-1-2.hash.plex.direct:32400")
}

@Test func plexEnvelopeAndHubDecode() throws {
    let container = try decodePlex(PlexEnvelope<PlexMetadataContainer>.self,
                                   #"{"MediaContainer": {"size": 1, "Metadata": [\#(plexMovieJSON)]}}"#)
    #expect(container.mediaContainer.metadata?.first?.title == "Dune")

    let hub = try decodePlex(PlexEnvelope<PlexHubContainer>.self,
                             #"{"MediaContainer": {"Hub": [{"type": "movie", "Metadata": [\#(plexMovieJSON)]}]}}"#)
    #expect(hub.mediaContainer.hub?.first?.metadata?.first?.ratingKey == "101")
}
