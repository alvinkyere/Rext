# Runtime — Architecture Spike

The smallest end-to-end slice that pressure-tests the frozen contracts (docs 03–06):
a **Runtime Bridge** injecting the `Runtime` global into an isolated JS context, and
**one real connector** taken through search → details → resolve.

Its job is to answer one question before any feature work begins: **do the frozen
contracts survive contact with a real runtime?** Not "is the app built."

```
runtime-spike/
├── connector/
│   ├── podcast-rss.js      # the test connector (Connector contract, doc 03 §4)
│   └── manifest.json       # identity + permissions + apiVersion (doc 03 §2)
├── validation/
│   ├── mock-bridge.mjs     # Node mock of the bridge, mirrors the Swift enforcement
│   ├── fixtures.mjs        # canned API responses (deterministic, offline)
│   └── run-validation.mjs  # runs the connector through the mock, asserts the contract
└── ios/
    ├── RuntimeModels.swift          # Codable mirrors of the data contracts
    ├── ConnectorError.swift         # normalized error model (doc 03 §7)
    ├── RuntimeBridge.swift          # the trust boundary — JSContext, allowlist, timeouts, ADR-001 lifecycle
    └── ConnectorRuntimeTests.swift  # XCTest mirror of the JS validation
```

---

## What is already validated (and how)

Run it yourself — no build, no network, ~instant:

```bash
node validation/run-validation.mjs
```

This executes the **exact** connector source (`connector/podcast-rss.js`) inside Node's
`vm` module — the same execution model a `JSContext` uses (an isolated context with only
`Runtime` injected). It asserts **23 checks**: the happy-path flow, namespaced storage,
connector isolation, and every `ConnectorError` path from the doc 05 §8 enforcement table:

| Area | Checks |
|---|---|
| Happy path | search → 2 valid `CatalogItem`s; details → `MediaDetails` + episodes; streams → `StreamSource` |
| Storage | namespaced write recorded; two connectors' stores isolated |
| `NOT_FOUND` | upstream 404 and connector guards map through |
| `INVALID_RESPONSE` | non-JSON upstream body **and** malformed connector *return* both rejected |
| `PERMISSION_DENIED` | undeclared-domain request blocked + logged; cross-origin redirect re-checked and blocked |
| `STORAGE_QUOTA_EXCEEDED` | over-quota write rejected |
| `TIMEOUT` | slow request (>10s cap) aborted |

**This proves the contract design.** The five `Connector` methods, the data shapes, the
`Runtime` surface, the error model, and the enforcement rules are internally consistent and
sufficient to take a real source end-to-end. That's the part that was cheapest to get wrong
and most expensive to change after connector authors depend on it — so it's the part worth
proving first.

---

## What is NOT validated here (and needs a device)

The mock proves the *contract*. It deliberately does **not** model the iOS runtime, which is
exactly what the spike exists to de-risk. These require Xcode + hardware:

1. **JSContext / JSVirtualMachine isolation is real** — that one connector genuinely cannot
   reach another's context or globals, at the engine level (not just "separate `Map`s in Node").
2. **The async promise bridge works under JSCore** — `JSValue(newPromiseIn:)` resolving from a
   `URLSession` completion, marshaled back onto the context queue, without deadlock or leak.
3. **ADR-001 lifecycle behaves on-device** — contexts create lazily, stay warm across a
   browse→play sequence, and actually **tear down** on 45s idle / backgrounding / memory
   pressure, with memory returned to the OS.
4. **Memory under load** — the brief's highest-risk assumption. Repeated create/use/teardown
   cycles must not leak; `JSVirtualMachine` deallocation must actually free.
5. **Redirect re-check fires** — `RedirectGuard` cancels a real 302 to a disallowed host
   (the Swift path; the JS mock proves the *rule*, the delegate proves the *mechanism*).

---

## Running the Swift side

`JavaScriptCore` is cross-Apple-platform, so the bridge compiles on both macOS and iOS.
The `ios/` folder is now turnkey — no stub to write:

- `RuntimeBridge.swift`, `RuntimeModels.swift`, `ConnectorError.swift` — the bridge.
- `FixtureURLProtocol.swift` — a `URLProtocol` that serves the same fixtures as
  `validation/fixtures.mjs`, so tests run **offline**. Hand it to the runtime via
  `ConnectorRuntime(…, sessionConfiguration: FixtureURLProtocol.sessionConfiguration())`.
- `ConnectorRuntimeTests.swift` — the functional mirror of the JS suite.
- `ConnectorRuntimeLeakTests.swift` — the automated dealloc/leak proxy for on-device
  criterion 5 below (asserts each runtime, its JSContext/VM, and its session delegate
  actually deallocate across 100 cycles, via weak references).

**Fast loop (macOS):** add the files to a unit-test target named `RuntimeSpike`, add
`connector/podcast-rss.js` to the target's resources, and run both test files. This exercises
the JS bridging and the dealloc logic without a device.

**Real loop (iOS device):** same files in an iOS app + unit-test target. Run on hardware to
validate the memory/lifecycle criteria a simulator and a mock both lie about.

### Two bugs the spike already caught (before any device)

Writing the leak test surfaced two real retainers, both now fixed in `RuntimeBridge.swift` —
exactly the point of building a spike:

1. **`URLSession` retains its delegate until invalidated.** Each per-connector session was never
   invalidated, so every teardown leaked a session + delegate. Fixed with `invalidateAndCancel()`
   in `deinit` and a self-contained delegate. (`testSessionDelegateDeallocatesAfterTeardown`)
2. **The whole-call timeout pinned the runtime for 15s.** The timeout block captured `self`
   strongly and was never cancelled, so a finished call kept its runtime (and JSContext) alive
   for the full `callTimeout`. Fixed with a cancellable, weakly-capturing work item.
   (`testTeardownIsPromptNotTimeoutBound`)

A third discrepancy showed up too: on-device, cancelling a disallowed redirect completes the task
with the 3xx response rather than erroring, so the bridge now maps a 3xx-at-completion to
`PERMISSION_DENIED` to match the mock's intent. The one stub behavior still worth confirming on
hardware is that a cancelled redirect indeed completes with the 3xx (see the note in
`FixtureURLProtocol.startLoading`).

---

## Pass/fail criteria for the on-device spike

The spike **passes** — and you can start expanding into vertical slices — only if all hold on
a physical iOS device:

- [ ] **Flow:** install → search("history") → 2 results → getDetails → 2 episodes →
      getStreams → a playable URL, with no main-thread stalls.
- [ ] **Isolation:** a connector that tries to read another's storage key or reach its globals
      gets nothing — confirmed at the JSContext level, not by convention.
- [ ] **Allowlist:** a connector declared for `api.example-podcasts.com` that requests any other
      host (incl. a `192.168.x.x` LAN IP and `169.254.169.254`) is blocked and logged, and a
      302 from the allowed host to a disallowed host is cancelled.
- [ ] **Teardown:** after a search, leaving the connector idle 45s drops its context and returns
      its memory; backgrounding the app does the same immediately.
- [ ] **No leak:** 100 create → use → teardown cycles show flat memory in Instruments
      (Allocations + Leaks), not monotonic growth.
- [ ] **Timeout:** a connector that hangs a request is aborted at 10s and a whole hung call at
      15s, and neither takes down any other connector's context.

If any fail, that's the spike doing its job — fix the contract or the bridge **now**, while
changing a frozen doc is cheap, before connectors are built against it.

---

## Note on the connector's form

`connector/podcast-rss.js` is the **bundled** form: a classic script that assigns
`globalThis.connectorInstance`, which is what a `JSContext` evaluates. In production, authors
write an ES module with `export default connector` (doc 03 §4) and the SDK CLI emits this form.
The spike uses the bundled form directly so the identical source runs in both the Node
validation and the iOS bridge.
