import Foundation

// ---------------------------------------------------------------------------
// ExtensionLifecycle.swift  (Runtime SDK v1, Priority 5)
//
// Replaces the old implicit "install a manifest + a string, then call methods"
// model with a formal, documented lifecycle. Every installed extension moves
// through these stages deterministically:
//
//   ┌─────────┐   ┌──────────┐   ┌─────────────┐   ┌───────┐
//   │ Install │ → │ Validate │ → │ Initialize  │ → │ Ready │
//   └─────────┘   └──────────┘   └─────────────┘   └───┬───┘
//                                                       │  (per request)
//                          Search() / Details() / Resolve()
//                                                       │
//                                                   ┌───▼─────┐
//                                                   │ Dispose │
//                                                   └─────────┘
//
//   • Install     — bytes acquired from a PackageSource; nothing executed yet.
//   • Validate    — manifest parsed; required fields, versions, SDK/runtime
//                   compatibility, duplicate id, permissions & capabilities
//                   checked. On failure the extension never advances.
//   • Initialize  — a fresh JSVirtualMachine/JSContext is created lazily on first
//                   use and the entry-point script is evaluated in isolation.
//   • Ready       — the extension can serve requests.
//   • Search/Details/Resolve — capability- and permission-gated execution.
//                   "Resolve" is stream resolution (getStreams).
//   • Dispose     — the context is torn down (idle timeout, memory pressure, or
//                   explicit teardown). A disposed extension re-initializes
//                   transparently on its next request.
// ---------------------------------------------------------------------------

public nonisolated enum ExtensionState: Sendable, Equatable {
    case installed
    case validated
    case initialized
    case ready
    case disposed
    case failed(RuntimeError)

    public var isUsable: Bool {
        switch self {
        case .ready, .initialized, .validated: return true
        case .installed, .disposed, .failed: return false
        }
    }
}
