# Runtime Spike — Project Structure

This is a clean, modular project structure treating the Runtime SDK as a first-class citizen from day one.

## Directory Layout

```
RuntimeSpike/
├── RuntimeSpike.xcodeproj/          # Xcode project
├── RuntimeSpike/                     # Minimal app shell (hosts the runtime)
│   ├── RuntimeSpikeApp.swift
│   └── ContentView.swift
├── RuntimeSDK/                       # The trust boundary — will become its own package
│   ├── RuntimeBridge.swift          # JSContext lifecycle, native bridge, enforcement
│   ├── RuntimeModels.swift          # Codable contracts (CatalogItem, MediaDetails, etc.)
│   └── ConnectorError.swift         # Normalized error model
├── RuntimeSpikeTests/                # Unit tests mirroring validation/run-validation.mjs
│   ├── ConnectorRuntimeTests.swift  # Contract + happy path + error scenarios
│   ├── ConnectorRuntimeLeakTests.swift  # Memory/lifecycle validation
│   ├── FixtureURLProtocol.swift     # Offline HTTP stubbing
│   └── PodcastRSSFixtures.swift     # Fixture registration helper
├── SampleConnectors/                 # Reference connectors (canonical SDK examples)
│   ├── podcast-rss.js               # THE GOLDEN CONNECTOR — study this first
│   └── manifest.json
├── Fixtures/                         # Test fixtures organized by connector
│   └── PodcastRSS/
│       ├── search-history.json
│       ├── show-42.json
│       ├── episode-ep-1001-stream.json
│       ├── show-not-found.txt
│       ├── search-broken.html
│       └── search-slow.json
└── Docs/                            # Frozen contract specs (living here for reference)
    ├── 03-runtime-sdk-specification.md
    ├── 04-data-contracts.md
    ├── 05-security-model.md
    └── README.md  (the spike README)
```

## What Each Component Does

### RuntimeSpike (app target)
Intentionally minimal — just enough to host and exercise the runtime on-device. The spike validates contracts and lifecycle; real app UI comes later.

### RuntimeSDK (module → future package)
The entire trust boundary. A connector's JSContext, the injected `Runtime` global, allowlist enforcement, timeout/quota enforcement, return-value validation. This is modular from day one so it can become a Swift Package once proven.

### RuntimeSpikeTests
Swift mirrors of `validation/run-validation.mjs` (23/23). Every test creates a **fresh runtime** (no state leakage). Uses `FixtureURLProtocol` to run completely offline with deterministic responses.

### SampleConnectors
**podcast-rss.js is the reference connector** — the canonical SDK implementation that connector authors should study. Fully documented inline. Treat it as the golden example, not just a test asset.

### Fixtures
Organized by connector (PodcastRSS, future: Jellyfin, YouTube, etc.). Each connector's fixtures live in their own subdirectory for scalability.

## Requirements

- iOS 18+
- macOS 15+ (for fast test iteration)
- Swift 6
- Strict Concurrency enabled
- XCTest (Swift Testing can be added later)
- Swift Package Manager only (no CocoaPods)

## Building

Open `RuntimeSpike.xcodeproj` in Xcode 16+.

1. **Fast loop (macOS):** Run `ConnectorRuntimeTests` and `ConnectorRuntimeLeakTests` on macOS. These tests run offline via fixtures and validate the JS bridging without needing a device.

2. **Real loop (iOS device):** Run the same tests on a physical iOS device to validate the on-device criteria from the spike README:
   - Isolation is real (JSContext-level)
   - Teardown actually returns memory
   - 100 create/use/teardown cycles show flat memory in Instruments
   - Timeouts/redirects/allowlist enforcement work as specified

## Pass/Fail Criteria

The spike **passes** when all six criteria in `Docs/README.md` hold on a physical iOS device. See that doc for the full checklist.

## Next Steps After the Spike Passes

Once all tests are green on-device and the criteria pass:

1. Extract RuntimeSDK as a Swift Package
2. Build the first real vertical slice: Jellyfin connector end-to-end with actual SwiftUI
3. Continue working in vertical slices (don't build every layer at once)

## Notes

- **Every test creates a fresh runtime** — no shared state, mirrors production isolation
- **Fixtures are deterministic** — no network, no flakiness, instant execution
- **The SDK is modular from day one** — designed to become a package once proven
- **podcast-rss.js is the golden connector** — connector authors should study it as the canonical example
