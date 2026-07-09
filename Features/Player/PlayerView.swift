import SwiftUI
import SwiftData
import AVKit
import AVFoundation

// ---------------------------------------------------------------------------
// PlayerView.swift  (Rext Phase 2 — Priority 7 core)
//
// A real AVPlayer-backed player that works the same regardless of which
// extension supplied the stream. Uses AVKit's `VideoPlayer` for native transport
// controls (and PiP), and adds quality selection (choosing among the extension's
// StreamSources), playback speed, and resume (persisted to HistoryEntry).
//
// Deferred: casting, skip intro/outro, audio/subtitle selection.
// ---------------------------------------------------------------------------

@MainActor
@Observable
final class PlayerModel {
    let player = AVPlayer()
    let streams: [StreamSource]
    private(set) var currentStream: StreamSource?
    var rate: Float = 1.0

    private let extensionID: String
    private let item: CatalogItem
    private var timeObserver: Any?
    private var modelContext: ModelContext?

    // Playback Event Engine wiring.
    private var recorder: PlaybackEventRecording?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var hasStarted = false
    private var wasPlaying = false
    private var didComplete = false
    private var lastObservedTime: Double = 0
    private let tickInterval: Double = 1.0

    init(streams: [StreamSource], initial: StreamSource?, item: CatalogItem, extensionID: String) {
        self.streams = streams
        self.currentStream = initial ?? streams.first
        self.item = item
        self.extensionID = extensionID
    }

    func start(context: ModelContext) {
        modelContext = context
        recorder = SwiftDataPlaybackEventRecorder(context: context)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        guard let stream = currentStream, let url = URL(string: stream.url) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))

        // Resume from saved position.
        let resume = savedPosition(context: context)
        if resume > 5 {
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
            lastObservedTime = resume
        }

        setupObservers()
        hasStarted = true
        wasPlaying = true
        emit(.started)
        player.playImmediately(atRate: rate)
    }

    func select(_ stream: StreamSource) {
        guard stream.id != currentStream?.id, let url = URL(string: stream.url) else { return }
        let resumeAt = player.currentTime()
        currentStream = stream
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: resumeAt)
        lastObservedTime = resumeAt.seconds
        player.playImmediately(atRate: rate)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if player.timeControlStatus == .playing {
            player.rate = newRate
        }
    }

    func teardown() {
        // Abandoned = left before (near-)completion.
        if hasStarted, !didComplete {
            let duration = player.currentItem?.duration.seconds ?? 0
            let position = player.currentTime().seconds
            let nearlyDone = duration > 0 && position / duration > 0.95
            if !nearlyDone { emit(.abandoned) }
        }
        recordProgress()

        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
    }

    // MARK: - Observers → events

    private func setupObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: tickInterval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }

        statusObservation = player.observe(\.timeControlStatus) { _, _ in
            Task { @MainActor [weak self] in self?.handleTimeControlChange() }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnd() }
        }
    }

    private func handleTimeControlChange() {
        guard hasStarted else { return }
        switch player.timeControlStatus {
        case .paused:
            if wasPlaying { wasPlaying = false; emit(.paused) }
        case .playing:
            if !wasPlaying { wasPlaying = true; emit(.resumed) }
        default:
            break
        }
    }

    private func handleEnd() {
        guard !didComplete else { return }
        didComplete = true
        emit(.completed)
        recordProgress()
    }

    /// Fine-grained progress tick that also detects seeks (skip / replay).
    private func tick(_ now: Double) {
        guard now.isFinite else { return }
        if lastObservedTime > 0 {
            let delta = now - lastObservedTime
            let expected = tickInterval * Double(max(rate, 0.1))
            if delta > expected + 3 {
                emit(.skipped)
            } else if delta < -3 {
                emit(.replayed)
            }
        }
        lastObservedTime = now
        recordProgress()
    }

    private func emit(_ type: PlaybackEventType) {
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        recorder?.record(PlaybackEventInput(
            type: type,
            extensionID: extensionID,
            itemID: item.id,
            title: item.title,
            kind: item.kind.rawValue,
            positionSeconds: position.isFinite ? position : 0,
            durationSeconds: duration.isFinite ? duration : 0
        ))
    }

    private func savedPosition(context: ModelContext) -> Double {
        let key = "\(extensionID)|\(item.id)"
        let descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor).first)?.positionSeconds ?? 0
    }

    private func recordProgress() {
        guard let context = modelContext else { return }
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard position.isFinite, position > 0 else { return }
        LibraryActions.recordHistory(
            extensionID: extensionID,
            item: item,
            positionSeconds: position,
            durationSeconds: duration.isFinite ? duration : 0,
            context: context
        )
    }
}

struct PlayerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerModel
    private let title: String

    private static let speeds: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    init(streams: [StreamSource], initial: StreamSource?, item: CatalogItem, extensionID: String, title: String) {
        _model = State(initialValue: PlayerModel(streams: streams, initial: initial, item: item, extensionID: extensionID))
        self.title = title
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VideoPlayer(player: model.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                controls
                Spacer()
            }
            .padding(.top)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { model.start(context: context) }
            .onDisappear { model.teardown() }
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            if model.streams.count > 1 {
                Menu {
                    ForEach(model.streams) { stream in
                        Button {
                            model.select(stream)
                        } label: {
                            Label(stream.quality ?? "Source", systemImage: stream.id == model.currentStream?.id ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label(model.currentStream?.quality ?? "Quality", systemImage: "rectangle.stack")
                }
            }

            Menu {
                ForEach(Self.speeds, id: \.self) { speed in
                    Button {
                        model.setRate(speed)
                    } label: {
                        Label(String(format: "%g×", speed), systemImage: speed == model.rate ? "checkmark" : "")
                    }
                }
            } label: {
                Label(String(format: "%g×", model.rate), systemImage: "speedometer")
            }
        }
        .font(.subheadline)
    }
}
