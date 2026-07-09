import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// ExtensionsView.swift  (Rext Phase 2 — Priority 1: Repository Browser)
//
// Browses extensions across every enabled repository (from SwiftData) and lets
// the user install / update / open a management page / review permissions. Feels
// like a package manager: no rankings, no featured developers — just the repos
// the user chose to add.
// ---------------------------------------------------------------------------

struct ExtensionsView: View {
    @Query(sort: \RepositorySource.addedAt) private var repositories: [RepositorySource]
    @State private var controller = ExtensionsController()

    var body: some View {
        NavigationStack {
            List {
                if let error = controller.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }

                if !controller.updates.isEmpty {
                    Section("Updates") {
                        ForEach(controller.updates) { entry in
                            availableRow(entry)
                        }
                    }
                }

                Section("Installed") {
                    if controller.installed.isEmpty {
                        Text("No extensions installed").foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.installed) { ext in
                            NavigationLink {
                                ExtensionDetailView(extensionID: ext.id, controller: controller)
                            } label: {
                                installedRow(ext)
                            }
                        }
                    }
                }

                Section("Available") {
                    if controller.available.isEmpty {
                        Text("Nothing new to install").foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.available) { entry in
                            availableRow(entry)
                        }
                    }
                }
            }
            .navigationTitle("Extensions")
            .overlay { if controller.isBusy { ProgressView().controlSize(.large) } }
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(item: Binding(
                get: { controller.pendingInstall },
                set: { controller.pendingInstall = $0 }
            )) { pending in
                PermissionReviewSheet(
                    pending: pending,
                    onConfirm: { Task { await controller.confirmPending() } },
                    onCancel: { controller.cancelPending() }
                )
            }
        }
    }

    private func reload() async {
        let refs = repositories.filter(\.isEnabled).map { RepoRef(url: $0.url, title: $0.title) }
        await controller.refresh(repositories: refs)
    }

    private func availableRow(_ entry: ExtensionsController.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            extensionIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.listing.displayName).font(.headline)
                if let description = entry.listing.description {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text("v\(entry.version.version.description) · \(entry.repositoryName)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(entry.isUpdate ? "Update" : "Install") {
                Task { await controller.requestInstall(entry) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func installedRow(_ ext: InstalledExtension) -> some View {
        HStack(alignment: .top, spacing: 12) {
            extensionIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(ext.manifest.displayName).font(.headline)
                Text("v\(ext.manifest.version.description)").font(.caption).foregroundStyle(.secondary)
                Text(ext.capabilities.map(\.rawValue).sorted().joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text("Installed").font(.caption).foregroundStyle(.blue)
        }
        .padding(.vertical, 2)
    }

    private var extensionIcon: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.blue.gradient)
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - Permission review (Priority 5 security gate)

struct PermissionReviewSheet: View {
    let pending: ExtensionsController.PendingInstall
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Extension") {
                    LabeledContent("Name", value: pending.manifest.displayName)
                    LabeledContent("Version", value: pending.version.version.description)
                    if let author = pending.manifest.author {
                        LabeledContent("Developer", value: author)
                    }
                    LabeledContent("Repository", value: pending.repositoryName)
                }

                Section("Capabilities") {
                    ForEach(pending.manifest.capabilities.map(\.rawValue).sorted(), id: \.self) { capability in
                        Label(capability, systemImage: "bolt.fill")
                    }
                }

                Section("Permissions") {
                    let permissions = pending.manifest.permissions.declared.map(\.rawValue).sorted()
                    if permissions.isEmpty {
                        Text("None requested").foregroundStyle(.secondary)
                    } else {
                        ForEach(permissions, id: \.self) { permission in
                            Label(permission, systemImage: "lock.shield.fill")
                        }
                    }
                }

                if let network = pending.manifest.permissions.network, !network.domains.isEmpty {
                    Section("Network access") {
                        ForEach(network.domains, id: \.self) { domain in
                            Text(domain).font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle(pending.isUpdate ? "Review Update" : "Review Install")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pending.isUpdate ? "Update" : "Install", action: onConfirm)
                }
            }
        }
    }
}
