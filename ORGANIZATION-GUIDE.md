# File Organization Guide for Xcode

## Current State

The source files were created with flattened names:
```
RuntimeSpikeRuntimeSDKRuntimeBridge.swift
RuntimeSpikeRuntimeSDKRuntimeModels.swift
RuntimeSpikeRuntimeSpikeRuntimeSpikeApp.swift
RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeTests.swift
```

## Target Structure

They need to be organized into proper Xcode groups/folders:

```
RuntimeSpike/
├── RuntimeSpike/
│   ├── RuntimeSpikeApp.swift
│   └── ContentView.swift
├── RuntimeSDK/
│   ├── RuntimeBridge.swift
│   ├── RuntimeModels.swift
│   └── ConnectorError.swift
├── RuntimeSpikeTests/
│   ├── ConnectorRuntimeTests.swift
│   ├── ConnectorRuntimeLeakTests.swift
│   ├── FixtureURLProtocol.swift
│   └── PodcastRSSFixtures.swift
├── SampleConnectors/
│   └── podcast-rss.js
└── Fixtures/
    └── PodcastRSS/
        └── (JSON files)
```

## File Mapping

| Current Flat Name | Target Location |
|-------------------|-----------------|
| `RuntimeSpikeRuntimeSDKRuntimeBridge.swift` | `RuntimeSDK/RuntimeBridge.swift` |
| `RuntimeSpikeRuntimeSDKRuntimeModels.swift` | `RuntimeSDK/RuntimeModels.swift` |
| `RuntimeSpikeRuntimeSDKConnectorError.swift` | `RuntimeSDK/ConnectorError.swift` |
| `RuntimeSpikeRuntimeSpikeRuntimeSpikeApp.swift` | `RuntimeSpike/RuntimeSpikeApp.swift` |
| `RuntimeSpikeRuntimeSpikeContentView.swift` | `RuntimeSpike/ContentView.swift` |
| `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeTests.swift` | `RuntimeSpikeTests/ConnectorRuntimeTests.swift` |
| `RuntimeSpikeRuntimeSpikeTestsConnectorRuntimeLeakTests.swift` | `RuntimeSpikeTests/ConnectorRuntimeLeakTests.swift` |
| `RuntimeSpikeRuntimeSpikeTestsFixtureURLProtocol.swift` | `RuntimeSpikeTests/FixtureURLProtocol.swift` |
| `RuntimeSpikeRuntimeSpikeTestsPodcastRSSFixtures.swift` | `RuntimeSpikeTests/PodcastRSSFixtures.swift` |
| `RuntimeSpikeSampleConnectorspodcast-rss.js` | `SampleConnectors/podcast-rss.js` |
| `RuntimeSpikeFixturesPodcastRSS*.json` | `Fixtures/PodcastRSS/*.json` |

## Next Steps in Xcode

1. **Create folder groups** in Xcode:
   - Right-click project → New Group → "RuntimeSDK"
   - Right-click project → New Group → "RuntimeSpikeTests"
   - Right-click project → New Group → "SampleConnectors"
   - Right-click project → New Group → "Fixtures" → New Group → "PodcastRSS"

2. **Move/rename files** in Xcode:
   - Select file → Show File Inspector → rename
   - Drag into appropriate group

3. **Or use Finder**:
   - Organize files in Finder first
   - Then add to Xcode with proper structure

## I Can Help

Would you like me to:
1. **Create properly named copies** of all files?
2. **Generate a shell script** to organize them?
3. **Walk through the Xcode setup** step by step?

Let me know and I'll assist!
