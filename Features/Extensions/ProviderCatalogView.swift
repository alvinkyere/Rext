import SwiftUI

// ---------------------------------------------------------------------------
// ProviderCatalogView.swift  (Rext Roadmap Phase 8 — Provider Ecosystem, UI)
//
// The discovery surface for the provider ecosystem: every provider Rext is built
// around, grouped by category, with a live status (Installed / Available / Coming
// Soon) resolved from the runtime. Available providers install through the same
// permission-gated flow as the repository browser; the list is fully data-driven
// from `ProviderCatalog` + `ExtensionsController`.
// ---------------------------------------------------------------------------

struct ProviderCatalogView: View {
    let controller: ExtensionsController

    private var providers: [ProviderDescriptor] {
        // Native providers (YouTube, Plex) count as installed for status — they're
        // built in and connected via Accounts rather than installed from a repo.
        let installedIDs = Set(controller.installed.map(\.id))
            .union(MediaCatalog.shared.nativeProviderIDs)
            .union([PlexProvider.providerID])
        return ProviderCatalog.resolved(
            installedIDs: installedIDs,
            availableIDs: Set(controller.available.map(\.listing.id))
        )
    }

    private var groups: [(category: ExtensionCategory, providers: [ProviderDescriptor])] {
        ProviderCatalog.grouped(providers)
    }

    var body: some View {
        List {
            Section {
                Text("Providers unify content from many sources into one experience. Install one and its content flows into Search, your Library, and recommendations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.category) { group in
                Section(group.category.displayTitle) {
                    ForEach(group.providers) { provider in
                        ProviderRow(provider: provider) { install(provider) }
                    }
                }
            }
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func install(_ provider: ProviderDescriptor) {
        guard let id = provider.extensionID,
              let entry = controller.available.first(where: { $0.listing.id == id }) else { return }
        Task { await controller.requestInstall(entry) }
    }
}

private struct ProviderRow: View {
    let provider: ProviderDescriptor
    let onInstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: provider.colorHex).gradient)
                .frame(width: 44, height: 44)
                .overlay { Image(systemName: provider.iconSystemName).foregroundStyle(.white) }

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.name).font(.headline)
                Text(provider.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            statusControl
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusControl: some View {
        switch provider.status {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
                .font(.title3)
                .accessibilityLabel("Installed")
        case .available:
            Button("Get", action: onInstall)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .comingSoon:
            Text("Soon")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }
}
