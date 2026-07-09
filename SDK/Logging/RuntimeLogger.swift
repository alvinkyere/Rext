import Foundation

// ---------------------------------------------------------------------------
// RuntimeLogger.swift  (Runtime SDK v1, Priority 8)
//
// `LogBus` is the process-wide fan-out point: it keeps a bounded in-memory
// history (for a future Developer Console) and forwards every event to the
// registered sinks. It is lock-based and synchronous so it can be called from
// anywhere — including the bridge's JavaScript callback queue — without forcing
// `await` at every logging site.
//
// `RuntimeLogger` is the per-extension handle handed to the runtime. Each
// installed extension gets its own, so logs are always attributable.
// ---------------------------------------------------------------------------

public nonisolated final class LogBus: @unchecked Sendable {
    public static let shared = LogBus()

    private let lock = NSLock()
    private var buffer: [LogEvent] = []
    private var sinks: [LogSink]
    private let historyLimit: Int

    public init(historyLimit: Int = 2000, sinks: [LogSink] = [ConsoleLogSink()]) {
        self.historyLimit = historyLimit
        self.sinks = sinks
    }

    public func addSink(_ sink: LogSink) {
        lock.lock()
        defer { lock.unlock() }
        sinks.append(sink)
    }

    public func publish(_ event: LogEvent) {
        lock.lock()
        buffer.append(event)
        if buffer.count > historyLimit {
            buffer.removeFirst(buffer.count - historyLimit)
        }
        let currentSinks = sinks
        lock.unlock()

        for sink in currentSinks {
            sink.write(event)
        }
    }

    /// A snapshot of recent history, newest last. Optionally scoped to one
    /// extension — the query shape a Developer Console will use.
    public func history(forExtension extensionID: String? = nil, limit: Int = 500) -> [LogEvent] {
        lock.lock()
        defer { lock.unlock() }
        let filtered = extensionID.map { id in buffer.filter { $0.extensionID == id } } ?? buffer
        return Array(filtered.suffix(limit))
    }

    public func clearHistory() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}

/// The default sink: prints a compact, greppable line to stdout.
public nonisolated struct ConsoleLogSink: LogSink {
    public init() {}

    public func write(_ event: LogEvent) {
        let base = "· [\(event.level.label)] [\(event.extensionID)] [\(event.category.rawValue)] \(event.message)"
        if event.metadata.isEmpty {
            print(base)
        } else {
            let meta = event.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
            print("\(base) {\(meta)}")
        }
    }
}

/// A per-extension logging handle. Immutable and therefore `Sendable`; safe to
/// hand to the off-main execution layer.
public nonisolated final class RuntimeLogger: Sendable {
    public let extensionID: String
    private let bus: LogBus

    public init(extensionID: String, bus: LogBus = .shared) {
        self.extensionID = extensionID
        self.bus = bus
    }

    public func log(
        _ level: LogLevel,
        _ category: LogCategory,
        _ message: String,
        metadata: [String: String] = [:]
    ) {
        bus.publish(
            LogEvent(
                extensionID: extensionID,
                category: category,
                level: level,
                message: message,
                metadata: metadata
            )
        )
    }

    // Convenience entry points aligned with the lifecycle stages and subsystems.

    public func install(_ message: String, metadata: [String: String] = [:]) {
        log(.info, .install, message, metadata: metadata)
    }

    public func load(_ message: String, metadata: [String: String] = [:]) {
        log(.info, .load, message, metadata: metadata)
    }

    public func initialize(_ message: String, metadata: [String: String] = [:]) {
        log(.info, .initialize, message, metadata: metadata)
    }

    public func network(_ message: String, metadata: [String: String] = [:]) {
        log(.debug, .network, message, metadata: metadata)
    }

    public func warning(_ message: String, metadata: [String: String] = [:]) {
        log(.warning, .warning, message, metadata: metadata)
    }

    public func error(_ message: String, metadata: [String: String] = [:]) {
        log(.error, .error, message, metadata: metadata)
    }

    public func performance(_ message: String, durationMs: Double, metadata: [String: String] = [:]) {
        var combined = metadata
        combined["durationMs"] = String(format: "%.1f", durationMs)
        log(.info, .performance, message, metadata: combined)
    }
}
