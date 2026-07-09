# Security Model

**Document 05 — Engineering Specification**
**Status:** Draft v0.1 — **frozen for v1.0 before implementation** (per SDLC plan §Requirements & Design)
**Depends on:** `03-runtime-sdk-specification.md`, `04-data-contracts.md`, `06-repository-spec.md`, ADR-001 (JS Runtime Lifecycle), ADR-004 (Publisher Trust Model)
**Consumed by:** Runtime Bridge (Swift), Repository Manager, App Store compliance review, adversarial test suite

---

## 0. Purpose and Scope

This document defines the **trust boundary** of the platform: what connector JavaScript is permitted to do, what it is structurally prevented from doing, and — critically — the *mechanism* that enforces each rule rather than a promise that it holds.

The guiding principle: **a connector is untrusted code from the internet.** Every guarantee here must survive a connector author who is actively hostile, not merely careless. "The connector shouldn't do X" is not a control; "the connector *cannot* do X because Y" is.

This doc is the reference for the adversarial test suite (SDLC plan §Testing) and for the App Store dynamic-code-execution compliance review that every submission triggers given this architecture.

Out of scope: the connector API surface itself (doc 03), the wire shapes (doc 04), repository signing format details (doc 06). This doc governs *enforcement*.

---

## 1. Threat Model

### 1.1 What we are defending

| Asset | Why it matters |
|---|---|
| User's other connectors' data | A malicious connector must not read/steal another's stored credentials or history |
| User's device & OS surface | No filesystem, no native APIs, no sensors — nothing beyond the sanctioned bridge |
| User's network / local network | A connector must not be usable as an SSRF pivot into the user's LAN or arbitrary hosts |
| The installed base's integrity | A repo must not be able to swap a trusted connector's code for malicious code on "update" |
| The user's trust in the UI | Connector-supplied content must never become executable UI (no injection) |

### 1.2 Who the adversary is

1. **A hostile connector author** — writes JS designed to exfiltrate data, pivot into the LAN, exhaust resources, or impersonate another publisher.
2. **A hostile / compromised repository** — serves a valid-looking index that swaps connector code, or points a trusted connector ID at malicious code.
3. **A network attacker** — MITMs connector downloads or API traffic.
4. **A malicious upstream source** — returns crafted JSON/streams intended to crash the host or inject content.

### 1.3 Explicit non-goals (v1)

- We do **not** attempt to prevent a connector from talking to a source the *user explicitly configured and permitted* (that's the point of a self-hosted connector).
- We do **not** attempt to detect "is this connector accessing content the user is legally entitled to" — that is a repository-governance and product-policy question (product vision §1), not a runtime security control.
- We do **not** defend against JavaScriptCore engine 0-days themselves — that's Apple's surface; we defend against everything reachable *through* the sanctioned bridge.

---

## 2. The Trust Boundary

```
┌──────────────────────────────────────────────────────────────┐
│  HOST (trusted, Swift)                                        │
│                                                              │
│   UI Layer ── Catalog DB ── Player ── Repository Manager     │
│        │                                                     │
│        │  typed data contracts only (doc 03 §5, doc 04)      │
│  ┌─────┴────────────────────────────────────────────┐       │
│  │  RUNTIME BRIDGE  ← the entire trust boundary       │       │
│  │  • injects `Runtime` global                        │       │
│  │  • mediates network (domain allowlist)             │       │
│  │  • mediates storage (namespacing + quota)          │       │
│  │  • enforces timeouts, serializes calls             │       │
│  │  • validates every return value                    │       │
│  └─────┬──────────────────────────────────────────────┘       │
│        │  ONLY `Runtime.request` / `Runtime.storage` / `.log`  │
└────────┼─────────────────────────────────────────────────────┘
         │
  ┌──────▼───────────────────────────────────────────────┐
  │  JSContext (untrusted)  — one per connector           │
  │  connector index.js — no globals but `Runtime`         │
  └───────────────────────────────────────────────────────┘
```

Everything crossing the Bridge is either a sanctioned `Runtime.*` call going down, or a value going up that is validated against doc 03 §5 / doc 04 before any trusted component sees it. There is no other channel.

---

## 3. Capability Matrix

### 3.1 Allowed (via the `Runtime` global only)

| Capability | Surface | Constraint |
|---|---|---|
| Outbound HTTP/HTTPS | `Runtime.request` (doc 03 §6.1) | Domain allowlist (§4); host-attached headers scoped to origin |
| Key/value storage | `Runtime.storage` (doc 03 §6.4) | Namespaced per connector; `maxBytes` quota |
| Logging | `Runtime.log` | Routed to Developer Console only; never to a network sink |
| Standard JS + language builtins | JSContext default | `JSON`, `Math`, `Date`, `Promise`, `TextEncoder`, string/array ops, `crypto`-style hashing *if* provided as a host shim — see §3.3 |

### 3.2 Disallowed (structurally absent, not merely discouraged)

| Capability | Why absent | Enforcement |
|---|---|---|
| Filesystem | No native file bridge injected | Not present in JSContext |
| Native iOS APIs (UIKit, contacts, etc.) | No native bridge injected | Not present |
| Camera / Microphone | No bridge; also no OS entitlement requested for connector use | Not present + no entitlement |
| Location | No bridge | Not present |
| Bluetooth | No bridge | Not present |
| Raw sockets / WebSocket / arbitrary TCP | Only `Runtime.request` (HTTP[S]) exposed | No socket API in context |
| `eval` of further remote code | Blocked (§5.3) | Bridge + review |
| Reading another connector's storage | Storage is namespaced by connector id | Bridge storage mediation (§4.4) |
| Reaching into host app state | Nothing but method args passed in | Nothing injected |
| Rendering UI / HTML | Host renders only structured data | Data-only contract (§6) |

### 3.3 The `crypto` question (open — see §9)

Connector authors will reasonably want hashing/HMAC for some auth schemes. A *pure* crypto shim (hashing, HMAC, base64 — no network, no key material access beyond what the connector already holds) is safe to expose and avoids authors shipping their own buggy JS crypto. This is listed as allowed-if-shimmed pending a decision on exactly which primitives to expose. It must **not** expose anything that reaches the Keychain or another connector's secrets.

---

## 4. Enforcement Mechanisms

Each subsection is a control, not an aspiration. The adversarial test suite has a corresponding test per control.

### 4.1 Isolation (per-connector JSContext)

- One `JSContext` / `JSVirtualMachine` per connector, created lazily and torn down on idle (ADR-001). No shared global object, no shared prototype chain, no shared storage handle across connectors.
- A crash, infinite loop, or OOM in one context cannot touch another — they are separate VMs on separate threads.
- **Control test:** connector A attempts to reach connector B's globals/storage → no reference obtainable; storage read returns only A's namespace.

### 4.2 Network mediation & domain allowlist

- Every `Runtime.request` is checked against the manifest's `permissions.network.domains` (doc 03 §6.2) **before the request leaves the device**.
- Match rules: exact host match, or wildcard `"*"` only when `allowUserConfiguredHost: true` was declared and the user saw the corresponding install-time prompt.
- **SSRF defense:** the same allowlist that permits a self-hosted host (e.g. a user's Jellyfin at `192.168.1.10`) is the *only* thing that host can reach. A connector declared for `api.themoviedb.org` cannot make a request to `192.168.1.10`, `169.254.169.254` (cloud metadata), or `localhost` — those hosts are simply not in its allowlist. There is no "the connector asked nicely" path.
- Header scoping: headers a connector receives in a `StreamSource` (doc 03 §5.4) are re-attached by the Player Engine **only** to requests to the same origin that supplied them — a connector cannot harvest a self-hosted server's auth header and cause it to be sent to an attacker-controlled domain.
- Blocked requests are surfaced as `PERMISSION_DENIED` (doc 03 §7) *and* logged to the HTTP Inspector — both a debugging aid and a misbehavior signal.
- **Control test:** connector declares one domain, attempts request to an undeclared domain (including LAN/metadata IPs) → blocked + logged.

### 4.3 Redirect handling

- `Runtime.request` follows redirects, but **each hop is re-checked against the allowlist.** A permitted domain that 302-redirects to a disallowed host does not smuggle the connector out of its allowlist — the redirected request is blocked.
- **Control test:** allowed host returns a redirect to a disallowed host → redirect blocked, `PERMISSION_DENIED`.

### 4.4 Storage mediation

- All `Runtime.storage` keys are transparently prefixed with the connector id by the Bridge; the connector never sees or controls the real key. Cross-namespace access is impossible because the connector cannot express a key outside its own namespace.
- Quota (`permissions.storage.maxBytes`) enforced on write; overflow → `STORAGE_QUOTA_EXCEEDED`.
- `secret`-typed config (doc 04 §6) lives in Keychain-backed storage the connector can *use* (its own values) but never *enumerate* beyond its namespace, and which is redacted in Developer Console + backups.
- **Control test:** connector attempts a key collision with another connector / attempts to exceed quota → isolated / rejected.

### 4.5 Resource bounds (DoS defense)

| Bound | Limit | On breach |
|---|---|---|
| Single request timeout | 10s (doc 03 §6.3) | `TIMEOUT` |
| Whole-method wall clock | 15s | `TIMEOUT`, context call aborted |
| Memory | Polled per context; hard ceiling | Context torn down, `error` health set |
| CPU / infinite loop | Watchdog on the whole-method budget | Call aborted at 15s regardless of progress |

Because bounds are per-context (ADR-001), a runaway connector degrades only itself. **Control tests:** infinite loop, oversized allocation, hung request — each aborts the offending context alone.

### 4.6 Return-value validation

- Every value a connector returns is validated against its declared contract (doc 03 §5) before any trusted component (Catalog DB, Player, UI) sees it. Malformed shape → `INVALID_RESPONSE`, value discarded.
- This is what makes "no injection" real (§6): the host never receives, let alone renders, arbitrary connector-authored structure — only fields that survive schema validation.

---

## 5. Supply-Chain Integrity (ADR-004)

The runtime sandbox defends against what a connector *does*; this section defends against *which code runs* in the first place.

### 5.1 Checksums (v1, enforced now)

- Every connector entry file has a `sha256` checksum in the repository index (doc 04 §2) and manifest (doc 03 §2).
- The downloaded bytes are hashed and compared **before** the code is ever evaluated in a JSContext. Mismatch → install/update blocked, nothing executed.
- Defends against: corrupted downloads, MITM tampering, a CDN serving different bytes than the index advertises.

### 5.2 Publisher signatures (v1.5, enforced before any public repo directory exists)

- Ed25519 signatures over the entry file, verified against a per-publisher key.
- **Trust-on-first-use pinning:** the first install of a connector id pins its `publisherKeyId`. Every subsequent update to that id must verify against the pinned key or the update is **rejected with a warning** and the existing version keeps running (doc 04 §6, `pinnedPublisherKeyId`).
- Defends against the core supply-chain threat: **a repo swapping a trusted connector's code on "update."** Even a fully compromised repository cannot push malicious code under an existing trusted id without the original publisher's key.
- Format is built into the manifest/index from v1 (checksum + optional signature fields present day one) precisely so enforcement can turn on at v1.5 without a "50,000 connectors, no migration path" break (ADR-004).
- **Key rotation** is a governed process (SDLC §Maintenance): a publisher rotating keys must sign the new key with the old one (or go through an explicit, user-visible re-trust flow) — never a silent swap.

### 5.3 No second-stage code loading

- A connector must not fetch-and-eval further remote code to defeat review/signing (download a benign index, then pull malicious JS at runtime).
- Controls: (a) no `eval`/`Function`-from-network pattern is provided a network-to-execution path — `Runtime.request` returns a string body the connector can parse as *data*, but there is no host affordance to execute a fetched string as code; (b) App Store review + the adversarial suite flag connectors that appear to construct executable code from network responses.
- This is defense-in-depth, not a single hard wall — noted honestly as the softest control here, which is why signing (§5.2) matters: it ties running code to an accountable key.

---

## 6. UI Injection Defense

- The UI Layer (architecture §4.2) renders **only structured data** — the validated fields of `CatalogItem`/`MediaDetails`/etc. It never renders connector-supplied HTML, markup, or markdown-as-HTML.
- A connector cannot return a "title" that becomes a script, a link that becomes an action, or artwork that becomes anything but an image request to an allowlisted URL.
- Image URLs are subject to the same origin considerations; a connector-supplied `artworkUrl` is loaded as an image, not fetched-and-interpreted.
- **Control test:** connector returns fields containing script/markup payloads → rendered inertly as text, never interpreted.

---

## 7. Permission UX (informed consent)

Security controls are paired with user-visible consent, because the strongest technical boundary still needs the user to understand what they permitted:

- At install, the user sees the connector's declared permissions (doc 03 §2) in plain language *before* opting in — specifically the network scope ("contacts `api.themoviedb.org`" vs. the distinct "contacts a server you specify" for self-hosted `allowUserConfiguredHost`) and storage.
- Per the repository flow (architecture §4.7): paste repo URL → validate → preview list → **per-connector opt-in with the permission prompt shown at that point** — not a bulk "trust everything in this repo."
- Connector Details (UI doc) surfaces the same permissions post-install for transparency ("Transparency builds trust").

---

## 8. Enforcement ↔ Test Mapping

Every control above has a standing adversarial test (SDLC §Testing), run on **every Bridge change**:

| Control | Adversarial test |
|---|---|
| §4.2 domain allowlist | Undeclared-domain request (incl. LAN/`169.254.169.254`/`localhost`) → blocked |
| §4.3 redirect re-check | Allowed→disallowed redirect → blocked |
| §4.4 storage isolation | Cross-namespace read / key collision → isolated |
| §4.4 quota | Oversized write → `STORAGE_QUOTA_EXCEEDED` |
| §4.5 timeouts/loops | Infinite loop, hung request, oversized allocation → offending context only aborts |
| §4.6 validation | Malformed return shapes → `INVALID_RESPONSE` |
| §4.1 isolation | Cross-connector global/state access → impossible |
| §5.1 checksum | Tampered bytes → install blocked pre-execution |
| §5.2 signature pin | Update signed by wrong key → rejected, prior version kept |
| §6 injection | Markup/script in returned fields → inert |

A red result on any of these blocks the Bridge change from merging.

---

## 9. Open Questions for Review

1. **Crypto shim scope (§3.3).** Which primitives do we expose — SHA-256 + HMAC + base64 only, or a broader set? Exposing too little pushes authors toward buggy JS crypto; too much widens surface. *(Leaning: minimal — SHA/HMAC/base64 — behind a `Runtime.crypto` namespace, no key storage access.)*
2. **Private/LAN address policy for user-configured hosts.** `allowUserConfiguredHost` legitimately needs to reach `192.168.x.x` for self-hosted servers — but that's also the exact capability an SSRF attacker wants. Do we require the user-configured host to be *pinned to the single address they entered* (not a wildcard into their whole LAN)? *(Leaning: yes — `allowUserConfiguredHost` resolves to exactly the host the user configured, not arbitrary private space.)*
3. **Second-stage code detection (§5.3).** This is the softest control. Is signing (§5.2) + review sufficient, or do we want a stricter static check that flags network-response-to-eval patterns at submission? *(Leaning: rely on signing as the real control; add a best-effort static flag but don't claim it's airtight.)*
4. **Certificate pinning for connector *downloads*.** Checksums defend the bytes, but should the CDN/repo fetch itself pin certs to reduce MITM surface before checksum verification even runs? *(Leaning: nice-to-have, not v1 — checksum already defeats tampering regardless of transport.)*
