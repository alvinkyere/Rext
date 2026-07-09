# Data Contracts

**Document 04 — Engineering Specification**
**Status:** Draft v0.1 — frozen for v1.0 once reviewed
**Depends on:** `03-runtime-sdk-specification.md`, `06-repository-spec.md`, ADR-003 (Backend Abstraction), ADR-004 (Publisher Trust Model)
**Consumed by:** Repository Manager, Catalog DB, Download Store, Notification dispatch, Cloud Sync adapter, Backup import/export

---

## 0. Purpose and Scope

Doc 03 (Runtime SDK) defines the contract **between a connector and the host**. This document defines every *other* JSON shape in the system — the ones the host produces, persists, syncs, or exchanges with its own backend.

**Non-goal:** re-documenting connector-facing types. `CatalogItem`, `MediaDetails`, `EpisodeRef`, `StreamSource`, and `SubtitleTrack` are owned by doc 03. Where they appear below (e.g. embedded in a backup), this doc references them rather than redefining them. If a connector type and its description here ever diverge, doc 03 wins.

Every contract below is given as (a) a TypeScript interface and (b) a real JSON example. The host validates against these before persistence — a malformed object is rejected at its boundary, never written half-formed into the Catalog DB.

### 0.1 Conventions

- **Timestamps** are ISO-8601 UTC strings (`"2026-02-14T09:31:00Z"`) on the wire. On-disk they may be stored as epoch millis; the wire/backup format is always ISO-8601.
- **Durations / positions** are integer **seconds** unless the field name ends in `Ms`.
- **Sizes** are integer **bytes**.
- **IDs** are opaque strings. Connector-scoped IDs are only ever meaningful in combination with their `connectorId` (see §1.1).
- A field marked optional (`?`) may be absent or `null` — consumers must treat both identically.

---

## 1. Identity & Provenance

### 1.1 The `(connectorId, id)` pair

Every piece of media in the system is identified by the pair **`connectorId` + the connector-local `id`**. A raw `id` alone is meaningless and must never be passed across connectors — this is both a correctness rule (two connectors can legitimately use `"tt1877830"`) and a security invariant (doc 03 §6.5: a connector only ever receives IDs it previously issued).

```typescript
interface MediaRef {
  connectorId: string;   // which connector this belongs to
  id: string;            // connector-local CatalogItem id
  episodeId?: string;    // connector-local EpisodeRef id, when referring to an episode
}
```

`MediaRef` is the join key threaded through WatchState, Favorite, DownloadRecord, Follow, and Notification. Everything traces back to it.

---

## 2. Repository Contract

Full detail lives in `06-repository-spec.md`; the shape is reproduced here as the canonical data contract so this doc is self-contained for anyone wiring up the Repository Manager.

```typescript
interface Repository {
  schemaVersion: number;
  name: string;
  maintainer: string;
  connectors: RepositoryConnectorEntry[];
}

interface RepositoryConnectorEntry {
  id: string;
  name: string;
  version: string;          // semver
  apiVersion: number;       // ADR-005
  entry: string;            // URL to index.js
  manifestUrl: string;      // URL to manifest.json
  checksum: string;         // "sha256-..."
  publisherKeyId?: string;  // v1.5+
  signature?: string;       // v1.5+, ed25519 over the entry file
}
```

**Example:**
```json
{
  "schemaVersion": 1,
  "name": "Community Connectors",
  "maintainer": "someone",
  "connectors": [
    {
      "id": "jellyfin-basic",
      "name": "Jellyfin",
      "version": "1.2.0",
      "apiVersion": 1,
      "entry": "https://cdn.example.com/connectors/jellyfin-basic/1.2.0/index.js",
      "manifestUrl": "https://cdn.example.com/connectors/jellyfin-basic/1.2.0/manifest.json",
      "checksum": "sha256-8f14e45fceea167a5a36dedd4bea2543",
      "publisherKeyId": "publisher-abc",
      "signature": "ed25519-3045022100b2..."
    }
  ]
}
```

The `manifest.json` each entry points to follows the schema in doc 03 §2.

---

## 3. Catalog Contracts (persisted, host-owned)

These mirror the Catalog DB tables from the architecture doc §4.6 and are the normalized, persisted form of what connectors return. The connector returns a `CatalogItem`/`MediaDetails` (doc 03 §5); the host stamps it with provenance and persistence metadata to produce these.

### 3.1 `StoredCatalogItem`

```typescript
interface StoredCatalogItem {
  connectorId: string;
  item: CatalogItem;         // doc 03 §5.1 — verbatim connector output
  lastSeenAt: string;        // ISO-8601 — last time a connector call returned this
}
```

**Example:**
```json
{
  "connectorId": "jellyfin-basic",
  "item": {
    "id": "a1b2c3",
    "title": "The Batman",
    "subtitle": "2022 · Action, Crime",
    "artworkUrl": "https://media.local/posters/a1b2c3.jpg",
    "kind": "movie",
    "metadata": { "year": 2022, "rating": "PG-13" }
  },
  "lastSeenAt": "2026-02-14T09:31:00Z"
}
```

### 3.2 `WatchState`

Drives Continue Watching and Resume Playback.

```typescript
interface WatchState {
  ref: MediaRef;
  positionSec: number;       // current playback position
  durationSec: number;       // total known duration
  finished: boolean;         // true once within the credits / past a completion threshold
  updatedAt: string;         // ISO-8601 — the sync merge key (§7)
}
```

**Example:**
```json
{
  "ref": { "connectorId": "jellyfin-basic", "id": "a1b2c3", "episodeId": "s01e05" },
  "positionSec": 742,
  "durationSec": 2760,
  "finished": false,
  "updatedAt": "2026-02-14T09:48:12Z"
}
```

### 3.3 `Favorite`

```typescript
interface Favorite {
  ref: MediaRef;
  addedAt: string;           // ISO-8601
}
```

---

## 4. Download Contract

The `DownloadRecord` is host-owned and never touches connector code — the connector's only role is resolving the `StreamSource` (doc 03 §5.4); the host manages the download itself.

```typescript
interface DownloadRecord {
  ref: MediaRef;
  title: string;             // denormalized for offline display when the connector is dormant/removed
  artworkUrl?: string;       // denormalized for the same reason
  source: StreamSource;      // doc 03 §5.4 — the resolved source being fetched
  localPath: string;         // app-sandbox relative path
  sizeBytes: number;         // total, once known; 0 while unknown
  downloadedBytes: number;   // progress
  status: DownloadStatus;
  createdAt: string;
  completedAt?: string;
  error?: ConnectorError;    // doc 03 §7, present only when status === "failed"
}

type DownloadStatus =
  | "queued"
  | "downloading"
  | "paused"
  | "completed"
  | "failed";
```

**Example (in progress):**
```json
{
  "ref": { "connectorId": "jellyfin-basic", "id": "a1b2c3", "episodeId": "s01e05" },
  "title": "The Bells",
  "artworkUrl": "https://media.local/posters/a1b2c3.jpg",
  "source": { "url": "https://server.local/stream/s01e05.m3u8", "type": "hls", "quality": "1080p" },
  "localPath": "downloads/jellyfin-basic/a1b2c3/s01e05/",
  "sizeBytes": 1476395008,
  "downloadedBytes": 918552576,
  "status": "downloading",
  "createdAt": "2026-02-14T09:20:00Z"
}
```

**Note on denormalization:** `title` and `artworkUrl` are copied into the record deliberately. A download must remain fully displayable in the Downloads tab even when its connector is dormant (ADR-001), disabled, or removed entirely — the offline experience cannot depend on live connector calls.

---

## 5. Follow & Notification Contracts (Pro)

### 5.1 `Follow`

Backs Follow Center. A follow is a standing subscription to changes on a specific media item.

```typescript
interface Follow {
  ref: MediaRef;              // episodeId typically omitted — you follow a series, not an episode
  title: string;             // denormalized for the Following list
  artworkUrl?: string;
  triggers: NotificationTrigger[];   // which change types this follow cares about
  createdAt: string;
}

type NotificationTrigger =
  | "newEpisode"
  | "newSeason"
  | "betterQuality"
  | "dubAvailable"
  | "subtitlesAdded"
  | "connectorUpdated";
```

These trigger names map 1:1 to the Smart Notifications toggles in the product spec (New Episode, New Season, Better Quality, Dub Available, Subtitles Added, Connector Updated).

### 5.2 `Notification`

The delivered payload — produced by the backend's `NotificationDispatching` adapter (ADR-003), delivered via APNs, and also stored locally for the in-app Notifications list.

```typescript
interface Notification {
  id: string;                 // backend-issued, stable, for dedup
  trigger: NotificationTrigger;
  ref: MediaRef;
  title: string;              // e.g. "One Piece"
  body: string;               // e.g. "Episode 1145 is now available"
  actionLabel?: string;       // e.g. "Watch", "Update", "Review"
  createdAt: string;
  readAt?: string;
}
```

**Example:**
```json
{
  "id": "ntf_01HZX9",
  "trigger": "newEpisode",
  "ref": { "connectorId": "some-anime-src", "id": "one-piece" },
  "title": "One Piece",
  "body": "Episode 1145 is now available",
  "actionLabel": "Watch",
  "createdAt": "2026-02-14T06:00:00Z"
}
```

The client treats `trigger` + `ref` as the routing key: tapping the notification deep-links to the media details screen for that `ref`, or to the connector/repository update flow for `connectorUpdated`.

---

## 6. Connector Install State

The persisted record of an installed connector — the data behind the "Installed Connectors" screen and the input to update detection (ADR-005) and signature pinning (ADR-004).

```typescript
interface ConnectorInstall {
  connectorId: string;
  repoId: string;
  version: string;
  apiVersion: number;
  config: ConnectorConfig;          // doc 03 §5.5 — secrets stored in Keychain, not here in cleartext
  pinnedPublisherKeyId?: string;    // set on first install once signatures are enforced (ADR-004)
  status: ConnectorHealth;
  installedAt: string;
  updatedAt: string;
}

type ConnectorHealth =
  | "healthy"
  | "updateAvailable"
  | "updateRequired"     // apiVersion outside host's supported window (ADR-005) — no longer receives calls
  | "disabled"           // user-disabled
  | "error";             // repeated runtime failures
```

**Secrets note:** `config` values whose `SettingsField.type` is `secret` (doc 03 §5.6) are **not** stored inline here. This record holds a reference/placeholder; the actual secret lives in the Keychain-backed storage slice and is redacted in any Developer Console view and in backups (§8.2).

---

## 7. Cloud Sync Contract (Pro)

Per the architecture doc §4.6 and ADR-003, sync is single-user, multi-device, **not** collaborative — so the merge rule is simply **last-write-wins by `updatedAt`**. The sync adapter (`SyncStoring`) exchanges envelopes:

```typescript
interface SyncEnvelope<T> {
  entity: SyncEntity;
  records: SyncRecord<T>[];
  since?: string;            // ISO-8601 — client sends its last-sync cursor; server returns everything newer
}

interface SyncRecord<T> {
  key: string;               // stable identity, e.g. `${connectorId}:${id}:${episodeId ?? ""}`
  updatedAt: string;         // LWW merge key
  deleted?: boolean;         // tombstone — a delete syncs as a record, not an omission
  data?: T;                  // absent when deleted === true
}

type SyncEntity =
  | "watchState"
  | "favorite"
  | "follow"
  | "connectorInstall"
  | "repository"
  | "settings"
  | "downloadQueue";
```

**Example (one WatchState record in a sync push):**
```json
{
  "entity": "watchState",
  "since": "2026-02-14T00:00:00Z",
  "records": [
    {
      "key": "jellyfin-basic:a1b2c3:s01e05",
      "updatedAt": "2026-02-14T09:48:12Z",
      "data": {
        "ref": { "connectorId": "jellyfin-basic", "id": "a1b2c3", "episodeId": "s01e05" },
        "positionSec": 742,
        "durationSec": 2760,
        "finished": false,
        "updatedAt": "2026-02-14T09:48:12Z"
      }
    }
  ]
}
```

**Two rules that matter for correctness:**
1. **Deletes are tombstones.** Removing a favorite on device A syncs as a record with `deleted: true`, not as its absence — otherwise device B would resurrect it on the next merge. Tombstones are retained server-side for a bounded window (backend policy, not client concern).
2. **The merge key is `updatedAt`, period.** No vector clocks, no per-field merge. If two devices edit the same `key`, the later `updatedAt` wins wholesale. This is an explicit acceptable-loss decision given the non-collaborative use case (architecture doc §4.6).

Because app/UI code depends only on the `SyncStoring` protocol (ADR-003), this envelope shape is the contract a future custom backend must satisfy — not any particular vendor's SDK types.

---

## 8. Backup Contract

One-tap export/import of everything (product spec: Backup, Pro). The backup is a single self-describing JSON document, portable across devices independent of any account/cloud.

```typescript
interface Backup {
  format: "runtime-backup";
  formatVersion: number;         // bump on breaking changes to this shape
  exportedAt: string;
  app: { version: string; build: string };
  repositories: Repository[];    // §2 — enough to re-fetch connectors
  installs: ConnectorInstall[];  // §6 — secrets redacted, see §8.2
  favorites: Favorite[];         // §3.3
  watchStates: WatchState[];     // §3.2
  follows: Follow[];             // §5.1
  settings: Record<string, unknown>;   // opaque host settings blob
  // Deliberately NOT included: downloaded media bytes (see §8.1)
}
```

### 8.1 What a backup does and does not contain

- **Included:** everything needed to reconstruct the user's *setup and state* — which repos/connectors, their config (minus secrets), favorites, watch progress, follows, settings.
- **Excluded:** the downloaded media files themselves. A backup is metadata, not a media archive — it can re-trigger downloads on the new device via the recorded `DownloadRecord` refs, but it does not carry gigabytes of video. The `downloadQueue` sync entity (§7) covers *queue state*, not file bytes.

### 8.2 Secret handling on export

`secret`-typed config values (doc 03 §5.6) are **redacted** in the exported document — replaced with a `"__redacted__"` sentinel. On import, the user is prompted to re-enter those specific fields (e.g. the Jellyfin API key) before the affected connector becomes `healthy`. This keeps a backup file safe to store in iCloud Drive / email / etc. without leaking credentials.

**Example (abbreviated):**
```json
{
  "format": "runtime-backup",
  "formatVersion": 1,
  "exportedAt": "2026-02-14T10:00:00Z",
  "app": { "version": "1.5.0", "build": "1500" },
  "repositories": [ /* §2 */ ],
  "installs": [
    {
      "connectorId": "jellyfin-basic",
      "repoId": "community",
      "version": "1.2.0",
      "apiVersion": 1,
      "config": { "serverUrl": "https://media.mylan.home", "apiKey": "__redacted__" },
      "status": "healthy",
      "installedAt": "2026-01-02T00:00:00Z",
      "updatedAt": "2026-02-01T00:00:00Z"
    }
  ],
  "favorites": [ /* §3.3 */ ],
  "watchStates": [ /* §3.2 */ ],
  "follows": [ /* §5.1 */ ],
  "settings": { "theme": "midnight", "playback": { "autoNext": true } }
}
```

---

## 9. Contract Ownership Summary

Quick reference for who defines what, so two docs never claim the same type:

| Contract | Owned by | This doc's role |
|---|---|---|
| `CatalogItem`, `MediaDetails`, `EpisodeRef`, `StreamSource`, `SubtitleTrack`, `SettingsField`, `ConnectorConfig`, `ConnectorError` | Doc 03 (SDK) | Reference only |
| `Repository`, `RepositoryConnectorEntry` | Doc 06 (Repository Spec) | Canonical JSON reproduced here |
| `MediaRef`, `StoredCatalogItem`, `WatchState`, `Favorite` | **This doc** | Canonical |
| `DownloadRecord`, `DownloadStatus` | **This doc** | Canonical |
| `Follow`, `Notification`, `NotificationTrigger` | **This doc** | Canonical |
| `ConnectorInstall`, `ConnectorHealth` | **This doc** | Canonical |
| `SyncEnvelope`, `SyncRecord`, `SyncEntity` | **This doc** | Canonical (satisfies ADR-003 `SyncStoring`) |
| `Backup` | **This doc** | Canonical |

---

## 10. Open Questions for Review

1. **`SyncEntity` granularity for settings.** Settings sync as one opaque blob (§7) — simple, but a change to any single setting re-syncs the whole blob and LWW can clobber an unrelated setting changed on another device seconds earlier. Acceptable for v1.5? Or split high-churn settings (e.g. theme) from the blob? *(Leaning: one blob for v1.5, revisit if users report cross-device settings clobbering.)*
2. **Tombstone retention window.** §7 says "bounded window" for server-side tombstone retention — needs a concrete number (30 days? 90?) before the sync backend is built, since a device offline longer than the window and then reconnecting can resurrect deleted records. *(Leaning: 90 days, documented as a hard limit in the Pro sync description.)*
3. **Backup `formatVersion` migration.** Do we commit to importing *older* backup `formatVersion`s indefinitely (forward-compat on import), or define a support window like connectors have (ADR-005)? *(Leaning: import must support all prior versions — a backup is a user's data, not a connector; breaking it is unacceptable. State this explicitly.)*
