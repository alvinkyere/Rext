# Runtime Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  iOS App: RuntimeSpike                                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                                                                          │ │
│  │  SwiftUI Layer (Future)                                                 │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                │ │
│  │  │ Search View  │  │ Details View │  │ Player View  │                │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                │ │
│  │         │                 │                 │                          │ │
│  │         └─────────────────┼─────────────────┘                          │ │
│  │                           │                                            │ │
│  └───────────────────────────┼────────────────────────────────────────────┘ │
│                              │                                              │
│  ┌───────────────────────────▼────────────────────────────────────────────┐ │
│  │                                                                          │ │
│  │  RuntimeHost (Singleton)                                                │ │
│  │  • Lazy connector creation (ADR-001)                                   │ │
│  │  • Idle teardown (45s)                                                 │ │
│  │  • Memory pressure teardown                                            │ │
│  │  • Registry: [connectorId: ConnectorRuntime]                          │ │
│  │                                                                          │ │
│  └───────────────────────────┬────────────────────────────────────────────┘ │
│                              │                                              │
│                              │ Creates & manages                            │
│                              │                                              │
│  ┌───────────────────────────▼────────────────────────────────────────────┐ │
│  │                                                                          │ │
│  │  ConnectorRuntime (one per connector)                    RuntimeSDK    │ │
│  │  ┌────────────────────────────────────────────────────────────────────┐│ │
│  │  │                                                                      ││ │
│  │  │  THE TRUST BOUNDARY                                                ││ │
│  │  │  ─────────────────────                                             ││ │
│  │  │                                                                      ││ │
│  │  │  ✓ Domain allowlist enforcement                                    ││ │
│  │  │  ✓ Redirect re-check (RedirectGuard)                              ││ │
│  │  │  ✓ Storage namespacing + quota                                     ││ │
│  │  │  ✓ Timeout enforcement (10s request, 15s call)                    ││ │
│  │  │  ✓ Return-value validation (Codable)                              ││ │
│  │  │  ✓ Weak-capturing timeout work item                               ││ │
│  │  │  ✓ Session invalidation in deinit                                 ││ │
│  │  │                                                                      ││ │
│  │  │  Components:                                                        ││ │
│  │  │  • JSVirtualMachine (isolated per connector)                      ││ │
│  │  │  • JSContext (no shared globals)                                   ││ │
│  │  │  • NamespacedStore (per-connector storage)                        ││ │
│  │  │  • URLSession + RedirectGuard                                      ││ │
│  │  │  • Serial DispatchQueue (call serialization)                      ││ │
│  │  │                                                                      ││ │
│  │  └────────────────────────┬───────────────────────────────────────────┘│ │
│  │                           │                                             │ │
│  │                           │ Injects Runtime global only                 │ │
│  │                           │                                             │ │
│  └───────────────────────────┼─────────────────────────────────────────────┘ │
│                              │                                              │
│  ════════════════════════════╪══════════════════════════════════════════════ │
│  No other channel            │ Only this surface                            │
│  ════════════════════════════╪══════════════════════════════════════════════ │
│                              │                                              │
│  ┌───────────────────────────▼────────────────────────────────────────────┐ │
│  │                                                                          │ │
│  │  JSContext (untrusted, isolated)                                        │ │
│  │  ┌────────────────────────────────────────────────────────────────────┐│ │
│  │  │                                                                      ││ │
│  │  │  globalThis.Runtime = {                                            ││ │
│  │  │    request: (input) => Promise<RuntimeResponse>,                  ││ │
│  │  │    storage: { get, set, delete },                                 ││ │
│  │  │    log: (...args) => void                                          ││ │
│  │  │  }                                                                  ││ │
│  │  │                                                                      ││ │
│  │  │  globalThis.connectorInstance = {                                  ││ │
│  │  │    search(query, page?) => Promise<CatalogItem[]>,                ││ │
│  │  │    getDetails(id) => Promise<MediaDetails>,                       ││ │
│  │  │    getStreams(itemId, episodeId?) => Promise<StreamSource[]>      ││ │
│  │  │  }                                                                  ││ │
│  │  │                                                                      ││ │
│  │  │  NO:                                                                ││ │
│  │  │  ✗ fetch / XMLHttpRequest                                          ││ │
│  │  │  ✗ DOM / document / window                                         ││ │
│  │  │  ✗ Filesystem access                                               ││ │
│  │  │  ✗ Native APIs (UIKit, contacts, etc.)                            ││ │
│  │  │  ✗ Access to other connectors                                      ││ │
│  │  │  ✗ Access to host app state                                        ││ │
│  │  │                                                                      ││ │
│  │  └──────────────────────────────────────────────────────────────────┬─┘│ │
│  │                                                                        │  │ │
│  │  Connector Source (podcast-rss.js)                                   │  │ │
│  │  • Implements the Connector interface                                 │  │ │
│  │  • Calls only Runtime.request/storage/log                            │  │ │
│  │  • Returns typed data (validated by host)                            │  │ │
│  │  • Throws structured ConnectorError                                   │  │ │
│  │                                                                          │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════════════
                            ENFORCEMENT LAYERS
═══════════════════════════════════════════════════════════════════════════════

Layer 1: JSContext Isolation
─────────────────────────────
• One JSVirtualMachine per connector (structural isolation)
• No shared global object, no shared prototype chain
• Crash/OOM in one context cannot touch another

Layer 2: Capability Surface
───────────────────────────
• ONLY Runtime global injected (request, storage, log)
• No fetch, no filesystem, no native APIs
• Connector cannot reach host app state or other connectors

Layer 3: Network Enforcement
─────────────────────────────
• Domain allowlist checked BEFORE request leaves device
• RedirectGuard re-checks every redirect hop
• Blocked requests logged to Developer Console

Layer 4: Resource Bounds
──────────────────────────
• 10s per request, 15s per call (timeout)
• Storage quota enforced on writes
• Memory polled per context (hard ceiling)

Layer 5: Return Validation
────────────────────────────
• Every return value decoded via Codable BEFORE host sees it
• Malformed shape → INVALID_RESPONSE, value discarded
• No injection: UI renders only structured data

═══════════════════════════════════════════════════════════════════════════════
                            DATA FLOW EXAMPLE
═══════════════════════════════════════════════════════════════════════════════

User Search "history"
  │
  ├─▶ RuntimeHost.search("podcast-rss", "history")
  │     │
  │     ├─▶ runtime(for: "podcast-rss")  // Lazy create if needed
  │     │     │
  │     │     ├─▶ ConnectorRuntime created:
  │     │     │     • JSVirtualMachine + JSContext
  │     │     │     • Inject Runtime global
  │     │     │     • Evaluate podcast-rss.js
  │     │     │     • Serial queue for call serialization
  │     │     │
  │     │     └─▶ Warm runtime returned
  │     │
  │     └─▶ runtime.call("search", ["history", 1], [CatalogItem].self)
  │           │
  │           ├─▶ Queue.async on connector's serial queue
  │           │     │
  │           │     ├─▶ connectorInstance.search("history", 1)
  │           │     │     │
  │           │     │     ├─▶ Runtime.request({ url: "...search?q=history..." })
  │           │     │     │     │
  │           │     │     │     ├─▶ Allowlist check: "api.example-podcasts.com" ✓
  │           │     │     │     ├─▶ URLSession.dataTask with RedirectGuard
  │           │     │     │     ├─▶ Response returns, hop to connector queue
  │           │     │     │     └─▶ Promise resolves
  │           │     │     │
  │           │     │     ├─▶ Runtime.storage.set("lastQuery", "history")
  │           │     │     │     │
  │           │     │     │     ├─▶ Quota check ✓
  │           │     │     │     └─▶ Write succeeds
  │           │     │     │
  │           │     │     └─▶ Return [{ id: "show-42", title: "...", kind: "podcast" }, ...]
  │           │     │
  │           │     └─▶ Promise resolves with JSValue
  │           │
  │           ├─▶ decode(jsResult, [CatalogItem].self)
  │           │     │
  │           │     ├─▶ JSValue.toObject() → Swift dictionary
  │           │     ├─▶ JSONSerialization.data(withJSONObject:)
  │           │     ├─▶ JSONDecoder().decode([CatalogItem].self)
  │           │     │     • id: ✓ present
  │           │     │     • title: ✓ present
  │           │     │     • kind: ✓ valid enum
  │           │     └─▶ Validation passes → [CatalogItem] returned
  │           │
  │           └─▶ Returns typed [CatalogItem] to host
  │
  └─▶ Host UI renders results (structured data only, no injection)

═══════════════════════════════════════════════════════════════════════════════
                            LIFECYCLE (ADR-001)
═══════════════════════════════════════════════════════════════════════════════

Install:
  manifest + source → RuntimeHost.install()
                    ↓
            Manifest & source stored
            NO JSContext created yet (lazy)

First Call (search/browse/details):
  RuntimeHost.search() → runtime(for: id)
                       ↓
              JSContext created & warmed
              Runtime global injected
              Connector source evaluated

Warm State (30–60s):
  • JSContext alive
  • Storage in memory
  • URLSession alive
  • Subsequent calls reuse same context

Idle Teardown (45s no calls):
  RuntimeHost sweeper (every 15s)
                ↓
      Check lastUsed > 45s ago?
                ↓
       Drop runtime from registry
                ↓
      deinit: session.invalidateAndCancel()
                ↓
      JSContext/JSVirtualMachine released
                ↓
      Memory returned to OS

Memory Pressure:
  System warning → RuntimeHost.tearDownAll()
                 ↓
         Drop ALL runtimes immediately
                 ↓
         Shed memory before OS kills app

App Backgrounding:
  UIApplicationDidEnterBackground → RuntimeHost.tearDownAll()
                                  ↓
                      All contexts torn down

═══════════════════════════════════════════════════════════════════════════════
                            TEST ARCHITECTURE
═══════════════════════════════════════════════════════════════════════════════

FixtureURLProtocol
  │
  ├─▶ Intercepts URLSession requests
  │     │
  │     ├─▶ Check fixtures map: url → FixtureResponse
  │     │     • status, body, headers
  │     │     • optional delay (for timeout tests)
  │     │     • optional redirect (for redirect tests)
  │     │
  │     └─▶ Serve canned response (no network)
  │
  └─▶ Registered fixtures:
        • PodcastRSSFixtures.registerAll()
        • Each test gets fresh fixtures (clearFixtures())

ConnectorRuntimeTests
  │
  ├─▶ Each test creates FRESH runtime
  │     │
  │     ├─▶ No state leakage between tests
  │     └─▶ Mirrors production isolation
  │
  ├─▶ Happy path: search → details → streams
  ├─▶ Error scenarios: NOT_FOUND, INVALID_RESPONSE, PERMISSION_DENIED, etc.
  └─▶ Isolation: separate runtimes have separate storage

ConnectorRuntimeLeakTests
  │
  ├─▶ Weak references to runtime, delegate
  ├─▶ Assert deallocates after use
  ├─▶ 100 cycles: flat memory (no leaks)
  └─▶ Guards both leak fixes:
        • Session invalidation
        • Weak-capturing timeout

═══════════════════════════════════════════════════════════════════════════════
