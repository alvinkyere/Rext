# 🚨 IMMEDIATE FIX FOR YOUR BUILD ERRORS

## Problem Summary
You have duplicate files causing "Invalid redeclaration" errors and test files trying to import a non-existent "RuntimeSDK" module.

## ✅ SOLUTION (5 Steps)

### Step 1: Remove Duplicate Files from Runtime Target

In Xcode, **select and DELETE** these files (they're duplicates):

1. ❌ `RuntimeSpikeRuntimeSpikeContentView.swift` (you already have `ContentView.swift`)
2. ❌ `RuntimeSpikeRuntimeSpikeRuntimeSpikeApp.swift` (you already have `RuntimeApp.swift`)

**How:** Select file → Right-click → Delete → Move to Trash

### Step 2: Remove Test Files from Runtime App Target

These files should NOT be in your app target. Select each and remove from Runtime target:

1. ❌ `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeTests.swift`
2. ❌ `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeLeakTests.swift`
3. ❌ `RuntimeSpikeRuntimeSpikeTestsFixtureURLProtocol.swift`
4. ❌ `RuntimeSpikeRuntimeSpikeTestsPodcastRSSFixtures.swift`

**How:** Select file → File Inspector (⌥⌘1) → Target Membership → **Uncheck** "Runtime"

### Step 3: Choose ONE RuntimeBridge

You have two RuntimeBridge files. Pick ONE:

**Option A:** Keep `RuntimeBridge.swift` (shorter name)
- Delete: `RuntimeSpikeRuntimeSDKRuntimeBridge.swift`

**Option B:** Keep `RuntimeSpikeRuntimeSDKRuntimeBridge.swift` (my improved version with Swift 6 fixes)
- Delete: `RuntimeBridge.swift`

**I recommend Option B** because it has the leak fixes and Swift 6 compatibility.

If you choose Option B, also delete these old files:
- ❌ `RuntimeModels.swift` (keep `RuntimeSpikeRuntimeSDKRuntimeModels.swift`)
- ❌ `ConnectorError.swift` (keep `RuntimeSpikeRuntimeSDKConnectorError.swift`)

### Step 4: Make Types Public

Open whichever RuntimeBridge/RuntimeModels/ConnectorError files you kept and add `public` to these declarations:

**RuntimeModels.swift:**
```swift
public enum CatalogKind: String, Codable, Sendable { ... }
public enum JSONScalar: Codable, Equatable, Sendable { ... }
public struct CatalogItem: Codable, Sendable { ... }
public struct EpisodeRef: Codable, Sendable { ... }
public struct MediaDetails: Codable, Sendable { ... }
public struct SubtitleTrack: Codable, Sendable { ... }
public struct StreamSource: Codable, Sendable { ... }
public struct ConnectorManifest: Codable, Sendable { ... }
```

**ConnectorError.swift:**
```swift
public enum ConnectorErrorCode: String, Codable, Sendable { ... }
public struct ConnectorError: Error, CustomStringConvertible, Sendable { ... }
```

**RuntimeBridge.swift:**
```swift
public final class ConnectorRuntime: @unchecked Sendable { ... }
public final class RuntimeHost: @unchecked Sendable { ... }
```

### Step 5: Fix Test Imports

**Option A (Quick):** Change test files to import your app module:

In all test files, change:
```swift
@testable import RuntimeSDK  // ❌ This module doesn't exist
```

To:
```swift
@testable import Runtime  // ✅ Your app's module name
```

**Files to fix:**
- `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeTests.swift`
- `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeLeakTests.swift`

**Option B (Better):** Use the fixed version I just created:
- Delete the old test files
- Add `ConnectorRuntimeTests-Fixed.swift` instead

## After These 5 Steps

1. **⌘B** to build
2. Build should succeed ✅
3. **⌘U** to run tests (but you'll need to create a test target first - see below)

## Creating Test Target

If you don't have a test target yet:

1. File → New → Target
2. Choose "Unit Testing Bundle"  
3. Name it "RuntimeTests"
4. Host Application: Runtime

Then add all the test files to ONLY the test target.

## Quick Test

After fixing, try building with ⌘B. You should see:

✅ Build Succeeded

Then tell me the result and I'll help with the next step!
