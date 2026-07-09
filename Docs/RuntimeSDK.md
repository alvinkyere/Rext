# Runtime SDK v1

The stable contract for building **Runtime extensions**. An extension is a
packaged directory containing a manifest and a JavaScript entry point. The host
installs, validates, loads, and executes extensions inside an isolated JavaScript
engine, enforcing every security boundary in Swift. This document is the
authoritative reference — an extension author should be able to build a working
extension from this page alone.

---

## 1. Package format

Every extension is a directory whose name ends in `.runtime`:

```
PodcastRSS.runtime/
  manifest.json     # required — canonical metadata, permissions, capabilities
  main.js           # required — the entry point (name set by manifest.entryPoint)
  icon.png          # optional — declared via manifest.icon
  LICENSE           # optional
  README.md         # optional
  assets/           # optional — bundled resources
```

Loose `.js` files are **not** installable. Only a directory with a valid
`manifest.json` is an extension. Packages may also be delivered as an archive in
a future release; the installer is source-agnostic (`PackageSource`), so the
origin never affects installation.

---

## 2. Manifest (`manifest.json`)

| Field                   | Type        | Required | Description |
|-------------------------|-------------|----------|-------------|
| `id`                    | string      | ✓        | Reverse-DNS unique id, e.g. `com.runtime.podcast-rss`. |
| `displayName`           | string      | ✓        | Human-readable name. |
| `version`               | semver      | ✓        | The extension's version. |
| `sdkVersion`            | semver      | ✓        | SDK contract the extension targets. |
| `minimumRuntimeVersion` | semver      | ✓        | Minimum host version required. |
| `entryPoint`            | string      | ✓        | Package-relative JS file, e.g. `main.js`. |
| `permissions`           | object      | ✓        | Declared permissions (may be `{}`). |
| `capabilities`          | string[]    | ✓        | Declared capabilities. |
| `author`                | string      | –        | Author / publisher name. |
| `description`           | string      | –        | Short description. |
| `website`               | string      | –        | Homepage URL. |
| `repository`            | string      | –        | Source repository URL. |
| `category`              | string      | –        | One of the known categories; unknown → `other`. |
| `icon`                  | string      | –        | Package-relative icon path. |

**Versions** are strict Semantic Versioning 2.0.0 (`MAJOR.MINOR.PATCH`, optional
`-prerelease` / `+build`). **Forward compatibility:** unknown top-level fields are
ignored, unknown categories degrade to `other`, and every non-essential field is
optional, so future SDK versions can add fields without breaking older runtimes
or extensions.

Example:

```json
{
  "id": "com.runtime.podcast-rss",
  "displayName": "Podcast RSS",
  "version": "1.0.0",
  "sdkVersion": "1.0.0",
  "minimumRuntimeVersion": "1.0.0",
  "author": "Runtime Official",
  "category": "media",
  "entryPoint": "main.js",
  "permissions": {
    "network": { "domains": ["api.example-podcasts.com"], "allowUserConfiguredHost": false },
    "storage": { "maxBytes": 65536 }
  },
  "capabilities": ["search", "details", "streams"]
}
```

---

## 3. Permissions (enforced in Swift)

An extension may only use what it declares. Enforcement is **total by
construction** and never trusts JavaScript.

| Permission        | Shape | Enforcement |
|-------------------|-------|-------------|
| `network`         | `{ "domains": [String], "allowUserConfiguredHost": Bool? }` | Requests to hosts outside `domains` are blocked; redirects are re-checked. **No `network` ⇒ every request blocked.** |
| `storage`         | `{ "maxBytes": Int }` | Writes exceeding the budget are rejected. **No `storage` ⇒ every write rejected.** |
| `cache`           | `{ "maxBytes": Int }` | Reserved (declaration only in v1). |
| `cookies`         | `Bool` | Reserved. |
| `backgroundTasks` | `Bool` | Reserved. |
| `notifications`   | `Bool` | Reserved (future). |
| `downloads`       | `Bool` | Reserved (future). |

---

## 4. Capabilities

An extension declares which operations it supports; the host never assumes. The
engine gates each call on the declaration, and the UI can adapt to the declared
set.

| Capability        | Method invoked                    | Status |
|-------------------|-----------------------------------|--------|
| `search`          | `search(query, page?)`            | active |
| `details`         | `getDetails(id)`                  | active |
| `streams`         | `getStreams(itemId, episodeId?)`  | active |
| `downloads`       | —                                 | reserved |
| `recommendations` | —                                 | reserved |
| `subtitles`       | —                                 | reserved |
| `authentication`  | —                                 | reserved |

Calling an operation whose capability is not declared fails with
`capabilityNotSupported` before any JavaScript runs.

---

## 5. Lifecycle

```
Install → Validate → Initialize → (Search | Details | Resolve)* → Dispose
```

- **Install** — bytes acquired from a `PackageSource`; nothing executed.
- **Validate** — manifest parsed; required fields, versions, SDK/runtime
  compatibility, duplicate id, and permission/capability validity checked. On
  failure the extension never advances.
- **Initialize** — a fresh `JSVirtualMachine`/`JSContext` is created lazily on
  first use and the entry point is evaluated in isolation.
- **Ready** — the extension serves requests.
- **Search/Details/Resolve** — capability- and permission-gated execution
  (“Resolve” = `getStreams`).
- **Dispose** — the context is torn down on idle timeout, memory pressure, or
  explicit teardown; it re-initializes transparently on the next request.

---

## 6. The JavaScript contract

The entry point runs in an isolated context whose **only** host capabilities are
on the injected `Runtime` global. There is no `fetch`, filesystem, DOM, or access
to other extensions.

```js
Runtime.request({ url, method?, headers?, body?, timeoutMs? })
  // → Promise<{ status: number, headers: object, body: string }>
Runtime.storage.get(key)        // → Promise<string | null>
Runtime.storage.set(key, value) // → Promise<void>  (rejects if over quota)
Runtime.storage.delete(key)     // → Promise<void>
Runtime.log(...args)            // → void
```

The extension must assign an object to `globalThis.connectorInstance`
implementing the methods for its declared capabilities:

```js
globalThis.connectorInstance = {
  async search(query, page) { /* → CatalogItem[]  */ },
  async getDetails(id)      { /* → MediaDetails   */ },
  async getStreams(itemId, episodeId) { /* → StreamSource[] */ }
};
```

Return values must match the data contracts (`CatalogItem`, `MediaDetails`,
`StreamSource`); a mismatch is rejected as `INVALID_RESPONSE`. `metadata` values
must be JSON scalars (string, number, or boolean).

---

## 7. Errors

Two distinct, strongly-typed families:

**`ConnectorError`** — the JavaScript execution boundary (returned to callers/UI).
Codes: `NOT_FOUND`, `PERMISSION_DENIED`, `TIMEOUT`, `INVALID_RESPONSE`,
`STORAGE_QUOTA_EXCEEDED`, `UPSTREAM_ERROR`, `AUTH_REQUIRED`, `UNKNOWN`. An
extension raises one by throwing an `Error` carrying a `code` property:

```js
function fail(code, message) { var e = new Error(message); e.code = code; return e; }
throw fail("NOT_FOUND", "No such show");
```

**`RuntimeError`** — the platform boundary (install/validate/lifecycle):
`manifestMissing`, `manifestUnreadable`, `manifestInvalid`, `missingRequiredField`,
`invalidVersion`, `entryPointMissing`, `sdkIncompatible`, `runtimeIncompatible`,
`duplicateExtensionID`, `unknownPermission`, `unknownCapability`,
`permissionNotDeclared`, `capabilityNotSupported`, `notInstalled`,
`executionFailed`. Nothing fails silently.

---

## 8. Host API (Swift)

```swift
let engine = RuntimeEngine.shared

// Install from disk (or any PackageSource).
try await engine.install(from: DirectoryPackageSource(directory: url))

// Discover.
await engine.installedExtensions            // [InstalledExtension]
try await engine.capabilities(of: id)       // Set<Capability>
await engine.defaultExtensionID(supporting: .search)

// Execute (capability- & permission-gated).
try await engine.search(id, query: "history")
try await engine.details(id, itemId: "show-42")
try await engine.streams(id, itemId: "show-42", episodeId: "ep-1001")

// Teardown.
await engine.disposeAll()
```

Components (loosely coupled): **RuntimeEngine** (facade + lifecycle + gating),
**RuntimeHost** (live runtime instances), **RuntimeBridge / ConnectorRuntime**
(isolated execution + security boundary), **PackageInstaller**, **ManifestParser**,
**ExtensionValidator**, **ExtensionRegistry**, and structured **RuntimeLogger** /
**LogBus** (per-extension logs ready for a future Developer Console).

---

## 9. Logging

Every extension has its own `RuntimeLogger`. Events are structured
(`extensionID`, `category`, `level`, `message`, `metadata`) and fan out through
`LogBus` to registered `LogSink`s, with a bounded in-memory history a future
Developer Console can read. Categories: `install`, `load`, `initialize`,
`network`, `error`, `warning`, `performance`, `general`.

---

## 10. Repositories

A `repository.json` (`Repository`) describes a `Publisher` and its
`ExtensionListing`s, each with `RepositoryVersion`s carrying a `downloadURL`, a
`RepositoryChecksum`, and an optional `RepositorySignature`. The runtime is
designed to aggregate multiple repositories (official, personal, company,
university) with publisher verification in a later milestone.

`RepositoryService` implements discovery and installation:

```
fetch repository.json → compare versions → download package
  → verify SHA-256 checksum → install through the engine → register
```

```swift
let service = RepositoryService(sessionConfiguration: SampleRepository.sessionConfiguration())
let repo = try await service.fetchRepository(at: url)
let updates = service.availableUpdates(in: repo, installed: await engine.installedExtensions)
let doc = try await service.fetchPackage(version, from: listing)   // for permission review
try await service.install(version, from: listing, into: engine)    // download+verify+install
```

**Checksums are verified** (CryptoKit SHA-256); a mismatch throws
`RuntimeError.checksumMismatch`. Cryptographic **signatures** remain a future
milestone (the model exists).

## 11. Extension package transport

A downloadable extension is an **`ExtensionPackageDocument`** — a single JSON
document with the `manifest`, the `entryPoint` JavaScript as text, and optional
base64 `assets`. It installs through the same origin-agnostic `PackageInstaller`
via `PackageDocumentSource` (a `PackageSource`), so directory, bundle, document,
and future zip origins all share one install path. This keeps the transport
dependency-free (URLSession + Foundation only).

The bundled **sample repository** (`SampleRepository` + `BundledRepositoryURLProtocol`)
serves a working repo offline over a custom `rext-repo://` scheme, derived from
the bundled PodcastRSS package with a real computed checksum — no server required.

## 12. Host-side extension contract (`RextExtension`)

The engine programs against a host-side protocol; every installed extension is
presented uniformly, regardless of implementation:

```swift
protocol RextExtension: Sendable {
    var id: String { get }
    func initialize(context: RextExtensionContext) async
    func search(query: String, page: Int?) async throws -> [CatalogItem]
    func getDetails(id: String) async throws -> MediaDetails
    func getEpisodes(id: String) async throws -> [CatalogItem]
    func getStreams(itemId: String, episodeId: String?) async throws -> [StreamSource]
    func execute(action: String, payload: [String: JSONScalar]) async throws -> RextResponse
}
```

Today the sole implementation is **`JSExtension`**, which adapts a sandboxed
`ConnectorRuntime` to this protocol — the only way to ship third-party,
install-without-an-app-update extensions on iOS. `execute` is the open,
source-specific hook (still fully permission-gated). `RextItem`/`RextEpisode`/
`RextDetails`/`RextStream`/`ContentType` are SDK aliases for the existing
standardized models; `RextResponse` is the flexible `execute` envelope.

The **Extension Manager** UI (`ExtensionManagerView`) browses the repository and
installs/updates/removes extensions, showing a **permission-review** sheet (the
extension's declared capabilities, permissions, and network hosts) before any
install commits.
