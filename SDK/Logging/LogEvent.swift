import Foundation

// ---------------------------------------------------------------------------
// LogEvent.swift  (Runtime SDK v1, Priority 8)
//
// The structured unit of the logging system. Every log line is a typed event
// tagged with the originating extension, a category, and a level — never a bare
// string. This is what a future Developer Console reads and filters, so the
// shape is part of the stable SDK surface.
// ---------------------------------------------------------------------------

public nonisolated enum LogLevel: Int, Sendable, Comparable, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// The lifecycle/subsystem a log event belongs to. Mirrors the stages an
/// extension moves through plus cross-cutting concerns.
public nonisolated enum LogCategory: String, Sendable, CaseIterable {
    case install
    case load
    case initialize
    case network
    case error
    case warning
    case performance
    case general
}

public nonisolated struct LogEvent: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let extensionID: String
    public let category: LogCategory
    public let level: LogLevel
    public let message: String
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        extensionID: String,
        category: LogCategory,
        level: LogLevel,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.extensionID = extensionID
        self.category = category
        self.level = level
        self.message = message
        self.metadata = metadata
    }
}

/// A destination for log events. The default runtime installs a console sink;
/// a future Developer Console can register its own without any redesign.
public protocol LogSink: Sendable {
    nonisolated func write(_ event: LogEvent)
}
