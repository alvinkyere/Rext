import SwiftUI

// ---------------------------------------------------------------------------
// StreamsView.swift
//
// Lists the stream sources an extension resolved for an item/episode, then hands
// the chosen source (and the full set, for in-player quality switching) to the
// real AVPlayer-backed PlayerView.
// ---------------------------------------------------------------------------

struct StreamsView: View {
    let connectorId: String
    let item: CatalogItem
    let title: String

    @State private var streams: [StreamSource] = []
    @State private var isLoading: Bool = true
    @State private var error: ConnectorError?
    @State private var playingStream: StreamSource?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading streams...")
                } else if let error = error {
                    errorView(error)
                } else if streams.isEmpty {
                    emptyView
                } else {
                    streamsList
                }
            }
            .navigationTitle("Select Stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadStreams() }
            .fullScreenCover(item: $playingStream) { stream in
                if stream.format == "youtube" {
                    #if canImport(WebKit) && canImport(UIKit)
                    RextVideoPlayerView(item: item, extensionID: connectorId, title: title)
                    #else
                    PlayerView(streams: streams, initial: stream, item: item, extensionID: connectorId, title: title)
                    #endif
                } else {
                    PlayerView(streams: streams, initial: stream, item: item, extensionID: connectorId, title: title)
                }
            }
        }
    }

    private var streamsList: some View {
        List(streams) { stream in
            Button {
                playingStream = stream
            } label: {
                StreamRow(stream: stream)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Streams Available",
            systemImage: "tv.slash",
            description: Text("This content doesn't have any available streams at the moment.")
        )
    }

    private func errorView(_ error: ConnectorError) -> some View {
        ContentUnavailableView {
            Label("Error Loading Streams", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
        } actions: {
            Button("Try Again") { Task { await loadStreams() } }
                .buttonStyle(.bordered)
        }
    }

    private func loadStreams() async {
        isLoading = true
        error = nil
        do {
            let episodeId = item.kind == .episode ? item.id : nil
            let parentId = item.kind == .episode ? (item.metadata?["parentId"].flatMap(stringValue) ?? item.id) : item.id
            streams = try await MediaCatalog.shared.streams(connectorId, itemId: parentId, episodeId: episodeId)
        } catch let err as ConnectorError {
            error = err
        } catch let other {
            error = ConnectorError(.unknown, other.localizedDescription)
        }
        isLoading = false
    }

    private func stringValue(_ scalar: JSONScalar) -> String? {
        if case .string(let value) = scalar { return value }
        return nil
    }
}

// MARK: - Stream Row

struct StreamRow: View {
    let stream: StreamSource

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(stream.quality ?? "Stream")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let format = stream.format {
                        Text(format.uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                if let bitrate = stream.metadata?["bitrate"], case .int(let bitrateValue) = bitrate {
                    Text("\(bitrateValue) kbps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 8)
    }
}
