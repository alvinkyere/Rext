import SwiftUI
import SwiftData

// ---------------------------------------------------------------------------
// ProfilesView.swift  (Rext Roadmap Phase 6 — User Platform, experience layer)
//
// The user-facing surface for local profiles: switch, create, edit, delete,
// configure preferences + parental controls, and enter/leave guest mode. Fully
// data-driven from `ProfileManager`; the same manager scopes all per-profile data
// under the hood. Native iOS design language (Form / List / grid of avatars).
// ---------------------------------------------------------------------------

// MARK: - Presets

enum ProfilePalette {
    /// Preset avatar tint colors (hex) offered when creating/editing a profile.
    static let colors = ["#3B82F6", "#EF4444", "#10B981", "#F59E0B", "#8B5CF6", "#EC4899", "#14B8A6", "#8E8E93"]
    /// Preset SF Symbols for avatars.
    static let symbols = [
        "person.crop.circle.fill", "face.smiling.fill", "star.circle.fill",
        "gamecontroller.fill", "sparkles", "leaf.fill", "bolt.circle.fill", "heart.circle.fill",
    ]
}

extension Color {
    /// Create a Color from a `#RRGGBB` hex string (falls back to blue).
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            self = .blue; return
        }
        self = Color(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

// MARK: - Avatar

struct ProfileAvatarView: View {
    let profile: UserProfile
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Color(hex: profile.colorHex).gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: profile.avatarSymbol)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(profile.name)
    }
}

// MARK: - Management screen

struct ProfilesView: View {
    @Environment(ProfileManager.self) private var profiles
    @State private var editing: EditingTarget?

    private enum EditingTarget: Identifiable {
        case new
        case existing(UserProfile)
        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let p): return p.id
            }
        }
    }

    var body: some View {
        List {
            Section("Profiles") {
                ForEach(profiles.profiles) { profile in
                    Button {
                        profiles.switchTo(profile)
                    } label: {
                        ProfileRow(profile: profile, isCurrent: profile.id == profiles.currentProfileID)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if profile.id != UserProfile.defaultProfileID && !profile.isGuest {
                            Button(role: .destructive) { profiles.delete(profile) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { editing = .existing(profile) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }

                Button {
                    editing = .new
                } label: {
                    Label("Add Profile", systemImage: "plus.circle.fill")
                }
            }

            Section("Guest Mode") {
                if profiles.isGuestActive {
                    Button {
                        profiles.exitGuestMode()
                    } label: {
                        Label("Exit Guest Mode", systemImage: "person.crop.circle.badge.xmark")
                    }
                } else {
                    Button {
                        profiles.enterGuestMode()
                    } label: {
                        Label("Enter Guest Mode", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
                Text("Guest activity and library are kept separate and cleared when you leave.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profiles")
        .sheet(item: $editing) { target in
            switch target {
            case .new:
                ProfileEditor(profile: nil)
            case .existing(let profile):
                ProfileEditor(profile: profile)
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: UserProfile
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.body)
                HStack(spacing: 6) {
                    Text(profile.kind.title).font(.caption).foregroundStyle(.secondary)
                    if profile.parentalControls.isEnabled {
                        Label("Restricted", systemImage: "lock.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Create / edit

struct ProfileEditor: View {
    @Environment(ProfileManager.self) private var profiles
    @Environment(\.dismiss) private var dismiss

    /// nil = create a new profile.
    let profile: UserProfile?

    @State private var name: String
    @State private var kind: UserProfileKind
    @State private var symbol: String
    @State private var colorHex: String
    @State private var restrictionsOn: Bool
    @State private var blockedGenresText: String

    init(profile: UserProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _kind = State(initialValue: profile?.kind ?? .adult)
        _symbol = State(initialValue: profile?.avatarSymbol ?? ProfilePalette.symbols[0])
        _colorHex = State(initialValue: profile?.colorHex ?? ProfilePalette.colors[0])
        _restrictionsOn = State(initialValue: profile?.parentalControls.isEnabled ?? false)
        _blockedGenresText = State(initialValue: (profile?.parentalControls.blockedGenres ?? []).joined(separator: ", "))
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color(hex: colorHex).gradient)
                            .frame(width: 72, height: 72)
                            .overlay { Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.white) }
                        Spacer()
                    }
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach([UserProfileKind.adult, .child], id: \.self) { Text($0.title).tag($0) }
                    }
                }

                Section("Color") { colorGrid }
                Section("Icon") { symbolGrid }

                Section("Parental Controls") {
                    Toggle("Restrict content", isOn: $restrictionsOn)
                    if restrictionsOn {
                        TextField("Blocked genres (comma-separated)", text: $blockedGenresText)
                            .textInputAutocapitalization(.words)
                        Text("Content in these genres is hidden from search, trending, and recommendations for this profile.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(profile == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!isValid) }
            }
        }
    }

    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
            ForEach(ProfilePalette.colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex).gradient)
                    .frame(width: 36, height: 36)
                    .overlay { if hex == colorHex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                    .onTapGesture { colorHex = hex }
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
            ForEach(ProfilePalette.symbols, id: \.self) { name in
                Image(systemName: name)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(name == symbol ? Color(hex: colorHex) : .secondary)
                    .background(name == symbol ? Color(hex: colorHex).opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { symbol = name }
            }
        }
    }

    private func save() {
        let blockedGenres = blockedGenresText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let controls = ParentalControls(isEnabled: restrictionsOn, blockedGenres: blockedGenres)

        if let profile {
            profile.name = name
            profile.kindRaw = kind.rawValue
            profile.avatarSymbol = symbol
            profile.colorHex = colorHex
            profile.parentalControls = controls
            profiles.save()
        } else {
            profiles.create(name: name, kind: kind, avatarSymbol: symbol, colorHex: colorHex, parentalControls: controls)
        }
        dismiss()
    }
}

// MARK: - Quick switcher (compact sheet)

struct ProfileSwitcher: View {
    @Environment(ProfileManager.self) private var profiles
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(profiles.profiles) { profile in
                        Button {
                            profiles.switchTo(profile)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                ProfileAvatarView(profile: profile, size: 64)
                                    .overlay(alignment: .bottomTrailing) {
                                        if profile.id == profiles.currentProfileID {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                                .background(Circle().fill(.background))
                                        }
                                    }
                                Text(profile.name).font(.caption).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Who's watching?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ProfilesView() } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
        }
    }
}

#Preview {
    ProfilesView()
        .environment(ProfileManager.shared)
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
