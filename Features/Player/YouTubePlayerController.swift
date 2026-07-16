import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// YouTubePlayerController.swift  (Rext — Provider Runtime v1)
//
// The provider runtime that sits between the native PlayerView and a hidden
// WKWebView. It owns the playback lifecycle, the strongly-typed bridge, and the
// synchronization of every playback update into Rext's graphs. The web view is
// an implementation detail: it loads the mobile watch page, YouTube's own chrome
// is stripped by an injected normalization script, and playback is driven /
// observed through `window.RextBridge` via HTML5 media events (not polling).
//
// Fullscreen is handed to iOS: the runtime calls the HTML5 video's native
// fullscreen; Rext does not draw over the system fullscreen UI, and playback
// state keeps syncing so exiting restores the native Rext player in place.
// ---------------------------------------------------------------------------

#if canImport(WebKit) && canImport(UIKit)
import WebKit
import UIKit

@MainActor
@Observable
final class YouTubePlayerController: NSObject {
    private(set) var state = ProviderPlaybackState()
    private(set) var errorCode: Int?
    private(set) var providerLoaded = false

    private let item: CatalogItem
    private let extensionID: String
    private weak var webView: WKWebView?

    private var recorder: PlaybackEventRecording?
    private var activityRecorder: ActivityRecording?
    private var context: ModelContext?
    private let logger = RuntimeLogger(extensionID: YouTubeProvider.providerID)

    private var hasStarted = false
    private var didComplete = false
    private var lastSeekPosition: Double = 0
    private var lastProgressRecord: Date = .distantPast

    var videoID: String { item.id }

    init(item: CatalogItem, extensionID: String) {
        self.item = item
        self.extensionID = extensionID
    }

    func bind(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        recorder = SwiftDataPlaybackEventRecorder(context: context)
        activityRecorder = SwiftDataActivityRecorder(context: context)
    }

    func attach(_ webView: WKWebView) { self.webView = webView }

    // MARK: - Commands (Swift → provider)

    func send(_ command: ProviderCommand) {
        webView?.evaluateJavaScript(command.javaScript, completionHandler: nil)
    }

    func play() { send(.play) }
    func pause() { send(.pause) }
    func togglePlayPause() { state.isPlaying ? pause() : play() }
    func seek(to seconds: Double) { send(.seek(to: seconds)) }
    func skip(by seconds: Double) { send(.skip(by: seconds)) }
    func setRate(_ rate: Double) { send(.setRate(rate)) }
    func enterFullscreen() { send(.enterFullscreen) }
    func skipAd() { send(.skipAd) }

    // MARK: - Teardown

    func teardown() {
        if hasStarted, !didComplete {
            let nearlyDone = state.duration > 0 && state.currentTime / state.duration > 0.95
            if !nearlyDone { emit(.abandoned) }
        }
        recordProgress(force: true)
        pause()
    }

    // MARK: - Bridge ingest

    private func apply(_ newState: ProviderPlaybackState) {
        state = newState
        if newState.status == .error { errorCode = errorCode ?? -1 }
        recordProgress(force: false)
    }

    private func handle(_ event: ProviderPlaybackEvent) {
        switch event {
        case .providerLoaded:
            providerLoaded = true
            logger.network("ProviderLoaded")
        case .ready:
            logger.network("Player ready")
        case .play:
            if !hasStarted {
                hasStarted = true
                lastSeekPosition = state.currentTime
                emit(.started)
                logger.network("PlaybackStarted")
            } else {
                emit(.resumed)
                logger.network("PlaybackResumed")
            }
        case .pause:
            if hasStarted, !didComplete { emit(.paused); logger.network("PlaybackPaused") }
        case .ended:
            guard !didComplete else { return }
            didComplete = true
            emit(.completed)
            recordProgress(force: true)
            logger.network("PlaybackCompleted")
        case .seeked:
            let delta = state.currentTime - lastSeekPosition
            if delta > 4 { emit(.skipped) } else if delta < -4 { emit(.replayed) }
            lastSeekPosition = state.currentTime
        case .ratechange:
            logger.network("PlaybackRateChanged \(state.playbackRate)")
        case .fullscreenEnter:
            logger.network("EnteredFullscreen")
        case .fullscreenExit:
            logger.network("ExitedFullscreen")
        case .waiting, .seeking:
            break
        }
    }

    private func handleError(_ code: Int) {
        errorCode = code
        state.status = .error
        logger.error("ProviderFailed \(code)")
    }

    private func emit(_ type: PlaybackEventType) {
        let position = state.currentTime.isFinite ? state.currentTime : 0
        let duration = state.duration.isFinite ? state.duration : 0
        recorder?.record(PlaybackEventInput(
            type: type, extensionID: extensionID, itemID: item.id, title: item.title,
            kind: item.kind.rawValue, positionSeconds: position, durationSeconds: duration
        ))
        if let action = type.activityAction {
            activityRecorder?.record(.content(
                action, extensionID: extensionID, item: item,
                positionSeconds: position, durationSeconds: duration
            ))
        }
    }

    private func recordProgress(force: Bool) {
        guard let context else { return }
        guard state.currentTime.isFinite, state.currentTime > 0 else { return }
        if !force, Date().timeIntervalSince(lastProgressRecord) < 5 { return }
        lastProgressRecord = Date()
        LibraryActions.recordHistory(
            extensionID: extensionID, item: item,
            positionSeconds: state.currentTime,
            durationSeconds: state.duration.isFinite ? state.duration : 0,
            context: context
        )
    }
}

extension YouTubePlayerController: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let json = message.body as? String, let data = json.data(using: .utf8) else { return }
        guard let msg = try? JSONDecoder().decode(ProviderBridgeMessage.self, from: data) else { return }
        if let newState = msg.state { apply(newState) }
        switch msg.kind {
        case .event: if let event = msg.event { handle(event) }
        case .error: handleError(msg.errorCode ?? -1)
        case .log: logger.network("provider: \(msg.message ?? "")")
        case .state: break
        }
    }
}

// MARK: - Provider surface (WKWebView hosting the IFrame embed)

struct RextWebVideoSurface: UIViewRepresentable {
    let controller: YouTubePlayerController

    // Dedicated, provider-scoped session so cookies/auth persist and are not
    // shared with other providers, and the web content process is reused.
    private static let processPool = WKProcessPool()

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = Self.processPool
        configuration.websiteDataStore = .default()
        // The heart of the Safari-parity design: inline playback DISABLED means
        // WebKit routes the HTML5 <video> to the native full-screen controller
        // (AVKit) on play — with PiP, AirPlay, lock-screen & Control Center.
        configuration.allowsInlineMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        configuration.userContentController.add(controller, name: "rext")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false
        controller.attach(webView)

        // The official IFrame embed on a real youtube.com origin. This is the only
        // sanctioned, working player (the watch page is blocked in web views), and
        // it keeps ads/branding/DRM provider-owned.
        webView.loadHTMLString(Self.html(videoID: controller.videoID),
                               baseURL: URL(string: "https://www.youtube.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "rext")
        uiView.stopLoading()
    }

    /// The IFrame Player API page. `playsinline:0` + inline-disabled config hands
    /// playback to the native iOS player. `onStateChange` drives the strongly-typed
    /// bridge (state + events) for graph synchronization.
    private static func html(videoID: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <style>
            html, body { margin:0; padding:0; background:#000; height:100%; overflow:hidden; }
            #player { position:fixed; top:0; left:0; width:100%; height:100%; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script>
            function post(o){ try { window.webkit.messageHandlers.rext.postMessage(JSON.stringify(o)); } catch(e){} }
            var tag = document.createElement('script');
            tag.src = "https://www.youtube.com/iframe_api";
            document.body.appendChild(tag);
            var player;
            function statusName(s){ return s===1?'playing':s===2?'paused':s===3?'buffering':s===0?'ended':'unstarted'; }
            function snap(){
              if (!player || !player.getPlayerState) return null;
              var dur = player.getDuration ? (player.getDuration()||0) : 0;
              return {
                status: statusName(player.getPlayerState()),
                currentTime: player.getCurrentTime ? (player.getCurrentTime()||0) : 0,
                duration: dur,
                bufferedFraction: player.getVideoLoadedFraction ? player.getVideoLoadedFraction() : 0,
                playbackRate: player.getPlaybackRate ? player.getPlaybackRate() : 1,
                isFullscreen: false, captionsEnabled: false, adPlaying: false, adSkippable: false,
                quality: player.getPlaybackQuality ? player.getPlaybackQuality() : 'auto'
              };
            }
            function sendState(){ var s = snap(); if (s) post({ kind:'state', state:s }); }
            function sendEvent(e){ post({ kind:'event', event:e, state: snap() }); }
            window.RextBridge = {
              play: function(){ if (player && player.playVideo) player.playVideo(); },
              pause: function(){ if (player && player.pauseVideo) player.pauseVideo(); },
              seek: function(t){ if (player && player.seekTo) player.seekTo(t, true); },
              skipBy: function(d){ if (player && player.seekTo) player.seekTo((player.getCurrentTime()||0)+d, true); },
              setRate: function(r){ if (player && player.setPlaybackRate) player.setPlaybackRate(r); },
              setMuted: function(m){ if (player) { m ? player.mute() : player.unMute(); } },
              setCaptions: function(on){},
              enterFullscreen: function(){ var f = player && player.getIframe && player.getIframe(); if (f && f.requestFullscreen) f.requestFullscreen(); },
              skipAd: function(){}
            };
            function onYouTubeIframeAPIReady(){
              player = new YT.Player('player', {
                width:'100%', height:'100%', videoId:'\(videoID)',
                host:'https://www.youtube-nocookie.com',
                playerVars:{ playsinline:0, controls:1, rel:0, modestbranding:1, fs:1, origin:'https://www.youtube.com' },
                events:{
                  onReady:function(){ post({ kind:'event', event:'providerLoaded', state:null }); sendEvent('ready'); setInterval(sendState, 1000); },
                  onStateChange:function(e){ var m={1:'play',2:'pause',0:'ended',3:'waiting'}; var ev=m[e.data]; if (ev) sendEvent(ev); else sendState(); },
                  onPlaybackRateChange:function(){ sendEvent('ratechange'); },
                  onError:function(e){ post({ kind:'error', errorCode:e.data }); }
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }
}
#endif
