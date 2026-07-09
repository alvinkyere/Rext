# ✅ CLEAN START - Add These Files

You now have **5 clean files** ready to add to your Xcode project.

## Step 1: Add These Files to Your Runtime App Target

In Xcode, drag these files into your project:

1. **Clean-RuntimeApp.swift** → Rename to `RuntimeApp.swift` (replace your existing one)
2. **Clean-ContentView.swift** → Rename to `ContentView.swift` (replace your existing one)
3. **Clean-RuntimeBridge.swift** → Rename to `RuntimeBridge.swift`
4. **Clean-RuntimeModels.swift** → Rename to `RuntimeModels.swift`
5. **Clean-ConnectorError.swift** → Rename to `ConnectorError.swift`

**Target Membership:** Check ✅ Runtime (your app target)

## Step 2: Link JavaScriptCore Framework

1. Select Runtime target → General tab
2. Frameworks, Libraries, and Embedded Content
3. Click **+** → Search "JavaScriptCore" → Add
4. Set to "Do Not Embed"

## Step 3: Configure Build Settings

1. Select Runtime target → Build Settings
2. Swift Language Version → **Swift 6**
3. Strict Concurrency Checking → **Complete**
4. iOS Deployment Target → **iOS 18.0** (or your minimum)

## Step 4: Build!

1. **⇧⌘K** (Clean Build Folder)
2. **⌘B** (Build)

✅ **It should build successfully!**

## What You Have

A minimal but complete Runtime spike:
- ✅ SwiftUI app shell
- ✅ Complete RuntimeBridge with all security enforcement
- ✅ All data contracts (Codable models)
- ✅ Error handling
- ✅ Swift 6 compatible
- ✅ All public types for future testing
- ✅ Both leak fixes implemented

## Next Steps (After Build Succeeds)

1. Create a test target
2. Add test files (I'll create clean versions when you're ready)
3. Add the podcast connector
4. Add fixtures
5. Run tests!

---

**Try building now and tell me if it works!** 🚀
