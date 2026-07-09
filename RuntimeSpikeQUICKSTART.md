# Quick Start Checklist

Follow these steps to get the Runtime spike compiling and running in Xcode.

## ☑️ Pre-Flight

- [ ] Xcode 16+ installed
- [ ] macOS 15+ (for testing on macOS)
- [ ] Physical iOS device available (for on-device validation)

## 1️⃣ Create Xcode Project

- [ ] Open Xcode → File → New → Project
- [ ] Template: iOS App
- [ ] Product Name: `RuntimeSpike`
- [ ] Interface: SwiftUI
- [ ] Language: Swift
- [ ] Minimum Deployment: iOS 18.0
- [ ] Save to: (location of this README's parent directory)

## 2️⃣ Configure Swift 6

- [ ] Select project in navigator
- [ ] Build Settings → Swift Compiler - Language
- [ ] Swift Language Version: **Swift 6**
- [ ] Strict Concurrency Checking: **Complete**

## 3️⃣ Add RuntimeSDK Files to App Target

Drag these files into Xcode (check "Copy items if needed" + "Add to targets: RuntimeSpike"):

- [ ] `RuntimeSDK/RuntimeBridge.swift`
- [ ] `RuntimeSDK/RuntimeModels.swift`
- [ ] `RuntimeSDK/ConnectorError.swift`

Verify they appear in:
- Project navigator → RuntimeSpike group
- Target → Build Phases → Compile Sources

## 4️⃣ Add App Files

These should already exist if you created the project correctly:

- [ ] `RuntimeSpike/RuntimeSpikeApp.swift` ← Replace with provided version
- [ ] `RuntimeSpike/ContentView.swift` ← Replace with provided version

## 5️⃣ Link JavaScriptCore Framework

- [ ] Select app target → General → Frameworks, Libraries, and Embedded Content
- [ ] Click **+** → Add `JavaScriptCore.framework`
- [ ] Set to "Do Not Embed"

## 6️⃣ Create Test Target

- [ ] File → New → Target
- [ ] Template: **Unit Testing Bundle**
- [ ] Product Name: `RuntimeSpikeTests`
- [ ] Test Host: RuntimeSpike

## 7️⃣ Add Test Files to Test Target

Drag these files into Xcode (add to target: RuntimeSpikeTests):

- [ ] `RuntimeSpikeTests/ConnectorRuntimeTests.swift`
- [ ] `RuntimeSpikeTests/ConnectorRuntimeLeakTests.swift`
- [ ] `RuntimeSpikeTests/FixtureURLProtocol.swift`
- [ ] `RuntimeSpikeTests/PodcastRSSFixtures.swift`

Also add RuntimeSDK files to test target:
- [ ] `RuntimeSDK/RuntimeBridge.swift`
- [ ] `RuntimeSDK/RuntimeModels.swift`
- [ ] `RuntimeSDK/ConnectorError.swift`

## 8️⃣ Add Resources to Test Target

Drag these as **resources** (not compiled sources):

- [ ] `SampleConnectors/podcast-rss.js`
- [ ] `Fixtures/PodcastRSS/search-history.json`
- [ ] `Fixtures/PodcastRSS/show-42.json`
- [ ] `Fixtures/PodcastRSS/episode-ep-1001-stream.json`
- [ ] `Fixtures/PodcastRSS/show-not-found.txt`
- [ ] `Fixtures/PodcastRSS/search-broken.html`
- [ ] `Fixtures/PodcastRSS/search-slow.json`

**Verify:** These appear in Target → Build Phases → Copy Bundle Resources (NOT Compile Sources)

## 9️⃣ Link JavaScriptCore to Test Target

- [ ] Select test target → General → Frameworks and Libraries
- [ ] Click **+** → Add `JavaScriptCore.framework`

## 🔟 Configure Test Target Build Settings

- [ ] Select test target → Build Settings
- [ ] Swift Language Version: **Swift 6**
- [ ] Strict Concurrency Checking: **Complete**

## 1️⃣1️⃣ Build & Test (macOS)

- [ ] Select scheme: RuntimeSpike
- [ ] Destination: **My Mac** (or "Mac Designed for iPad")
- [ ] Product → Build (⌘B)
- [ ] Verify build succeeds
- [ ] Product → Test (⌘U)
- [ ] Verify all tests pass:
  - [ ] `testSearchHappyPath`
  - [ ] `testDetailsIncludeEpisodes`
  - [ ] `testStreamsResolve`
  - [ ] `testNotFoundMapsThrough`
  - [ ] `testGetStreamsWithoutEpisodeIdReturnsNotFound`
  - [ ] `testInvalidResponseFromUpstream`
  - [ ] `testUndeclaredDomainBlocked`
  - [ ] `testStorageQuotaEnforced`
  - [ ] `testMalformedConnectorReturnRejected`
  - [ ] `testTimeoutOnSlowRequest`
  - [ ] `testConnectorStorageIsIsolated`
  - [ ] `testRuntimeDeallocatesAfterUse`
  - [ ] `testSessionDelegateDeallocatesAfterTeardown`
  - [ ] `testNoLeakAcrossManyCycles`
  - [ ] `testTeardownIsPromptNotTimeoutBound`

## 1️⃣2️⃣ On-Device Validation

- [ ] Connect physical iOS device
- [ ] Select device as destination
- [ ] Product → Test (⌘U)
- [ ] Verify all tests pass on device

## 1️⃣3️⃣ Memory Validation (Instruments)

- [ ] Product → Profile (⌘I)
- [ ] Choose: **Allocations**
- [ ] Run `testNoLeakAcrossManyCycles`
- [ ] Verify: Memory graph shows flat line (no monotonic growth)
- [ ] Choose: **Leaks**
- [ ] Run all tests
- [ ] Verify: No leaks detected

## 1️⃣4️⃣ Walk the Six Pass/Fail Criteria

From `Docs/README.md`:

- [ ] **Flow works**: Run `testSearchHappyPath` → `testDetailsIncludeEpisodes` → `testStreamsResolve` on device
- [ ] **Isolation is real**: `testConnectorStorageIsIsolated` passes (structural guarantee via separate JSContexts)
- [ ] **Allowlist enforced**: `testUndeclaredDomainBlocked` passes, redirects re-checked
- [ ] **Teardown works**: `testRuntimeDeallocatesAfterUse` passes, memory returns to baseline
- [ ] **No leaks**: `testNoLeakAcrossManyCycles` passes in Instruments with flat memory
- [ ] **Timeouts work**: `testTimeoutOnSlowRequest` passes, hung requests abort safely

## ✅ Success Criteria

**The spike passes when:**
- All tests are green on macOS ✅
- All tests are green on iOS device ✅
- Instruments shows flat memory (no leaks) ✅
- All six criteria from the spike README are verified ✅

## 🚨 Troubleshooting

### Build Error: "Cannot find 'RuntimeSDK' in scope"

**Fix:** RuntimeSDK files must be in both app and test target compile sources.

### Test Fails: "Fixture not found"

**Fix:** Verify resources are in test target's Copy Bundle Resources phase, not Compile Sources.

### Test Fails: "Add SampleConnectors/podcast-rss.js to test target's resources"

**Fix:** Drag `SampleConnectors/podcast-rss.js` into Xcode and ensure it's checked for RuntimeSpikeTests target.

### Leak Test Fails: "URLSession delegate leaked"

**Fix:** This indicates `session.invalidateAndCancel()` isn't being called. Verify `RuntimeBridge.swift` has `deinit { session?.invalidateAndCancel() }`.

### Leak Test Fails: "Runtime leaked"

**Fix:** This indicates the timeout work item is capturing `self` strongly. Verify `RuntimeBridge.swift` uses `[weak self]` in the timeout DispatchWorkItem.

## 📚 Next Steps

Once all tests pass:
1. Read `SETUP-INSTRUCTIONS.md` for design decisions and next steps
2. Read `PROJECT-README.md` for project structure details
3. Study `SampleConnectors/podcast-rss.js` — the golden connector
4. Begin work on the first real vertical slice (Jellyfin connector)

---

**Need help?** Check:
- `SETUP-INSTRUCTIONS.md` — Detailed setup guide
- `PROJECT-README.md` — Project structure overview
- `Docs/README.md` — Spike pass/fail criteria
- `Docs/03-runtime-sdk-specification.md` — The SDK contract
