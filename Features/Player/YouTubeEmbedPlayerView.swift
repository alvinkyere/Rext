import SwiftUI

// ---------------------------------------------------------------------------
// YouTubeEmbedPlayerView.swift  (Rext — native provider PlayerView)
//
// RextVideoPlayerView is a native SwiftUI screen. It shows the item's metadata
// and a compact embedded YouTube player surface. Because the provider web view
// has inline playback disabled, tapping play hands the HTML5 video to iOS's
// native full-screen media experience (AVKit) — native controls, Picture in
// Picture, AirPlay, lock-screen & Control Center, rotation — exactly like Safari.
// Rext never shows the YouTube webpage; playback state syncs into the graphs.
// ---------------------------------------------------------------------------

#if canImport(WebKit) && canImport(UIKit)
import SwiftUI
import SwiftData

struct RextVideoPlayerView: View {
    let item: CatalogItem
    let extensionID: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context

    @State private var controller: YouTubePlayerController

    init(item: CatalogItem, extensionID: String, title: String) {
        self.item = item
        self.extensionID = extensionID
        self.title = title
        _controller = State(initialValue: YouTubePlayerController(item: item, extensionID: extensionID))
    }

    private var state: ProviderPlaybackState { controller.state }
    private var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(item.id)")! }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    playerSurface
                    metadata
                }
                .padding(.bottom, 32)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
                ToolbarItem(placement: .principal) {
                    Text(title).font(.headline).lineLimit(1).foregroundStyle(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { openURL(watchURL) } label: { Image(systemName: "arrow.up.forward.app") }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { controller.bind(context: context) }
        .onDisappear { controller.teardown() }
    }

    // MARK: - Player surface (hands off to native fullscreen on play)

    private var playerSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.black)
            RextWebVideoSurface(controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if let code = controller.errorCode {
                errorOverlay(code: code)
            } else if !controller.providerLoaded {
                ProgressView().tint(.white).controlSize(.large)
            } else if state.status == .unstarted {
                // A subtle native hint over the embed's own play affordance.
                VStack(spacing: 6) {
                    Image(systemName: "play.circle.fill").font(.system(size: 52))
                    Text("Tap to play").font(.caption)
                }
                .foregroundStyle(.white.opacity(0.9))
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Label(subtitle, systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                statusChip
                if state.duration > 0 {
                    Text(timecode(state.currentTime) + " / " + timecode(state.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)

            Label("Plays in the native iOS player — supports Picture in Picture, AirPlay and the Lock Screen.",
                  systemImage: "pip")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(.horizontal)
    }

    private var statusChip: some View {
        let (text, symbol): (String, String) = {
            switch state.status {
            case .playing: return ("Playing", "play.fill")
            case .paused: return ("Paused", "pause.fill")
            case .buffering: return ("Buffering", "arrow.triangle.2.circlepath")
            case .ended: return ("Finished", "checkmark.circle.fill")
            case .error: return ("Error", "exclamationmark.triangle.fill")
            case .unstarted: return ("Ready", "circle")
            }
        }()
        return Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(0.12), in: Capsule())
            .foregroundStyle(.white)
    }

    private func errorOverlay(code: Int) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "play.slash.fill").font(.largeTitle)
            Text("Can't play this video").font(.headline)
            Text("YouTube wouldn't play this one here (error \(code)).")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { openURL(watchURL) } label: { Text("Watch on YouTube") }
                .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding()
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
#endif
