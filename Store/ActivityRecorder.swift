import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// ActivityRecorder.swift  (Rext Roadmap Phase 4 — Activity Graph)
//
// The write and read sides of the activity timeline. `ActivityRecording` is a
// protocol so the sink can be swapped later (e.g. to also forward to the Cloud
// sync engine in Phase 7) without touching the callers. `ActivityLog` is the
// query surface the Intelligence Layer builds on.
// ---------------------------------------------------------------------------

/// Lightweight device description captured with each event. Deliberately avoids
/// UIKit so it compiles on every Apple platform; it records platform, OS version,
/// and app version rather than a hardware model string.
public struct DeviceInfo: Sendable {
    public let platform: String
    public let systemVersion: String
    public let appVersion: String

    public static var current: DeviceInfo {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return DeviceInfo(platform: Self.platformName, systemVersion: version, appVersion: app)
    }

    private static var platformName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(visionOS)
        return "visionOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "unknown"
        #endif
    }
}

/// A single app-launch session. Events recorded during the same launch share an
/// id, so the timeline can be grouped into sessions. A launch-scoped session is
/// the first implementation; background rollover can refine this later.
@MainActor
final class ActivitySession {
    static let shared = ActivitySession()

    let id: UUID
    let device: DeviceInfo

    init(id: UUID = UUID(), device: DeviceInfo = .current) {
        self.id = id
        self.device = device
    }
}

@MainActor
protocol ActivityRecording {
    func record(_ input: ActivityEventInput)
}

/// Persists activity events into SwiftData, stamping the current session + device.
@MainActor
final class SwiftDataActivityRecorder: ActivityRecording {
    private let context: ModelContext
    private let session: ActivitySession
    /// nil = stamp the active profile at record time.
    private let profileID: String?

    init(context: ModelContext, session: ActivitySession = .shared, profileID: String? = nil) {
        self.context = context
        self.session = session
        self.profileID = profileID
    }

    func record(_ input: ActivityEventInput) {
        let profileID = self.profileID ?? ProfileManager.shared.currentProfileID
        context.insert(ActivityEvent(input: input, session: session, profileID: profileID))
    }
}

/// Read-side queries over the activity timeline, scoped to one profile (Phase 6).
@MainActor
struct ActivityLog {
    let context: ModelContext
    /// nil = the active profile (resolved lazily so this stays off the property initializer).
    var profileID: String?
    private var resolvedProfileID: String { profileID ?? ProfileManager.shared.currentProfileID }

    /// The full timeline for the profile, newest first.
    func recent(limit: Int? = nil) -> [ActivityEvent] {
        let profileID = resolvedProfileID
        var descriptor = FetchDescriptor<ActivityEvent>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return (try? context.fetch(descriptor)) ?? []
    }

    func events(action: ActivityAction) -> [ActivityEvent] {
        let raw = action.rawValue
        let profileID = resolvedProfileID
        return (try? context.fetch(FetchDescriptor<ActivityEvent>(
            predicate: #Predicate { $0.actionRaw == raw && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))) ?? []
    }

    func events(contentID: ContentID) -> [ActivityEvent] {
        let raw = contentID.rawValue
        let profileID = resolvedProfileID
        return (try? context.fetch(FetchDescriptor<ActivityEvent>(
            predicate: #Predicate { $0.contentID == raw && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))) ?? []
    }

    func count(of action: ActivityAction) -> Int {
        let raw = action.rawValue
        let profileID = resolvedProfileID
        return (try? context.fetchCount(FetchDescriptor<ActivityEvent>(
            predicate: #Predicate { $0.actionRaw == raw && $0.profileID == profileID }
        ))) ?? 0
    }

    /// Distinct recent search queries (most recent first, de-duplicated).
    func recentSearches(limit: Int = 10) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for event in events(action: .search) {
            guard let query = event.query, !query.isEmpty else { continue }
            if seen.insert(query.lowercased()).inserted {
                result.append(query)
                if result.count >= limit { break }
            }
        }
        return result
    }
}
