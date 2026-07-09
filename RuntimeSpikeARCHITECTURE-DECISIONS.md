# Architecture & Security Decisions

## Resolved Open Questions

### 1. LAN Address Policy for `allowUserConfiguredHost` (Security Model §9 #2)

**Decision:** For the spike, `allowUserConfiguredHost: true` acts as a simple wildcard (allows any domain). The stricter "pin to user-entered host only" policy is **deferred to the first Jellyfin connector** (post-spike).

**Rationale:**
- The podcast-rss connector doesn't use user-configured hosts, so this doesn't block spike validation
- The real policy needs real UX: "enter your Jellyfin server URL" → pin that exact host
- Implementing pinning now would be premature without the actual user flow
- The allowlist enforcement is working correctly; we're just deferring the finer-grained host pinning

**Implementation status:**
```swift
// RuntimeBridge.swift:
private func isAllowed(_ url: URL) -> Bool {
    guard let host = url.host else { return false }
    if allowUserHost { return true }  // ← Currently wildcard; will become pinned later
    return allowlist.contains(host)
}
```

**Next steps (Jellyfin connector):**
- Add a `configuredHosts: [String]` field to ConnectorManifest.Permissions.Network
- Populate it from the user's settings (e.g., "https://jellyfin.home.local")
- Change `isAllowed` to check `allowUserHost ? configuredHosts.contains(host) : allowlist.contains(host)`
- This gives "wildcard into the set of user-configured hosts" (not truly wildcard into all private space)

---

## Key Design Decisions

### 2. Fresh Runtime Per Test

**Decision:** Every test creates a new `ConnectorRuntime` instance.

**Rationale:**
- Mirrors production isolation (one JSContext per connector)
- No state bleed between tests
- Catches lifecycle bugs (e.g., tests that accidentally rely on warm state)
- Makes tests parallelizable in the future

**Implementation:**
```swift
func testSearchHappyPath() async throws {
    let rt = try makeRuntime()  // ← Fresh every time
    let items = try await rt.call("search", args: ["history", 1], as: [CatalogItem].self)
    // ...
}
```

### 3. Fixture Organization by Connector

**Decision:** `Fixtures/PodcastRSS/`, `Fixtures/Jellyfin/`, etc. (not one flat directory).

**Rationale:**
- Scales to many connectors
- Clear ownership (Jellyfin team owns `Fixtures/Jellyfin/`)
- Easy to find/update fixtures for a specific connector
- Mirrors the sample connector structure (`SampleConnectors/podcast-rss.js`)

### 4. FixtureURLProtocol is Generic

**Decision:** Tests register fixtures via `FixtureURLProtocol.register(url:response:)` instead of hardcoding URLs in the protocol.

**Rationale:**
- Reusable across all connectors
- Tests can add fixtures without modifying the protocol
- Clear separation: protocol = mechanism, fixtures = data

**Implementation:**
```swift
// In test setup:
PodcastRSSFixtures.registerAll()

// In PodcastRSSFixtures:
FixtureURLProtocol.register(
    url: "https://api.example-podcasts.com/search?q=history&page=1",
    response: loadFixture("search-history.json", status: 200)
)
```

### 5. podcast-rss.js is the Golden Connector

**Decision:** Treat `SampleConnectors/podcast-rss.js` as the canonical SDK example, not just a test asset.

**Rationale:**
- Connector authors need a reference implementation to study
- Inline documentation explains the contract
- Shows best practices (structured errors, storage usage)
- Lives in `SampleConnectors/` (not hidden in `Tests/`)

**Documentation quality:**
- Every method has a doc comment linking to the spec
- Error handling is demonstrated
- Storage usage is shown
- Capabilities are explicitly called out

### 6. Modular from Day One

**Decision:** RuntimeSDK is a separate directory, not mixed with app code.

**Rationale:**
- Easy to extract as a Swift Package later
- Clear boundary: SDK = trust boundary, App = UI/orchestration
- Testable in isolation
- Reusable across multiple apps (future: tvOS, visionOS)

**Directory structure:**
```
RuntimeSpike/
├── RuntimeSDK/           ← Future package
│   ├── RuntimeBridge.swift
│   ├── RuntimeModels.swift
│   └── ConnectorError.swift
└── RuntimeSpike/         ← App shell
    ├── RuntimeSpikeApp.swift
    └── ContentView.swift
```

### 7. Swift 6 + Strict Concurrency

**Decision:** Enable Swift 6 and strict concurrency checking from day one.

**Rationale:**
- Catch threading bugs early (JSContext interop is tricky)
- Future-proof (Swift 6 is the present/future)
- Forces explicit Sendable conformance
- Tests the SDK in the strictest mode (no surprises later)

**Implementation notes:**
- `@unchecked Sendable` on bridge types (JSContext isn't Sendable but is thread-safe in our usage)
- All closures passed to JSContext are `@Sendable`
- All model types are `Sendable`

### 8. Two Leak Fixes Preserved

**Decision:** Keep both leak fixes found during spike development.

**Leak #1: URLSession delegate retention**
```swift
deinit {
    session?.invalidateAndCancel()  // ← Releases the delegate
}
```

**Leak #2: Timeout block capturing self**
```swift
// Before (leaked):
queue.asyncAfter(deadline: .now() + callTimeout) {
    // Strong capture of self → pinned for 15s
}

// After (fixed):
let item = DispatchWorkItem { [weak self] in
    // Weak capture + cancellable
}
queue.asyncAfter(deadline: .now() + callTimeout, execute: item)
```

**Tests that guard these:**
- `testRuntimeDeallocatesAfterUse` — catches leak #2
- `testSessionDelegateDeallocatesAfterTeardown` — catches leak #1
- `testNoLeakAcrossManyCycles` — catches both over 100 cycles

---

## Security Invariants (Unchanged)

All invariants from docs 03-05 are enforced as written:

✅ **Isolation** — One JSContext per connector, separate NamespacedStore
✅ **Domain allowlist** — Checked before every request leaves device
✅ **Redirect re-check** — `RedirectGuard` re-checks every hop
✅ **Storage namespacing** — Connector A cannot read connector B's keys
✅ **Quota enforcement** — Writes beyond `maxBytes` rejected
✅ **Timeouts** — 10s per request, 15s per call, enforced host-side
✅ **Return validation** — Codable decoding = validation; bad shape = INVALID_RESPONSE
✅ **No eval of remote code** — Runtime.request returns data, not executable code

---

## Deferred Decisions (Post-Spike)

### 1. LAN Address Pinning (see §1 above)
**When:** First Jellyfin connector
**What:** Change `allowUserHost` from boolean wildcard to "wildcard into user-configured hosts only"

### 2. Crypto Shim (Security Model §9 #1)
**When:** First connector needs HMAC/hashing
**What:** Expose a minimal `Runtime.crypto` (SHA-256, HMAC, base64)
**Why deferred:** No connector in the spike needs it; design when real need emerges

### 3. Repository Signing Enforcement (ADR-004)
**When:** v1.5 (before public repo directory)
**What:** Enforce Ed25519 signatures + TOFU pinning
**Why deferred:** Spike has one hardcoded connector; signing matters when distribution starts

### 4. Static Analysis for eval Patterns (Security Model §9 #3)
**When:** Repository submission flow
**What:** Flag connectors that appear to eval network responses
**Why deferred:** Signing (§3) is the real control; this is nice-to-have detection

---

## Non-Goals (Explicitly Out of Scope)

❌ **SwiftUI app UI** — Spike validates contracts, not app features
❌ **Catalog DB persistence** — Tests use in-memory validation
❌ **Cloud sync** — Future Pro feature, not needed for spike
❌ **Download management** — Future feature, not needed for spike
❌ **Repository Manager** — Spike has one hardcoded connector
❌ **Signature verification** — Deferred to v1.5
❌ **Settings UI** — Spike has no user-facing config

---

## Success Metrics

The spike **succeeds** when:

1. ✅ All tests pass on macOS (fast loop validated)
2. ✅ All tests pass on iOS device (on-device runtime validated)
3. ✅ Instruments shows flat memory over 100 cycles (no leaks)
4. ✅ Six pass/fail criteria from README.md hold on device:
   - Flow works (search → details → streams)
   - Isolation is real (JSContext-level)
   - Allowlist enforced (undeclared domains blocked)
   - Teardown works (45s idle drops context)
   - No leaks (100 cycles flat memory)
   - Timeouts work (hung requests abort)

5. ✅ The frozen contracts (docs 03-06) are proven internally consistent

---

## What Comes After Success

1. **Extract RuntimeSDK as a Swift Package**
   - Add Package.swift
   - Version the SDK separately from the app
   - Publish to GitHub (if open-sourcing the SDK)

2. **Build First Real Vertical Slice: Jellyfin Connector**
   - User-configured host (tests the LAN address policy)
   - Self-hosted auth (API key in Keychain)
   - Full SwiftUI UI (browse, search, play)
   - Tests the "real connector in a real app" flow

3. **Continue in Vertical Slices**
   - One connector end-to-end at a time
   - Don't build every layer at once
   - Each slice validates a new aspect (auth, pagination, subtitles, etc.)

4. **Build Infrastructure Layers as Needed**
   - Catalog DB (when search results need persistence)
   - Repository Manager (when multiple connectors exist)
   - Download management (when offline playback is next)
   - Cloud sync (when multi-device is prioritized)

---

## Key Takeaways

1. **The spike's job is to validate contracts, not build an app.** It succeeded.
2. **The frozen contracts (docs 03-06) are proven.** They survive contact with a real runtime.
3. **The security model holds.** All invariants are enforced in Swift where JS can't reach them.
4. **The two leak bugs are fixed and guarded by tests.**
5. **The next build is the first real vertical slice:** Jellyfin connector end-to-end with SwiftUI.
