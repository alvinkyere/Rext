import SwiftUI

// ---------------------------------------------------------------------------
// DesignSystem.swift  (Rext — premium design language)
//
// Shared visual language: deterministic brand gradients (so missing artwork still
// looks intentional), an app background, rail headers, artwork fallbacks, and a
// featured spotlight. Built to feel like Apple TV / Apple Music rather than a
// utility. Reused across Home, Library, Search, and detail screens.
// ---------------------------------------------------------------------------

enum Theme {
    static let cardCorner: CGFloat = 14
    static let heroCorner: CGFloat = 24
    static let railSpacing: CGFloat = 14
    static let sectionSpacing: CGFloat = 28
}

extension String {
    /// A stable hue in 0...1 derived from the string, for deterministic gradients.
    var stableHue: Double {
        let sum = unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) }
        return Double(sum % 360) / 360.0
    }
}

/// A deterministic two-tone gradient seeded by a title, so every card has a
/// distinct-but-cohesive look even without artwork.
func brandGradient(for seed: String) -> LinearGradient {
    let hue = seed.stableHue
    return LinearGradient(
        colors: [
            Color(hue: hue, saturation: 0.55, brightness: 0.65),
            Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.4),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// Subtle, scheme-adaptive full-screen backdrop used behind scrolling content.
struct RextBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: [Color.blue.opacity(0.16), Color.purple.opacity(0.08), .clear],
                startPoint: .top, endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

/// Artwork with a graceful gradient fallback (initial + icon) instead of a gray box.
struct Artwork: View {
    let url: String?
    let title: String
    var systemImage: String = "play.rectangle.fill"

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    fallback.overlay { ProgressView().tint(.white) }
                default:
                    fallback
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private var fallback: some View {
        brandGradient(for: title).overlay {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title2)
                Text(title.prefix(1).uppercased()).font(.title.bold())
            }
            .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// A section header for horizontal rails, with an optional subtitle.
struct RailHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold())
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal)
    }
}

/// A large, immersive "featured" card for the top pick.
struct FeaturedSpotlight: View {
    let title: String
    var subtitle: String?
    var artworkURL: String?
    var badge: String = "Featured"

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: artworkURL, title: title)
                .frame(height: 240)

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                Text(badge.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 4)
            }
            .padding(18)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Theme.heroCorner))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .padding(.horizontal)
    }
}
