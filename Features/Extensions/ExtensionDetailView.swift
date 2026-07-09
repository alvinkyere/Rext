import SwiftUI

// ---------------------------------------------------------------------------
// ExtensionDetailView.swift  (Rext Phase 2 — Priority 2)
//
// The management page for one installed extension: identity, declared
// capabilities & permissions, allowed network domains, storage used, recent logs,
// and the Clear Cache / Reinstall / Remove actions.
// ---------------------------------------------------------------------------

struct ExtensionDetailView: View {
    let extensionID: String
    let controller: ExtensionsController

    @Environment(\.dismiss) private var dismiss
    @State private var storageBytes: Int = 0
    @State private var logs: [LogEvent] = []

    private var installed: InstalledExtension? { controller.installedExtension(id: extensionID) }

    var body: some View {
        List {
            if let ext = installed {
                Section("Extension") {
                    LabeledContent("Name", value: ext.manifest.displayName)
                    LabeledContent("Version", value: ext.manifest.version.description)
                    if let author = ext.manifest.author {
                        LabeledContent("Developer", value: author)
                    }
                    LabeledContent("Identifier", value: ext.id).font(.caption.monospaced())
                }

                Section("Capabilities") {
                    ForEach(ext.capabilities.map(\.rawValue).sorted(), id: \.self) { capability in
                        Label(capability, systemImage: "bolt.fill")
                    }
                }

                Section("Permissions") {
                    let permissions = ext.manifest.permissions.declared.map(\.rawValue).sorted()
                    if permissions.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        ForEach(permissions, id: \.self) { Label($0, systemImage: "lock.shield.fill") }
                    }
                }

                if let network = ext.manifest.permissions.network, !network.domains.isEmpty {
                    Section("Allowed Domains") {
                        ForEach(network.domains, id: \.self) { Text($0).font(.caption.monospaced()) }
                    }
                }

                Section("Storage") {
                    LabeledContent("Used", value: ByteCountFormatter.string(fromByteCount: Int64(storageBytes), countStyle: .file))
                    if let quota = ext.manifest.permissions.storage?.maxBytes {
                        LabeledContent("Quota", value: ByteCountFormatter.string(fromByteCount: Int64(quota), countStyle: .file))
                    }
                }

                Section("Logs") {
                    if logs.isEmpty {
                        Text("No recent activity").foregroundStyle(.secondary)
                    } else {
                        ForEach(logs.suffix(30).reversed()) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.message).font(.caption)
                                Text("\(event.level.label) · \(event.category.rawValue)")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section {
                    Button("Clear Cache") {
                        Task { await controller.clearCache(id: extensionID); await refresh() }
                    }
                    Button("Reinstall") {
                        Task { await controller.reinstall(id: extensionID); await refresh() }
                    }
                    Button("Remove", role: .destructive) {
                        Task { await controller.uninstall(id: extensionID); dismiss() }
                    }
                }
            } else {
                ContentUnavailableView("Not Installed", systemImage: "puzzlepiece.extension")
            }
        }
        .navigationTitle(installed?.manifest.displayName ?? "Extension")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private func refresh() async {
        storageBytes = await controller.storageBytes(of: extensionID)
        logs = controller.logs(of: extensionID)
    }
}
