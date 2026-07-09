# 🧪 Adding Tests to Your Runtime Project

You now have 3 test files ready to add. Here's how to set them up:

## Step 1: Create Test Target

1. In Xcode: **File → New → Target**
2. Choose **Unit Testing Bundle**
3. Product Name: **RuntimeTests**
4. Test Host: **Runtime** (your app)
5. Click **Finish**

## Step 2: Add Test Files

Drag these files into your **RuntimeTests** group:

1. **Test-FixtureURLProtocol.swift** → Rename to `FixtureURLProtocol.swift`
2. **Test-ConnectorRuntimeTests.swift** → Rename to `ConnectorRuntimeTests.swift`
3. **Test-PodcastRSSFixtures.swift** → Rename to `PodcastRSSFixtures.swift`

**Target Membership:** Check ✅ RuntimeTests (test target only)

## Step 3: Add Runtime Module to Tests

The test files need access to your app's code:

1. Select **RuntimeTests** target
2. Build Phases → Link Binary With Libraries
3. Click **+** → Add **Runtime** (your app target)

OR simply make sure the RuntimeSDK files are also in the test target compile sources.

## Step 4: Add the Connector as a Resource

You need `podcast-rss.js`:

1. In Xcode, right-click RuntimeTests group
2. **Add Files to "Runtime"...**
3. Navigate to where you saved `podcast-rss.js` (I'll create it next)
4. **IMPORTANT:** Check "Copy items if needed"
5. **Target:** Check ✅ RuntimeTests only
6. **Verify:** File should appear in Build Phases → Copy Bundle Resources (NOT Compile Sources)

## Step 5: Link JavaScriptCore

1. Select **RuntimeTests** target
2. General → Frameworks and Libraries
3. Click **+** → Add `JavaScriptCore.framework`

## Step 6: Configure Build Settings

1. Select **RuntimeTests** target
2. Build Settings:
   - Swift Language Version: **Swift 6**
   - Strict Concurrency: **Complete**

## Step 7: Run Tests!

**⌘U** (Run Tests)

You should see:
- ✅ `testSearchHappyPath`
- ✅ `testDetailsIncludeEpisodes`
- ✅ `testStreamsResolve`
- ✅ `testNotFoundMapsThrough`
- ✅ `testUndeclaredDomainBlocked`
- ✅ `testStorageQuotaEnforced`
- ✅ `testMalformedReturnRejected`

**7 tests passing** proves your runtime works! 🎉

---

## Next: I Need to Create podcast-rss.js

Tell me when you've added the test files and I'll create the connector JavaScript file for you!
