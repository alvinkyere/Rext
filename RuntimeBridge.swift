@preconcurrency import Foundation
import JavaScriptCore

// ---------------------------------------------------------------------------
// RuntimeBridge.swift  (Runtime SDK v1 — the Bridge component)
//
// The trust boundary. Each extension gets its own JSVirtualMachine + JSContext
// (isolation) driven on a dedicated serial queue. The only capabilities exposed
// are the injected `Runtime` global: request / storage / log.
//
// Everything else — allowlist, redirect re-check, timeouts, quota, return-value
// validation — is enforced here, in Swift, where the extension can't reach it.
// The bridge is driven by a `RuntimeConfiguration` (derived from the manifest's
// permissions) and reports through the extension's `RuntimeLogger`; it knows
// nothing about packaging, capabilities, or the registry.
// ---------------------------------------------------------------------------

// MARK: - Namespaced storage

private nonisolated final class NamespacedStore: @unchecked Sendable {
    private var map: [String: String] = [:]
    private let maxBytes: Int
    private let lock = NSLock()

    init(maxBytes: Int) { self.maxBytes = maxBytes }

    private func usedBytes() -> Int {
        map.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
    }

    func get(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return map[key]
    }

    func currentBytes() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return usedBytes()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        map.removeAll()
    }

    func delete(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        map.removeValue(forKey: key)
    }

    func set(_ key: String, _ value: String) -> [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        let projected = usedBytes() + key.utf8.count + value.utf8.count
        if projected > maxBytes {
            return ["code": ConnectorErrorCode.storageQuotaExceeded.rawValue,
                    "message": "Write would exceed \(maxBytes) bytes"]
        }
        map[key] = value
        return nil
    }
}

// MARK: - Network mediation

private nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let isAllowed: @Sendable (URL) -> Bool
    let onBlocked: @Sendable (URL) -> Void

    init(isAllowed: @escaping @Sendable (URL) -> Bool, onBlocked: @escaping @Sendable (URL) -> Void) {
        self.isAllowed = isAllowed
        self.onBlocked = onBlocked
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if let url = request.url, isAllowed(url) {
            completionHandler(request)
        } else {
            if let url = request.url { onBlocked(url) }
            completionHandler(nil)
        }
    }
}

// MARK: - ConnectorRuntime (one per extension)

/// Executes one extension's JavaScript inside an isolated JSContext and enforces
/// the security boundary. Created and owned by `RuntimeHost`; addressed by the
/// engine via `search`/`getDetails`/`getStreams`.
public nonisolated final class ConnectorRuntime: @unchecked Sendable {
    public let extensionID: String
    private(set) var lastUsed: Date = .init()

    private let vm: JSVirtualMachine
    private let context: JSContext
    private let queue: DispatchQueue
    private let store: NamespacedStore
    private let allowlist: Set<String>
    private let allowUserHost: Bool
    private let logger: RuntimeLogger
    private let requestTimeout: TimeInterval = 10
    private let callTimeout: TimeInterval = 15
    private var sessionDelegate: RedirectGuard?
    private var session: URLSession?
    private let sessionConfiguration: URLSessionConfiguration

    var sessionDelegateForTesting: URLSessionDelegate? { sessionDelegate }

    /// Bytes currently held in this extension's namespaced storage.
    public var storageUsedBytes: Int { store.currentBytes() }

    /// Clear this extension's namespaced storage ("clear cache").
    public func clearStorage() { store.clear() }

    public init(
        configuration: RuntimeConfiguration,
        source: String,
        logger: RuntimeLogger,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.extensionID = configuration.extensionID
        self.sessionConfiguration = sessionConfiguration
        self.logger = logger

        // Safety: thread safety is managed via our own serial queue.
        let unsafeVM = JSVirtualMachine()!
        let unsafeContext = JSContext(virtualMachine: unsafeVM)!

        self.vm = unsafeVM
        self.context = unsafeContext
        self.queue = DispatchQueue(label: "runtime.extension.\(configuration.extensionID)")
        self.store = NamespacedStore(maxBytes: configuration.storageMaxBytes)
        self.allowlist = configuration.allowedDomains
        self.allowUserHost = configuration.allowUserConfiguredHost

        let log = logger
        context.exceptionHandler = { _, exc in
            log.error("JS exception: \(exc?.toString() ?? "unknown")")
        }

        installNatives()
        context.evaluateScript(Self.bootstrap)
        context.evaluateScript(source)
        logger.initialize("Context initialized")
    }

    deinit {
        session?.invalidateAndCancel()
    }

    private func makeSession() -> URLSession {
        let log = logger
        let guardDelegate = RedirectGuard(
            isAllowed: { [weak self] in self?.isAllowed($0) ?? false },
            onBlocked: { url in log.warning("Blocked redirect to \(url.absoluteString)", metadata: ["host": url.host ?? "?"]) }
        )
        self.sessionDelegate = guardDelegate
        let sess = URLSession(configuration: sessionConfiguration, delegate: guardDelegate, delegateQueue: nil)
        self.session = sess
        return sess
    }

    private func isAllowed(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        if allowUserHost { return true }
        return allowlist.contains(host)
    }

    private func installNatives() {
        let log = logger
        let request: @convention(block) (JSValue) -> JSValue = { [weak self] input in
            guard let self else {
                return JSValue(undefinedIn: JSContext.current())!
            }
            return JSValue(newPromiseIn: self.context, fromExecutor: { resolve, reject in
                guard let dict = input.toObject() as? [String: Any],
                      let urlString = dict["url"] as? String,
                      let url = URL(string: urlString) else {
                    reject?.call(withArguments: [["code": ConnectorErrorCode.invalidResponse.rawValue,
                                                  "message": "Malformed request input"]])
                    return
                }

                guard self.isAllowed(url) else {
                    log.warning("Blocked request to \(url.host ?? "?")", metadata: ["url": url.absoluteString])
                    reject?.call(withArguments: [["code": ConnectorErrorCode.permissionDenied.rawValue,
                                                  "message": "Blocked request to \(url.host ?? "?")"]])
                    return
                }

                var req = URLRequest(url: url)
                req.httpMethod = (dict["method"] as? String) ?? "GET"
                if let headers = dict["headers"] as? [String: String] {
                    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
                }
                if let body = dict["body"] as? String { req.httpBody = body.data(using: .utf8) }
                let requested = (dict["timeoutMs"] as? Double).map { $0 / 1000.0 } ?? self.requestTimeout
                req.timeoutInterval = min(requested, self.requestTimeout)

                log.network("\(req.httpMethod ?? "GET") \(url.absoluteString)")
                let started = Date()

                let sess = self.session ?? self.makeSession()
                let task = sess.dataTask(with: req) { data, response, error in
                    self.queue.async {
                        if let error = error {
                            let code = (error as? URLError)?.code == .timedOut
                                ? ConnectorErrorCode.timeout : ConnectorErrorCode.upstreamError
                            log.error("Request failed: \(error.localizedDescription)", metadata: ["url": url.absoluteString])
                            reject?.call(withArguments: [["code": code.rawValue, "message": error.localizedDescription]])
                            return
                        }
                        let http = response as? HTTPURLResponse
                        let headerDict = (http?.allHeaderFields as? [String: String]) ?? [:]
                        let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        log.performance("Request completed", durationMs: Date().timeIntervalSince(started) * 1000,
                                        metadata: ["status": String(http?.statusCode ?? 0)])
                        resolve?.call(withArguments: [[
                            "status": http?.statusCode ?? 0,
                            "headers": headerDict,
                            "body": bodyString
                        ]])
                    }
                }
                task.resume()
            })!
        }

        let storageGet: @convention(block) (String) -> Any = { [weak self] key in
            self?.store.get(key) as Any? ?? NSNull()
        }
        let storageSet: @convention(block) (String, String) -> Any = { [weak self] key, value in
            self?.store.set(key, value) as Any? ?? NSNull()
        }
        let storageDelete: @convention(block) (String) -> Void = { [weak self] key in
            self?.store.delete(key)
        }
        let logBlock: @convention(block) (JSValue) -> Void = { args in
            log.log(.debug, .general, args.toArray()?.map { "\($0)" }.joined(separator: " ") ?? "")
        }

        context.setObject(unsafeBitCast(request, to: AnyObject.self), forKeyedSubscript: "__runtimeRequest" as NSString)
        context.setObject(unsafeBitCast(storageGet, to: AnyObject.self), forKeyedSubscript: "__storageGet" as NSString)
        context.setObject(unsafeBitCast(storageSet, to: AnyObject.self), forKeyedSubscript: "__storageSet" as NSString)
        context.setObject(unsafeBitCast(storageDelete, to: AnyObject.self), forKeyedSubscript: "__storageDelete" as NSString)
        context.setObject(unsafeBitCast(logBlock, to: AnyObject.self), forKeyedSubscript: "__log" as NSString)
    }

    private static let bootstrap = """
    (function (g) {
      var Runtime = {
        request: __runtimeRequest,
        storage: {
          get: function (k) { return Promise.resolve(__storageGet(k)); },
          set: function (k, v) { var e = __storageSet(k, v); return (e === null) ? Promise.resolve() : Promise.reject(e); },
          delete: function (k) { __storageDelete(k); return Promise.resolve(); }
        },
        log: function () { __log(Array.prototype.slice.call(arguments)); }
      };
      g.Runtime = Runtime;
    })(this);
    """

    public func call<T>(_ method: String, args: [Any?], as type: T.Type) async throws -> T where T: Decodable, T: Sendable {
        let jsResult: JSValue = try await withCheckedThrowingContinuation { cont in
            var timeoutItem: DispatchWorkItem?

            queue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: ConnectorError(.unknown, "Runtime deallocated during call"))
                    return
                }

                self.lastUsed = Date()

                guard let instance = self.context.objectForKeyedSubscript("connectorInstance"),
                      !instance.isUndefined else {
                    cont.resume(throwing: ConnectorError(.unknown, "connectorInstance missing"))
                    return
                }
                guard let probe = instance.objectForKeyedSubscript(method), !probe.isUndefined else {
                    cont.resume(throwing: ConnectorError(.unknown, "Extension has no method \"\(method)\""))
                    return
                }

                let jsArgs: [Any] = args.map { $0 ?? JSValue(undefinedIn: self.context) as Any }
                guard let promise = instance.invokeMethod(method, withArguments: jsArgs) else {
                    cont.resume(throwing: ConnectorError(.unknown, "Call \(method) returned nil"))
                    return
                }

                var settled = false
                let settleLock = NSLock()

                let onResolve: @convention(block) (JSValue?) -> Void = { val in
                    settleLock.lock()
                    defer { settleLock.unlock() }
                    if settled { return }
                    settled = true
                    timeoutItem?.cancel()
                    cont.resume(returning: val ?? JSValue(undefinedIn: self.context)!)
                }
                let onReject: @convention(block) (JSValue?) -> Void = { err in
                    settleLock.lock()
                    defer { settleLock.unlock() }
                    if settled { return }
                    settled = true
                    timeoutItem?.cancel()
                    cont.resume(throwing: ConnectorError.from(jsThrown: err?.toObject()))
                }

                _ = promise.invokeMethod("then", withArguments: [
                    unsafeBitCast(onResolve, to: AnyObject.self),
                    unsafeBitCast(onReject, to: AnyObject.self)
                ])

                let item = DispatchWorkItem { [weak self] in
                    settleLock.lock()
                    defer { settleLock.unlock() }
                    if settled { return }
                    settled = true
                    cont.resume(throwing: ConnectorError(.timeout, "Call \"\(method)\" exceeded \(Int(self?.callTimeout ?? 15))s"))
                }
                timeoutItem = item
                self.queue.asyncAfter(deadline: .now() + self.callTimeout, execute: item)
            }
        }
        return try decode(jsResult, as: T.self)
    }

    private func decode<T: Decodable>(_ js: JSValue, as: T.Type) throws -> T {
        guard let obj = js.toObject() else {
            throw ConnectorError(.invalidResponse, "Extension returned an undefined/nil value")
        }
        guard JSONSerialization.isValidJSONObject(obj) else {
            throw ConnectorError(.invalidResponse, "Extension return is not a JSON object/array")
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [])
            return try JSONDecoder().decode(T.self, from: data)
        } catch let e as ConnectorError {
            throw e
        } catch {
            throw ConnectorError(.invalidResponse, "Return shape does not match contract", cause: "\(error)")
        }
    }
}
