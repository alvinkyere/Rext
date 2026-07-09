# ✅ FILES TO USE IN YOUR XCODE PROJECT

## The Situation

You have TWO sets of files:
1. **Original files** with clean names (RuntimeBridge.swift, etc.) - from the original repo
2. **New files** I created with prefixed names (RuntimeSpikeRuntimeSDKRuntimeBridge.swift, etc.) - my improved versions

**Use the NEW (prefixed) files** because they have:
- ✅ Swift 6 compatibility
- ✅ Sendable conformance  
- ✅ Public initializers (needed for tests)
- ✅ Both leak fixes implemented
- ✅ Proper @Sendable annotations

## Step-by-Step: Add to Xcode

### 1. Create Groups in Xcode

Right-click project → New Group for each:
- `RuntimeSDK`
- `RuntimeSpikeTests`
- `SampleConnectors`  
- `Fixtures` (with subfolder `PodcastRSS`)

### 2. Add RuntimeSDK Files

Drag these into the `RuntimeSDK` group:
- ✅ `RuntimeSpikeRuntimeSDKRuntimeBridge.swift`
- ✅ `RuntimeSpikeRuntimeSDKRuntimeModels.swift`
- ✅ `RuntimeSpikeRuntimeSDKConnectorError.swift`

**Then rename** each in File Inspector:
- → `RuntimeBridge.swift`
- → `RuntimeModels.swift`
- → `ConnectorError.swift`

**Target Membership:** Check BOTH RuntimeSpike AND RuntimeSpikeTests

### 3. Add App Files

Drag into main RuntimeSpike group:
- ✅ `RuntimeSpikeRuntimeSpikeRuntimeSpikeApp.swift` → rename to `RuntimeSpikeApp.swift`
- ✅ `RuntimeSpikeRuntimeSpikeContentView.swift` → rename to `ContentView.swift`

**Target:** RuntimeSpike only

### 4. Add Test Files

Drag into `RuntimeSpikeTests` group:
- ✅ `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeTests.swift` → rename to `ConnectorRuntimeTests.swift`
- ✅ `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeLeakTests.swift` → rename to `ConnectorRuntimeLeakTests.swift`
- ✅ `RuntimeSpikeRuntimeSpikeTestsFixtureURLProtocol.swift` → rename to `FixtureURLProtocol.swift`
- ✅ `RuntimeSpikeRuntimeSpikeTestsPodcastRSSFixtures.swift` → rename to `PodcastRSSFixtures.swift`

**Target:** RuntimeSpikeTests only

### 5. Add Connector (as Resource!)

Drag into `SampleConnectors` group:
- ✅ `RuntimeSpikeSampleConnectorspodcast-rss.js` → rename to `podcast-rss.js`

**IMPORTANT:** 
- Target: RuntimeSpikeTests  
- Build Phase: **Copy Bundle Resources** (NOT Compile Sources!)

### 6. Add Fixtures (as Resources!)

Drag into `Fixtures/PodcastRSS` group:
- ✅ `RuntimeSpikeFixturesPodcastRSSsearch-history.json` → `search-history.json`
- ✅ `RuntimeSpikeFixturesPodcastRSSshow-42.json` → `show-42.json`
- ✅ All other `RuntimeSpikeFixturesPodcastRSS*.json/txt/html` files

**IMPORTANT:**
- Target: RuntimeSpikeTests
- Build Phase: **Copy Bundle Resources** (NOT Compile Sources!)

### 7. Configure Targets

**Both targets:**
1. Build Settings → Swift Language Version → **Swift 6**
2. Build Settings → Strict Concurrency Checking → **Complete**  
3. General → Frameworks → Add **JavaScriptCore.framework**

### 8. Build & Test

1. ⌘B to build
2. ⌘U to run tests

## 🎯 Expected Result

All tests should pass:
- testSearchHappyPath ✅
- testDetailsIncludeEpisodes ✅
- testStreamsResolve ✅
- testNotFoundMapsThrough ✅
- (and 11 more tests) ✅

## 🚨 If You Get Errors

**"Cannot find module RuntimeSDK"**
→ Make sure RuntimeSDK files are in BOTH target membership

**"Fixture not found"**
→ Check that .js and .json files are in "Copy Bundle Resources" phase

**Module compiled with different Swift version**
→ Make sure ALL targets are set to Swift 6

## 💡 Want Me to Create Clean Files Instead?

If renaming is tedious, tell me and I'll create brand new files with clean names.

Otherwise, follow the steps above and you'll be running tests in 10 minutes!
