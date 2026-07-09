import Foundation

// ---------------------------------------------------------------------------
// RuntimeHost.swift  (Runtime SDK v1 — the Host component)
//
// Owns the live `ConnectorRuntime` instances — one per extension — and their
// lifecycle in memory: lazy creation, idle teardown, and memory-pressure
// eviction. It deliberately holds no manifest, registry, or packaging state; the
// engine passes the configuration + source needed to (re)create a runtime, so a
// runtime evicted for idleness is transparently rebuilt on the next request.
// ---------------------------------------------------------------------------

nonisolated final class RuntimeHost: @unchecked Sendable {
    private var runtimes: [String: ConnectorRuntime] = [:]
    private let lock = NSLock()
    private let sessionConfiguration: URLSessionConfiguration
    private let idleTimeout: TimeInterval
    private let hostLogger = RuntimeLogger(extensionID: "runtime.host")
    private var sweeper: DispatchSourceTimer?
    private var memoryPressure: DispatchSourceMemoryPressure?

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral, idleTimeout: TimeInterval = 45) {
        self.sessionConfiguration = sessionConfiguration
        self.idleTimeout = idleTimeout
        startIdleSweeper()
        startMemoryPressureTeardown()
    }

    /// Returns the cached runtime for an extension, creating it on first use.
    func runtime(for configuration: RuntimeConfiguration, source: String, logger: RuntimeLogger) -> ConnectorRuntime {
        lock.lock()
        defer { lock.unlock() }
        if let existing = runtimes[configuration.extensionID] {
            return existing
        }
        logger.load("Loading runtime")
        let runtime = ConnectorRuntime(
            configuration: configuration,
            source: source,
            logger: logger,
            sessionConfiguration: sessionConfiguration
        )
        runtimes[configuration.extensionID] = runtime
        return runtime
    }

    func dispose(id: String) {
        lock.lock()
        defer { lock.unlock() }
        if runtimes.removeValue(forKey: id) != nil {
            hostLogger.log(.info, .general, "Disposed runtime \(id)")
        }
    }

    func disposeAll() {
        lock.lock()
        defer { lock.unlock() }
        let count = runtimes.count
        runtimes.removeAll()
        hostLogger.log(.info, .general, "Disposed all runtimes", metadata: ["count": String(count)])
    }

    // MARK: - Idle sweep

    private func startIdleSweeper() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in self?.sweepIdle() }
        timer.resume()
        sweeper = timer
    }

    private func sweepIdle() {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        for (id, runtime) in runtimes where now.timeIntervalSince(runtime.lastUsed) > idleTimeout {
            runtimes.removeValue(forKey: id)
            hostLogger.log(.info, .general, "Torn down idle runtime \(id)")
        }
    }

    // MARK: - Memory pressure

    private func startMemoryPressureTeardown() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            self.runtimes.removeAll()
            self.hostLogger.warning("Memory pressure — all runtimes torn down")
        }
        source.resume()
        memoryPressure = source
    }
}
