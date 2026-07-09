# Complete File Listing

This document lists every file in the RuntimeSpike project for easy reference when setting up the Xcode project.

## Documentation Files (Root Level)

```
RuntimeSpike/
├── README.md                        # Project summary + quick overview
├── QUICKSTART.md                    # Step-by-step setup checklist ⭐ START HERE
├── SETUP-INSTRUCTIONS.md            # Detailed setup + troubleshooting
├── ARCHITECTURE-DECISIONS.md        # Design decisions + rationale
├── ARCHITECTURE-DIAGRAM.md          # Visual architecture diagrams
└── PROJECT-README.md                # Project structure overview
```

## App Target Files

```
RuntimeSpike/RuntimeSpike/
├── RuntimeSpikeApp.swift            # SwiftUI @main entry point
└── ContentView.swift                # Placeholder UI (minimal shell)
```

**Add to target:** `RuntimeSpike` (app target)  
**Compile as:** Source files  
**Framework dependencies:** None (SwiftUI is implicit)

## RuntimeSDK Files (The Trust Boundary)

```
RuntimeSpike/RuntimeSDK/
├── RuntimeBridge.swift              # JSContext lifecycle + native bridge
├── RuntimeModels.swift              # Codable contracts (CatalogItem, etc.)
└── ConnectorError.swift             # Normalized error model
```

**Add to targets:** 
- `RuntimeSpike` (app target) — so it compiles into a module
- `RuntimeSpikeTests` (test target) — so tests can `@testable import RuntimeSDK`

**Compile as:** Source files  
**Framework dependencies:** `JavaScriptCore.framework`

## Test Files

```
RuntimeSpike/RuntimeSpikeTests/
├── ConnectorRuntimeTests.swift      # Contract + happy path + error tests
├── ConnectorRuntimeLeakTests.swift  # Memory/lifecycle validation
├── FixtureURLProtocol.swift         # Generic HTTP stubbing
└── PodcastRSSFixtures.swift         # Fixture registration helper
```

**Add to target:** `RuntimeSpikeTests` (test target)  
**Compile as:** Source files  
**Framework dependencies:** 
- `JavaScriptCore.framework`
- `XCTest.framework` (implicit)

## Sample Connector (Reference Implementation)

```
RuntimeSpike/SampleConnectors/
├── podcast-rss.js                   # THE GOLDEN CONNECTOR ⭐
└── manifest.json                    # Connector manifest
```

**Add to target:** `RuntimeSpikeTests` (test target)  
**Compile as:** ❌ NO — Add as **Resources** (Copy Bundle Resources)  
**Bundle structure:** Should be loadable via:
```swift
Bundle(for: ConnectorRuntimeTests.self).url(forResource: "podcast-rss", withExtension: "js")
```

## Test Fixtures

```
RuntimeSpike/Fixtures/PodcastRSS/
├── search-history.json              # Happy path search results
├── show-42.json                     # Happy path show details
├── episode-ep-1001-stream.json      # Happy path stream resolution
├── show-not-found.txt               # 404 error fixture
├── search-broken.html               # Non-JSON response fixture
└── search-slow.json                 # Timeout test fixture (20s delay)
```

**Add to target:** `RuntimeSpikeTests` (test target)  
**Compile as:** ❌ NO — Add as **Resources** (Copy Bundle Resources)  
**Bundle structure:** Should be in `Fixtures/PodcastRSS/` subdirectory:
```swift
Bundle(for: ConnectorRuntimeTests.self).url(
    forResource: "search-history", 
    withExtension: "json", 
    subdirectory: "Fixtures/PodcastRSS"
)
```

## File Count Summary

- **Documentation:** 6 files
- **App target:** 2 files
- **RuntimeSDK:** 3 files
- **Tests:** 4 files
- **Sample connector:** 2 files
- **Fixtures:** 6 files

**Total:** 23 files

## Xcode Target Configuration

### App Target: `RuntimeSpike`

**Compile Sources:**
- `RuntimeSpike/RuntimeSpikeApp.swift`
- `RuntimeSpike/ContentView.swift`
- `RuntimeSDK/RuntimeBridge.swift`
- `RuntimeSDK/RuntimeModels.swift`
- `RuntimeSDK/ConnectorError.swift`

**Resources:**
- (none)

**Frameworks:**
- `JavaScriptCore.framework`
- SwiftUI (implicit)
- Foundation (implicit)

**Build Settings:**
- Swift Language Version: Swift 6
- Strict Concurrency: Complete
- Minimum Deployment: iOS 18.0

### Test Target: `RuntimeSpikeTests`

**Compile Sources:**
- `RuntimeSpikeTests/ConnectorRuntimeTests.swift`
- `RuntimeSpikeTests/ConnectorRuntimeLeakTests.swift`
- `RuntimeSpikeTests/FixtureURLProtocol.swift`
- `RuntimeSpikeTests/PodcastRSSFixtures.swift`
- `RuntimeSDK/RuntimeBridge.swift` (also compiled into test target)
- `RuntimeSDK/RuntimeModels.swift` (also compiled into test target)
- `RuntimeSDK/ConnectorError.swift` (also compiled into test target)

**Resources (Copy Bundle Resources):**
- `SampleConnectors/podcast-rss.js`
- `SampleConnectors/manifest.json`
- `Fixtures/PodcastRSS/search-history.json`
- `Fixtures/PodcastRSS/show-42.json`
- `Fixtures/PodcastRSS/episode-ep-1001-stream.json`
- `Fixtures/PodcastRSS/show-not-found.txt`
- `Fixtures/PodcastRSS/search-broken.html`
- `Fixtures/PodcastRSS/search-slow.json`

**Frameworks:**
- `JavaScriptCore.framework`
- XCTest (implicit)

**Build Settings:**
- Swift Language Version: Swift 6
- Strict Concurrency: Complete
- Test Host: `$(BUILT_PRODUCTS_DIR)/RuntimeSpike.app/RuntimeSpike`

## Resource Bundle Verification

After adding files to the test target, verify resources are accessible:

```swift
// In a test:
func verifyResources() {
    let bundle = Bundle(for: ConnectorRuntimeTests.self)
    
    // Connector source should be loadable:
    XCTAssertNotNil(bundle.url(forResource: "podcast-rss", withExtension: "js"))
    
    // Fixtures should be in subdirectory:
    XCTAssertNotNil(bundle.url(
        forResource: "search-history",
        withExtension: "json",
        subdirectory: "Fixtures/PodcastRSS"
    ))
}
```

## Adding Files to Xcode

### Method 1: Drag & Drop (Recommended)

1. Open Xcode project
2. Drag folders into project navigator:
   - Drag `RuntimeSpike/` folder → check `RuntimeSpike` target
   - Drag `RuntimeSDK/` folder → check both targets
   - Drag `RuntimeSpikeTests/` folder → check `RuntimeSpikeTests` target
   - Drag `SampleConnectors/` folder → check `RuntimeSpikeTests` target + "Copy Bundle Resources"
   - Drag `Fixtures/` folder → check `RuntimeSpikeTests` target + "Copy Bundle Resources"

3. Verify in Build Phases:
   - Compile Sources: `.swift` files
   - Copy Bundle Resources: `.js`, `.json`, `.txt`, `.html` files

### Method 2: Add Files Menu

1. File → Add Files to "RuntimeSpike"...
2. Select files/folders
3. Check appropriate targets
4. For resources, manually move to Copy Bundle Resources phase:
   - Select target → Build Phases
   - Drag from Compile Sources to Copy Bundle Resources

## Common Mistakes to Avoid

❌ **Adding resources to Compile Sources**  
   → `.js`, `.json`, etc. should be in Copy Bundle Resources, not compiled

❌ **Not maintaining subdirectory structure**  
   → Fixtures must be in `Fixtures/PodcastRSS/` subdirectory for loader to find them

❌ **RuntimeSDK only in app target**  
   → Must be in test target too so tests can `@testable import RuntimeSDK`

❌ **Forgetting JavaScriptCore framework**  
   → Must be linked in both app and test targets

❌ **Wrong Swift version**  
   → Must be Swift 6, not 5.x

❌ **Missing strict concurrency**  
   → Build Settings → Strict Concurrency Checking: Complete

## Verification Checklist

After setting up the project:

- [ ] App target compiles (⌘B)
- [ ] Test target compiles (⌘B with test scheme)
- [ ] `@testable import RuntimeSDK` resolves in tests
- [ ] `Bundle.url(forResource: "podcast-rss", withExtension: "js")` returns non-nil
- [ ] `Bundle.url(forResource: "search-history", ...)` in subdirectory returns non-nil
- [ ] All tests run (⌘U)
- [ ] No "file not found" or "module not found" errors

## Next Steps

Once all files are added and verified:

1. Follow **QUICKSTART.md** for build & test
2. Run tests on macOS (fast loop)
3. Run tests on iOS device (on-device validation)
4. Use Instruments to verify memory behavior

---

**All files are ready to use as-is. No modifications needed before building.**
