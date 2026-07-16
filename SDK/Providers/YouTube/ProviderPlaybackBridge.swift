import Foundation

// ---------------------------------------------------------------------------
// ProviderPlaybackBridge.swift  (Rext — Provider Runtime v1)
//
// The strongly-typed contract for the bidirectional bridge between the native
// player and a provider's hidden web view. Messages are Codable structs decoded
// from a single JSON payload — no stringly-typed parsing at the call sites.
//
// JavaScript → Swift : `ProviderBridgeMessage` (state + discrete events + errors)
// Swift → JavaScript : `ProviderCommand` (rendered to a small JS call)
// ---------------------------------------------------------------------------

/// Coarse playback status, mirroring the HTML5 media element / provider states.
enum ProviderPlaybackStatus: String, Codable, Sendable {
    case unstarted
    case buffering
    case playing
    case paused
    case ended
    case error
}

/// A continuously-synchronized snapshot of provider playback.
struct ProviderPlaybackState: Codable, Equatable, Sendable {
    var status: ProviderPlaybackStatus = .unstarted
    var currentTime: Double = 0
    var duration: Double = 0
    var bufferedFraction: Double = 0
    var playbackRate: Double = 1
    var isFullscreen: Bool = false
    var captionsEnabled: Bool = false
    var adPlaying: Bool = false
    var adSkippable: Bool = false
    var quality: String = "auto"

    var isPlaying: Bool { status == .playing }
    var isBuffering: Bool { status == .buffering }
}

/// Discrete provider lifecycle events (drive analytics + graphs precisely,
/// instead of inferring everything from polled state).
enum ProviderPlaybackEvent: String, Codable, Sendable {
    case ready
    case play
    case pause
    case waiting
    case seeking
    case seeked
    case ended
    case ratechange
    case fullscreenEnter
    case fullscreenExit
    case providerLoaded
}

/// A single decoded message from the provider page.
struct ProviderBridgeMessage: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case state
        case event
        case error
        case log
    }

    let kind: Kind
    var state: ProviderPlaybackState?
    var event: ProviderPlaybackEvent?
    var errorCode: Int?
    var message: String?
}

/// Commands Swift sends into the provider page. Each renders to a JS expression
/// invoked against the injected `window.RextBridge` API.
enum ProviderCommand: Sendable {
    case play
    case pause
    case seek(to: Double)
    case skip(by: Double)
    case setRate(Double)
    case mute
    case unmute
    case enableCaptions
    case disableCaptions
    case enterFullscreen
    case skipAd

    var javaScript: String {
        switch self {
        case .play: return "RextBridge.play()"
        case .pause: return "RextBridge.pause()"
        case .seek(let t): return "RextBridge.seek(\(t))"
        case .skip(let d): return "RextBridge.skipBy(\(d))"
        case .setRate(let r): return "RextBridge.setRate(\(r))"
        case .mute: return "RextBridge.setMuted(true)"
        case .unmute: return "RextBridge.setMuted(false)"
        case .enableCaptions: return "RextBridge.setCaptions(true)"
        case .disableCaptions: return "RextBridge.setCaptions(false)"
        case .enterFullscreen: return "RextBridge.enterFullscreen()"
        case .skipAd: return "RextBridge.skipAd()"
        }
    }
}
