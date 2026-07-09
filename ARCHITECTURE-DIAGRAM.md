# SwiftUI App Architecture Diagram

## Complete System Flow

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                    ConnectorApp (@main)                   ┃
┃  • Installs example connector on launch                   ┃
┃  • Presents ContentView as root                           ┃
┗━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                      │
                      ▼
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                   ContentView (TabView)                   ┃
┃  ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌──────────┐ ┃
┃  │ Search  │  │Favorites │  │Connectors │  │Settings  │ ┃
┃  └────┬────┘  └────┬─────┘  └─────┬─────┘  └────┬─────┘ ┃
┗━━━━━━━┿━━━━━━━━━━━┿━━━━━━━━━━━━━━┿━━━━━━━━━━━━━┿━━━━━━━┛
        │           │               │              │
        ▼           ▼               ▼              ▼
   ┌─────────┐ ┌─────────┐   ┌──────────┐   ┌──────────┐
   │ Search  │ │Favorites│   │Connector │   │Settings  │
   │  View   │ │  View   │   │ Manager  │   │   View   │
   └────┬────┘ └─────────┘   │   View   │   └──────────┘
        │                     └──────────┘
        │ User searches
        │ for content
        ▼
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃              RuntimeHost.shared.search()                  ┃
┃  async throws -> [CatalogItem]                            ┃
┗━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                      │
                      ▼
        ┌──────────────────────────┐
        │  Results displayed in    │
        │  scrollable grid/list    │
        └─────────┬────────────────┘
                  │ User taps item
                  ▼
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃               MediaDetailView                             ┃
┃  • Loads full details via RuntimeHost                     ┃
┃  • Displays hero image, metadata, cast                    ┃
┃  • Shows episodes (for series)                            ┃
┃  • Favorite button in toolbar                             ┃
┗━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                      │
                      ▼
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃           RuntimeHost.shared.details()                    ┃
┃  async throws -> MediaDetails                             ┃
┗━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                      │
                      ▼
        ┌──────────────────────────┐
        │ User taps "Watch" or     │
        │ selects episode          │
        └─────────┬────────────────┘
                  │
                  ▼
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                   StreamsView                             ┃
┃  • Lists available streams with quality options           ┃
┃  • Shows subtitle tracks                                  ┃
┃  • Presents StreamPlayerView on selection                 ┃
┗━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                      │
                      ▼
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃          RuntimeHost.shared.streams()                     ┃
┃  async throws -> [StreamSource]                           ┃
┗━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                      │
                      ▼
        ┌──────────────────────────┐
        │ User selects stream      │
        └─────────┬────────────────┘
                  │
                  ▼
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃              StreamPlayerView                             ┃
┃  • Video player (AVPlayer placeholder)                    ┃
┃  • Playback controls                                      ┃
┃  • URL copying for external players                       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

## Data Flow

```
┌──────────────┐
│  SwiftUI     │  User interacts with UI
│  Views       │
└──────┬───────┘
       │ async/await calls
       ▼
┌──────────────┐
│ RuntimeHost  │  Manages connector lifecycle
│  .shared     │  Routes calls to correct runtime
└──────┬───────┘
       │ 
       ▼
┌──────────────┐
│  Connector   │  One per installed connector
│  Runtime     │  JSVirtualMachine + JSContext
└──────┬───────┘
       │ JavaScript execution
       ▼
┌──────────────┐
│  Connector   │  User's JavaScript code
│  JavaScript  │  search/getDetails/getStreams
└──────┬───────┘
       │ Runtime.request()
       ▼
┌──────────────┐
│  URLSession  │  Network requests with:
│  + Delegate  │  • Domain validation
│              │  • Redirect checking
│              │  • Timeout enforcement
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  External    │  Media API server
│  API         │
└──────────────┘
```

## Security Layers

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                  User's Device                           ┃
┃                                                          ┃
┃  ┌────────────────────────────────────────────────┐    ┃
┃  │            SwiftUI App (Trusted)               │    ┃
┃  │  • User data storage                           │    ┃
┃  │  • Payment processing                          │    ┃
┃  │  • Personal information                        │    ┃
┃  └───────────────────┬────────────────────────────┘    ┃
┃                      │                                  ┃
┃  ════════════════════╪═══════════════════════════════  ┃
┃       TRUST BOUNDARY │ RuntimeBridge.swift             ┃
┃  ════════════════════╪═══════════════════════════════  ┃
┃                      │                                  ┃
┃  ┌───────────────────▼────────────────────────────┐    ┃
┃  │      Connector JS (Untrusted/Sandboxed)        │    ┃
┃  │  ✅ Can call Runtime.request() [validated]     │    ┃
┃  │  ✅ Can use Runtime.storage [quota enforced]   │    ┃
┃  │  ✅ Can log messages [sanitized]               │    ┃
┃  │  ❌ Cannot access filesystem                   │    ┃
┃  │  ❌ Cannot execute arbitrary code              │    ┃
┃  │  ❌ Cannot access user data                    │    ┃
┃  │  ❌ Cannot make unrestricted network calls     │    ┃
┃  └────────────────────────────────────────────────┘    ┃
┃                                                          ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
           │                           │
           ▼                           ▼
    ┌───────────┐              ┌──────────────┐
    │ Allowed   │              │  Blocked     │
    │ Domains   │              │  Domains     │
    │ (manifest)│              │  (rejected)  │
    └───────────┘              └──────────────┘
```

## State Management

```
┌─────────────────────────────────────────────────────────┐
│                  App State                              │
│                                                         │
│  ┌──────────────┐      ┌──────────────┐               │
│  │ @State       │      │ @Observable  │               │
│  │ View-local   │      │ Shared       │               │
│  │              │      │              │               │
│  │ • searchQuery│      │ • Favorites  │               │
│  │ • isLoading  │      │   Manager    │               │
│  │ • error      │      └──────────────┘               │
│  └──────────────┘                                      │
│                                                         │
│  ┌──────────────┐      ┌──────────────┐               │
│  │ @AppStorage  │      │ UserDefaults │               │
│  │ Preferences  │      │ Persistence  │               │
│  │              │      │              │               │
│  │ • autoPlay   │      │ • favorites  │               │
│  │ • quality    │      │ • history    │               │
│  └──────────────┘      └──────────────┘               │
│                                                         │
│         All backed by Swift Observation                │
│         (no Combine or manual publishers)              │
└─────────────────────────────────────────────────────────┘
```

## File Organization

```
YourApp/
├── App/
│   └── ConnectorApp.swift           @main entry point
│
├── Views/
│   ├── ContentView.swift            TabView root
│   ├── MediaDetailView.swift        Item details + episodes
│   ├── StreamsView.swift            Stream selection + player
│   ├── ConnectorManagerView.swift   Connector management
│   ├── SettingsView.swift           User preferences
│   └── FavoritesView.swift          Bookmarked content
│
├── Models/
│   ├── Models.swift                 Data contracts
│   └── ConnectorError.swift         Error types
│
├── Runtime/
│   └── RuntimeBridge.swift          JS execution + security
│
└── Documentation/
    ├── SwiftUI-README.md            Architecture guide
    ├── BUILD-SUMMARY.md             Feature checklist
    ├── QUICK-START.md               Getting started
    └── ARCHITECTURE-DIAGRAM.md      This file!
```

## Async Flow Example

```swift
// User taps search button
SearchView
    │
    ├─▶ .onSubmit { Task { await performSearch() } }
    │
    ▼
performSearch() async
    │
    ├─▶ searchResults = try await RuntimeHost.shared.search(...)
    │       │
    │       ▼
    │   RuntimeHost
    │       │
    │       ├─▶ runtime(for: id) throws -> ConnectorRuntime
    │       │       │
    │       │       ▼
    │       │   Returns existing or creates new runtime
    │       │
    │       ▼
    │   runtime.call("search", args: [...])
    │       │
    │       ▼
    │   withCheckedThrowingContinuation { continuation in
    │       queue.async {
    │           // Execute JS on connector's serial queue
    │           let promise = instance.invokeMethod("search", ...)
    │           promise.then(resolve, reject)
    │       }
    │   }
    │       │
    │       ▼
    │   JavaScript executes
    │       │
    │       ├─▶ Runtime.request({ url: "..." })
    │       │       │
    │       │       ▼
    │       │   URLSession with domain validation
    │       │       │
    │       │       ▼
    │       │   External API
    │       │       │
    │       │       ▼
    │       │   Response validated
    │       │       │
    │       │       ▼
    │       │   Returns to JS
    │       │
    │       ▼
    │   JS promise resolves
    │       │
    │       ▼
    │   Swift continuation resumes
    │       │
    │       ▼
    │   Decode JSValue to [CatalogItem]
    │
    ▼
SwiftUI updates with results
```

## Threading Model

```
┌────────────────────────────────────────────────────────┐
│                    Main Thread                         │
│  • SwiftUI rendering                                   │
│  • User interaction                                    │
│  • @State updates                                      │
└────────────┬───────────────────────────────────────────┘
             │
             │ Task { await ... }
             │
             ▼
┌────────────────────────────────────────────────────────┐
│              Cooperative Thread Pool                   │
│  • async/await execution                               │
│  • RuntimeHost methods                                 │
└────────────┬───────────────────────────────────────────┘
             │
             │ queue.async { ... }
             │
             ▼
┌────────────────────────────────────────────────────────┐
│         Connector Serial Queue (per runtime)           │
│  • JavaScript execution (thread-safe)                  │
│  • JSContext operations                                │
│  • Storage access (synchronized)                       │
└────────────┬───────────────────────────────────────────┘
             │
             │ URLSession delegate callbacks
             │
             ▼
┌────────────────────────────────────────────────────────┐
│              URLSession Queue                          │
│  • Network I/O                                         │
│  • Redirect validation                                 │
└────────────────────────────────────────────────────────┘
```

---

**This architecture ensures:**
- ✅ Thread safety
- ✅ Security isolation
- ✅ Smooth UI updates
- ✅ Efficient resource usage
- ✅ Testability
- ✅ Maintainability
