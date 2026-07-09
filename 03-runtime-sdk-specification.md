# Runtime SDK Specification

**Document 03 — Engineering Specification**
**Status:** Draft v0.1 — frozen for v1.0 once reviewed
**Depends on:** `00-product-vision.md`, ADR-001 (JS Runtime Lifecycle), ADR-004 (Publisher Trust Model), ADR-005 (Connector API Versioning)
**Consumed by:** Runtime Bridge (Swift), Connector SDK/CLI, every third-party connector author

---

## 0. Purpose and Scope

This document is the single source of truth for what a **connector** is, what it can do, and what the host app promises it in return. Nothing here is aspirational — every function, field, and error listed is either implemented in v1.0 or explicitly marked as deferred.

If the Swift implementation and this document ever disagree, this document is the bug report.

Out of scope for this doc (covered elsewhere): repository format (`06-repository-spec.md`), security enforcement mechanics (`05-security-model.md`), UI layer (`01-ui-design-system.md`), storage layout on disk (`07-storage-architecture.md`).

---

## 1. Conceptual Model

```
Repository
   └── Connector Package
          ├── manifest.json      (identity, permissions, apiVersion)
          └── index.js           (the Connector implementation)
```

A **connector** is a single JavaScript module, evaluated inside its own `JSContext`, that implements the `Connector` interface (§4). The host never executes connector code outside that sandboxed context, and never renders anything the connector returns except through the typed data contracts in §5.

One connector = one `JSContext`. No shared globals, no shared storage, no shared network state between connectors. This isolation is structural, not a runtime check — see ADR-001.

---

## 2. Connector Manifest

Every connector package ships a `manifest.json` alongside its `index.js`. The manifest is read by the Repository Manager **before** any connector code executes, and drives the permission prompt shown to the user at install time.

### 2.1 Schema

```json
{
  "id": "jellyfin-basic",
  "name": "Jellyfin",
  "version": "1.2.0",
  "apiVersion": 1,
  "entry": "index.js",
  "author": "someone",
  "description": "Connects to a self-hosted Jellyfin media server.",
  "kind": ["series", "movie"],
  "permissions": {
    "network": {
      "domains": ["*"],
      "allowUserConfiguredHost": true
    },
    "storage": {
      "maxBytes": 5242880
    }
  },
  "configSchema": [
    { "key": "serverUrl", "label": "Server URL", "type": "url", "required": true },
    { "key": "apiKey", "label": "API Key", "type": "secret", "required": true }
  ],
  "checksum": "sha256-...",
  "publisherKeyId": "publisher-abc",
  "signature": "ed25519-..."
}
```

### 2.2 Field Reference

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | ✅ | Stable, unique within a repository. Immutable across versions — this is the identity the Publisher Trust Model (ADR-004) pins a key to. |
| `name` | string | ✅ | Display name. |
| `version` | semver string | ✅ | Connector package version. |
| `apiVersion` | integer | ✅ | Which Connector SDK contract this targets (ADR-005). Host rejects install if outside its supported window. |
| `entry` | string | ✅ | Relative or absolute path/URL to the JS module. |
| `author` | string | ✅ | Free text. |
| `description` | string | ✅ | Shown in Repository Browser / Connector Details. |
| `kind` | `CatalogItem["kind"][]` | ✅ | Declares what content types this connector can return — drives Unified Search fan-out and Smart Collections filtering. |
| `permissions.network.domains` | string[] | ✅ | Allowlist. `"*"` means "any domain, including a user-configured host" and requires `allowUserConfiguredHost`. A connector requesting an undeclared domain at runtime is blocked — see §6.2. |
| `permissions.network.allowUserConfiguredHost` | boolean | — | Required alongside a wildcard domain when the connector talks to a self-hosted server the user provides (e.g. Jellyfin/Plex/Emby). Shown distinctly in the permission prompt ("This connector will contact a server you specify"). |
| `permissions.storage.maxBytes` | integer | ✅ | Quota enforced by the Bridge's storage mediation, not by the connector. |
| `configSchema` | `SettingsField[]` | — | Optional. If present, the Repository Manager renders a config form at install time (or via `getSettingsSchema()` — see §4.6) before `onInstall` runs. |
| `checksum` | string | ✅ | `sha256-<hex>` of the entry file. Enforced v1 (ADR-004). |
| `publisherKeyId` | string | v1.5+ | Identifies the signing key. TOFU-pinned per publisher on first install. |
| `signature` | string | v1.5+ | Ed25519 signature of the entry file, verified against the pinned key on every update. |

### 2.3 Manifest Validation Failure Modes

| Failure | Host behavior |
|---|---|
| Malformed JSON | Install blocked, "Invalid connector package" shown, connector never reaches JSContext |
| Missing required field | Install blocked, specific field named in error |
| `apiVersion` outside supported window | Install blocked (fresh install) or "Update Required" badge (existing install after app update) |
| Checksum mismatch | Install/update blocked, no code executed |
| Signature mismatch against pinned key (v1.5+) | Update blocked, warning shown, existing version kept running |

---

## 3. Lifecycle

### 3.1 States

```
   install()
      │
      ▼
 [Installed, Dormant]  ──first call (search/browse)──▶  [Warm]
      ▲                                                     │
      │                                                     │ 30–60s idle
      │                                                     │ OR app backgrounded
      │                                                     │ OR memory pressure
      └─────────────────── dispose() ◀─────────────────────┘
```

Per ADR-001, a connector's `JSContext` is created lazily on first real use (not at install time, not at app launch) and torn down after a natural idle window or an app-lifecycle signal. This is purely a performance optimization on top of full per-session isolation — it does not change any of the isolation guarantees in §6.

### 3.2 Lifecycle Hooks

| Hook | Called when | Required |
|---|---|---|
| `onInstall(config)` | Once, immediately after manifest validation passes and (if applicable) the user submits the config form. Runs in a short-lived JSContext created solely for this call. | No |
| *(implicit) first data call* | Creates the "warm" JSContext for the session. | — |
| *(implicit) dispose* | Host tears down the JSContext. Connector receives no callback — JS has no cleanup obligations; the VM is simply discarded. | — |

There is no `onUninstall`. Removing a connector is a Bridge/storage operation (deleting its namespaced storage and catalog rows), not a connector-code operation — this avoids ever having to trust untrusted code to clean up after itself.

### 3.3 Concurrency

- Calls into a single connector's JSContext are **serialized** by the Bridge. A connector never receives two concurrent calls.
- Calls to *different* connectors (e.g. during Unified Search fan-out) run in parallel, each in its own JSContext/thread.
- If a call is still running when the idle-teardown timer fires, teardown is deferred until the call resolves or times out (§6.3).

---

## 4. The `Connector` Interface

This is the exact TypeScript contract, reproduced from the architecture doc and expanded with the semantics each method must satisfy. The Connector SDK ships this as the canonical `.d.ts`.

```typescript
export interface Connector {
  search(query: string, page?: number): Promise<CatalogItem[]>;
  browse?(category: string, page?: number): Promise<CatalogItem[]>;
  getDetails(id: string): Promise<MediaDetails>;
  getStreams(itemId: string, episodeId?: string): Promise<StreamSource[]>;
  onInstall?(config: ConnectorConfig): Promise<void>;
  getSettingsSchema?(): SettingsField[];
}
```

### 4.1 `search(query, page?)`

- **Purpose:** Free-text search. Backs both the connector's own results tab and Unified Search fan-out.
- **Contract:** Must return within the Bridge's call timeout (default 10s, see §6.3). Empty/no-match results return `[]`, never throw.
- **Pagination:** `page` is 1-indexed and optional; omitted means page 1. A connector that doesn't support pagination simply ignores additional page requests and may return `[]` for `page > 1`.
- **Errors:** Network/parse failures throw a `ConnectorError` (§7). The Bridge catches this per-connector during fan-out so one failing connector doesn't fail Unified Search as a whole.

### 4.2 `browse(category, page?)` — optional

- **Purpose:** Category/genre browsing without a search query (e.g. "Trending", "New Releases" tabs in Discover).
- **Contract:** Same pagination and timeout rules as `search`. Connectors that don't support browsing simply omit this method; the Bridge detects its absence via `typeof connector.browse === "function"` and hides browse-driven UI for that connector.
- Valid `category` strings are connector-defined but should be documented in the connector's own README; the host does not validate category names against a fixed enum.

### 4.3 `getDetails(id)`

- **Purpose:** Full metadata for a single `CatalogItem`, including its episode list if applicable.
- **Contract:** `id` is always a value the host previously received from that same connector (via `search`/`browse`), never a value invented by the host or passed cross-connector. Must throw `ConnectorError` with code `NOT_FOUND` if the id no longer resolves (e.g. removed upstream).

### 4.4 `getStreams(itemId, episodeId?)`

- **Purpose:** Resolve one or more playable `StreamSource`s for an item (or a specific episode of a series).
- **Contract:** This is the only method the Player Engine calls directly before playback. Must return at least one `StreamSource` or throw. If multiple qualities/sources are available, return all of them — quality selection is host-native UI, not a connector decision.
- **Timeout:** Same default as other calls, but the host UI shows a distinct "Resolving stream…" state for this call specifically, since it's the one on the critical path to playback.

### 4.5 `onInstall(config)` — optional

- **Purpose:** One-time setup — e.g. validating a Jellyfin server URL/API key against the real server before the connector is considered "installed."
- **Contract:** Receives the values collected via `configSchema`/`getSettingsSchema()`. Throwing here aborts installation and surfaces the error message to the user; nothing is persisted.

### 4.6 `getSettingsSchema()` — optional

- **Purpose:** Lets a connector define/redefine its config form dynamically instead of (or in addition to) the static `configSchema` in the manifest. Called at install time and whenever the user opens the connector's Settings screen.
- **Contract:** Pure function, no side effects, no network/storage access. Returns `SettingsField[]` (§5.6).

---

## 5. Data Contracts

All types below are the wire contract between connector and host. The host validates every return value against these shapes before it touches the Catalog DB or UI layer — a connector returning a malformed object gets that specific call rejected with a `ConnectorError` (`INVALID_RESPONSE`), not a crash.

### 5.1 `CatalogItem`

```typescript
export interface CatalogItem {
  id: string;
  title: string;
  subtitle?: string;
  artworkUrl?: string;
  kind: "series" | "movie" | "episode" | "podcast" | "track" | "stream" | "other";
  metadata?: Record<string, string | number | boolean>;
}
```

**Example:**
```json
{
  "id": "tt1877830",
  "title": "The Batman",
  "subtitle": "2022 · Action, Crime",
  "artworkUrl": "https://cdn.example.com/posters/tt1877830.jpg",
  "kind": "movie",
  "metadata": { "year": 2022, "rating": "PG-13" }
}
```

### 5.2 `MediaDetails`

```typescript
export interface MediaDetails extends CatalogItem {
  description?: string;
  episodes?: EpisodeRef[];
  tags?: string[];
  releaseDate?: string;
}
```

### 5.3 `EpisodeRef`

```typescript
export interface EpisodeRef {
  id: string;
  title: string;
  number?: number;
  seasonNumber?: number;
  durationSec?: number;
  // Optional, per ADR-002, for Skip Intro/Outro:
  intro?: { start: number; end: number };
  credits?: { start: number };
}
```

**Example:**
```json
{
  "id": "s01e05",
  "title": "The Bells",
  "number": 5,
  "seasonNumber": 1,
  "durationSec": 2760,
  "intro": { "start": 0, "end": 78 },
  "credits": { "start": 2640 }
}
```

If `intro`/`credits` are omitted, Skip Intro/Outro falls through to the community timestamp lookup per ADR-002 — a connector is never required to supply these.

### 5.4 `StreamSource`

```typescript
export interface StreamSource {
  url: string;
  quality?: string;        // e.g. "1080p", "720p", "auto"
  type?: "hls" | "dash" | "progressive";
  headers?: Record<string, string>;   // sent by the Player Engine when requesting this URL
  audioTrack?: string;
  subtitles?: SubtitleTrack[];
}

export interface SubtitleTrack {
  url: string;
  language: string;     // BCP-47, e.g. "en", "pt-BR"
  label?: string;
  format?: "vtt" | "srt";
}
```

`headers` exists specifically for sources requiring an auth header (self-hosted servers). The Bridge attaches these headers only to requests to the domain that returned them — see §6.2.

### 5.5 `ConnectorConfig`

```typescript
export type ConnectorConfig = Record<string, string | number | boolean>;
```

Keyed by the `key` values from `configSchema`/`getSettingsSchema()`. Values are whatever the corresponding `SettingsField.type` produces (string for `text`/`url`/`secret`, boolean for `toggle`, etc.).

### 5.6 `SettingsField`

```typescript
export interface SettingsField {
  key: string;
  label: string;
  type: "text" | "url" | "secret" | "toggle" | "select" | "number";
  required?: boolean;
  options?: string[];       // for type: "select"
  defaultValue?: string | number | boolean;
}
```

`secret` fields are stored in the connector's namespaced Keychain-backed slice of storage (§6.4), never in plain preferences, and are masked in the Developer Console's Storage Viewer.

---

## 6. The Runtime Bridge Surface

Connector code does not get raw access to `fetch`, `XMLHttpRequest`, `localStorage`, or any native iOS API. Everything a connector can do goes through a small, explicit `Runtime` global injected into its `JSContext`. This is the entire attack surface, and it's intentionally small.

```typescript
declare const Runtime: {
  request(input: RuntimeRequest): Promise<RuntimeResponse>;
  storage: {
    get(key: string): Promise<string | null>;
    set(key: string, value: string): Promise<void>;
    delete(key: string): Promise<void>;
  };
  log(...args: unknown[]): void;
};
```

### 6.1 `Runtime.request`

```typescript
interface RuntimeRequest {
  url: string;
  method?: "GET" | "POST" | "PUT" | "DELETE" | "HEAD";
  headers?: Record<string, string>;
  body?: string;
  timeoutMs?: number;   // capped at the Bridge's max (see §6.3)
}

interface RuntimeResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}
```

This is the *only* network primitive available. No raw sockets, no WebSocket, no arbitrary TCP — see the Security Model doc for the full allowed/disallowed matrix.

### 6.2 Domain Allowlist Enforcement

Every `Runtime.request` call is checked against the manifest's `permissions.network.domains` **before** the request leaves the device:

- Exact domains (e.g. `"api.themoviedb.org"`) — request allowed only to that host.
- `"*"` with `allowUserConfiguredHost: true` — request allowed to any host, but the UI has already told the user this connector talks to an arbitrary/self-hosted server at install time.
- A request to a domain not covered by either → rejected at the Bridge, connector receives a `ConnectorError` with code `PERMISSION_DENIED`, and the attempt is logged to the Developer Console's HTTP Inspector as a blocked request (useful both for connector-author debugging and for spotting misbehaving connectors).

### 6.3 Timeouts

| Operation | Default | Configurable? |
|---|---|---|
| Any single `Runtime.request` | 10s | Connector may request less via `timeoutMs`, never more |
| Any `Connector` interface method (`search`, `getDetails`, etc.) — wall-clock budget for the whole call, including multiple internal requests | 15s | No |
| JSContext idle teardown | 30–60s (ADR-001) | Host-tunable, not connector-tunable |

Exceeding either timeout throws `ConnectorError` with code `TIMEOUT` and — per ADR-001 — does not affect any other connector's running context.

### 6.4 `Runtime.storage`

- Fully namespaced per connector `id`. Connector A cannot read, enumerate, or overwrite Connector B's keys — enforced by the Bridge, not by convention.
- Backed by on-device storage (SQLite-backed key/value, `secret`-typed config values routed to Keychain).
- Bound by `permissions.storage.maxBytes` from the manifest; writes past quota throw `ConnectorError` (`STORAGE_QUOTA_EXCEEDED`).
- Values are strings — connectors serialize their own JSON if they need structured data.

### 6.5 What Is Deliberately Absent

No DOM, no `fetch`/`XMLHttpRequest` globals, no `eval` of further remote code, no filesystem access, no access to other connectors' JSContexts, no access to host app state beyond what's explicitly passed into a method call. A connector is a pure function of (its own storage) + (the network responses it fetches) + (its call arguments) → (typed data).

---

## 7. Error Model

All errors a connector throws (or that the Bridge synthesizes on its behalf) are normalized to a single shape before reaching host code:

```typescript
interface ConnectorError {
  code: ConnectorErrorCode;
  message: string;       // human-readable, may be shown in UI
  cause?: string;        // optional raw detail, Developer Console only
}

type ConnectorErrorCode =
  | "NOT_FOUND"
  | "PERMISSION_DENIED"
  | "TIMEOUT"
  | "INVALID_RESPONSE"
  | "STORAGE_QUOTA_EXCEEDED"
  | "UPSTREAM_ERROR"       // the connector's source (e.g. self-hosted server) returned an error
  | "AUTH_REQUIRED"        // e.g. expired Jellyfin token — host can prompt to re-auth
  | "UNKNOWN";
```

Connector authors may throw a plain `Error` from JS — the Bridge maps it to `UNKNOWN` with the original message preserved as `cause`. Throwing a structured error (via a small helper the SDK provides, e.g. `RuntimeError.notFound("...")`) is preferred and produces better UI ("Sign in again" for `AUTH_REQUIRED` vs. a generic failure toast).

Errors during Unified Search fan-out are collected per-connector and never abort the overall search — a single failing/misbehaving connector degrades gracefully to "0 results from X" rather than breaking the page.

---

## 8. Versioning (ADR-005 in practice)

- Every manifest declares `apiVersion` as an integer.
- The host app, at any given release, supports a **window** of API versions (e.g. app v2.0 supports API versions 1 and 2).
- When a future release drops support for an old `apiVersion`, the Connector Manager detects affected installs at launch and shows an explicit **"Update Required"** state — the connector stops receiving calls but is not silently deleted, and its cached catalog data remains visible (grayed out) until updated or removed.
- Within a single `apiVersion`, the SDK contract is **additive-only**: new optional methods/fields may be introduced; existing required methods/fields never change shape or semantics. A breaking change always means a new `apiVersion`.

---

## 9. Minimal Reference Implementation (illustrative)

This is *not* the Golden Connector (that's its own artifact per the SDLC plan) — just enough to show the contract end-to-end for a trivial RSS-style source.

```javascript
const connector = {
  async search(query, page = 1) {
    const res = await Runtime.request({
      url: `https://api.example-podcasts.com/search?q=${encodeURIComponent(query)}&page=${page}`
    });
    const data = JSON.parse(res.body);
    return data.results.map(r => ({
      id: r.id,
      title: r.title,
      artworkUrl: r.artwork,
      kind: "podcast"
    }));
  },

  async getDetails(id) {
    const res = await Runtime.request({ url: `https://api.example-podcasts.com/show/${id}` });
    const d = JSON.parse(res.body);
    return {
      id: d.id,
      title: d.title,
      kind: "podcast",
      description: d.description,
      episodes: d.episodes.map(e => ({ id: e.id, title: e.title, durationSec: e.duration }))
    };
  },

  async getStreams(itemId, episodeId) {
    const res = await Runtime.request({ url: `https://api.example-podcasts.com/episode/${episodeId}/stream` });
    const d = JSON.parse(res.body);
    return [{ url: d.streamUrl, type: "progressive" }];
  }
};

export default connector;
```

---

## 10. Open Questions for Review

These are flagged rather than silently decided, since they affect every connector author downstream:

1. Should `search()` and `browse()` share a single result-caching layer keyed by `(connectorId, query|category, page)`, or is that entirely a host-side Catalog DB concern with no SDK implication? *(Leaning: host-side only — keep the SDK surface unopinionated about caching.)*
2. Do we need a `refreshDetails(id)` distinct from `getDetails(id)` for connectors whose upstream data changes frequently (e.g. live episode counts), or is re-calling `getDetails` sufficient given the JSContext warm-cache window is short anyway? *(Leaning: no new method — re-call is sufficient.)*
3. Should `getSettingsSchema()` be allowed to differ from the manifest's static `configSchema`, or should the manifest version be considered the fallback only when the connector fails to load far enough to call `getSettingsSchema()`? Needs one clear precedence rule stated explicitly before the Connector SDK CLI ships a scaffold that gets this wrong.

---

## Appendix A — Full `.d.ts` (SDK Source of Truth)

```typescript
export interface Connector {
  search(query: string, page?: number): Promise<CatalogItem[]>;
  browse?(category: string, page?: number): Promise<CatalogItem[]>;
  getDetails(id: string): Promise<MediaDetails>;
  getStreams(itemId: string, episodeId?: string): Promise<StreamSource[]>;
  onInstall?(config: ConnectorConfig): Promise<void>;
  getSettingsSchema?(): SettingsField[];
}

export interface CatalogItem {
  id: string;
  title: string;
  subtitle?: string;
  artworkUrl?: string;
  kind: "series" | "movie" | "episode" | "podcast" | "track" | "stream" | "other";
  metadata?: Record<string, string | number | boolean>;
}

export interface MediaDetails extends CatalogItem {
  description?: string;
  episodes?: EpisodeRef[];
  tags?: string[];
  releaseDate?: string;
}

export interface EpisodeRef {
  id: string;
  title: string;
  number?: number;
  seasonNumber?: number;
  durationSec?: number;
  intro?: { start: number; end: number };
  credits?: { start: number };
}

export interface StreamSource {
  url: string;
  quality?: string;
  type?: "hls" | "dash" | "progressive";
  headers?: Record<string, string>;
  audioTrack?: string;
  subtitles?: SubtitleTrack[];
}

export interface SubtitleTrack {
  url: string;
  language: string;
  label?: string;
  format?: "vtt" | "srt";
}

export type ConnectorConfig = Record<string, string | number | boolean>;

export interface SettingsField {
  key: string;
  label: string;
  type: "text" | "url" | "secret" | "toggle" | "select" | "number";
  required?: boolean;
  options?: string[];
  defaultValue?: string | number | boolean;
}

export type ConnectorErrorCode =
  | "NOT_FOUND"
  | "PERMISSION_DENIED"
  | "TIMEOUT"
  | "INVALID_RESPONSE"
  | "STORAGE_QUOTA_EXCEEDED"
  | "UPSTREAM_ERROR"
  | "AUTH_REQUIRED"
  | "UNKNOWN";

export interface ConnectorError {
  code: ConnectorErrorCode;
  message: string;
  cause?: string;
}
```
