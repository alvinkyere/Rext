# IMMEDIATE ACTION PLAN

Since you have an Xcode project open, here's what to do RIGHT NOW:

## ✅ Step 1: Understand What You Have

All source files exist but with flattened names like `RuntimeSpikeRuntimeSDKRuntimeBridge.swift`.

These need to be **renamed** and **organized into groups** in Xcode.

## ✅ Step 2: Create the Module Structure

In Xcode's Project Navigator:

1. **Right-click** on your project root
2. **New Group** → Name it `RuntimeSDK`
3. **New Group** → Name it `RuntimeSpikeTests`
4. **New Group** → Name it `SampleConnectors`
5. **New Group** → Name it `Fixtures`
   - Inside Fixtures: **New Group** → Name it `PodcastRSS`

## ✅ Step 3: Add the Core SDK Files

### RuntimeSDK Group:

Find these files in your project and **drag them** into the RuntimeSDK group:
- `RuntimeSpikeRuntimeSDKRuntimeBridge.swift` → rename to `RuntimeBridge.swift`
- `RuntimeSpikeRuntimeSDKRuntimeModels.swift` → rename to `RuntimeModels.swift`
- `RuntimeSpikeRuntimeSDKConnectorError.swift` → rename to `ConnectorError.swift`

**To rename:** Select file → File Inspector (⌥⌘1) → change Name field

### Add to Targets:
- Select each file
- File Inspector → Target Membership
- Check: ✅ RuntimeSpike (app target)
- Check: ✅ RuntimeSpikeTests (test target)

## ✅ Step 4: Add Test Files

Find and move to RuntimeSpikeTests group:
- `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeTests.swift` → rename to `ConnectorRuntimeTests.swift`
- `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeLeakTests.swift` → rename to `ConnectorRuntimeLeakTests.swift`
- `RuntimeSpikeRuntimeSpikeTestsFixtureURLProtocol.swift` → rename to `FixtureURLProtocol.swift`
- `RuntimeSpikeRuntimeSpikeTestsPodcastRSSFixtures.swift` → rename to `PodcastRSSFixtures.swift`

**Target:** ✅ RuntimeSpikeTests only

## ✅ Step 5: Add App Files

Find and keep in RuntimeSpike group:
- `RuntimeSpikeRuntimeSpikeRuntimeSpikeApp.swift` → rename to `RuntimeSpikeApp.swift`
- `RuntimeSpikeRuntimeSpikeContentView.swift` → rename to `ContentView.swift`

**Target:** ✅ RuntimeSpike (app) only

## ✅ Step 6: Add Resources

Find and move to appropriate groups:

**SampleConnectors:**
- `RuntimeSpikeSampleConnectorspodcast-rss.js` → rename to `podcast-rss.js`

**Fixtures/PodcastRSS:**
- `RuntimeSpikeFixturesPodcastRSSsearch-history.json` → rename to `search-history.json`
- `RuntimeSpikeFixturesPodcastRSSshow-42.json` → rename to `show-42.json`
- (and any other fixture files)

**IMPORTANT:** These are RESOURCES, not source files!
- Select each file
- File Inspector → Target Membership
- Uncheck "Compile Sources"
- Check "Copy Bundle Resources" for RuntimeSpikeTests

## ✅ Step 7: Configure Build Settings

### App Target (RuntimeSpike):
1. Select project → select RuntimeSpike target
2. Build Settings tab
3. Search "Swift Language Version" → set to **Swift 6**
4. Search "Strict Concurrency" → set to **Complete**
5. General tab → Frameworks → Add **JavaScriptCore.framework**

### Test Target (RuntimeSpikeTests):
1. Select project → select RuntimeSpikeTests target
2. Same build settings as above
3. General tab → Frameworks → Add **JavaScriptCore.framework**

## ✅ Step 8: Build!

1. **⌘B** to build
2. Fix any errors (likely just module names or paths)
3. **⌘U** to run tests

## 🚨 Quick Troubleshooting

**"Cannot find RuntimeSDK in scope"**
→ Make sure RuntimeSDK files are added to BOTH targets

**"Fixture not found"**
→ Make sure .js and .json files are in "Copy Bundle Resources" NOT "Compile Sources"

**"Module compiled with Swift X"**
→ Make sure ALL targets use Swift 6

## 💡 Alternative: I Can Create Clean Files

If this is too tedious, I can:
1. Create new files with proper names (no RuntimeSpike prefix)
2. You just add them to Xcode fresh
3. Delete the old flattened-name files

Would you like me to do that instead?
