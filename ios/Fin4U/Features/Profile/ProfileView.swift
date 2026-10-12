import SwiftUI
import PhotosUI

/// A round picture: the chosen photo, else the owner's initials, else a
/// generic person.
struct AvatarView: View {
    @Environment(Profile.self) private var profile
    let size: CGFloat

    var body: some View {
        Group {
            if let photo = profile.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else if !profile.initials.isEmpty {
                Text(profile.initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.gradient)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("Profile")
    }
}

struct ProfileView: View {
    @Environment(Profile.self) private var profile
    @Environment(SplitwiseSession.self) private var splitwise
    @Environment(\.dismiss) private var dismiss
    @AppStorage("splitwiseConsentAcknowledged") private var consentAcknowledged = false
    @AppStorage("splitwiseGroupID") private var splitwiseGroupID = 0
    @State private var showingConsent = false
    @State private var groups: [SplitwiseGroup] = []

    @State private var pickerItem: PhotosPickerItem?
    @State private var photoFailed = false

    var body: some View {
        @Bindable var profile = profile

        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(size: 112)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(profile.hasPhoto ? "Change photo" : "Choose a photo", systemImage: "photo")
                    }
                    if profile.hasPhoto {
                        Button("Remove photo", role: .destructive) { profile.removePhoto() }
                    }
                } footer: {
                    if photoFailed {
                        Text("That photo couldn't be used. Try a different one.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Your name", text: $profile.name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Used for the greeting on your dashboard. Your name and photo stay on this phone; they're never sent anywhere.")
                }

                if Config.splitwiseEnabled { splitwiseSection }
            }
            .navigationTitle("Profile")
            .task(id: splitwise.isConnected) { await loadGroups() }
            .sheet(isPresented: $showingConsent) {
                SplitwiseConsentView {
                    consentAcknowledged = true
                    Task { await splitwise.connect() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    photoFailed = data.map { profile.setPhoto(from: $0) == false } ?? true
                    pickerItem = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Splitwise

    @ViewBuilder
    private var splitwiseSection: some View {
        Section {
            if splitwise.isConnected {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected").font(.subheadline.weight(.medium))
                        if let user = splitwise.user {
                            Text(user.displayName).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Disconnect", role: .destructive) { splitwise.disconnect() }
                        .buttonStyle(.borderless)
                }
                Picker("Add expenses to", selection: $splitwiseGroupID) {
                    Text("No group (just between us)").tag(0)
                    ForEach(groups) { group in Text(group.name).tag(group.id) }
                }
            } else {
                Button {
                    if consentAcknowledged {
                        Task { await splitwise.connect() }
                    } else {
                        showingConsent = true
                    }
                } label: {
                    HStack {
                        Label("Connect Splitwise", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if splitwise.isWorking { ProgressView() }
                    }
                }
                .disabled(splitwise.isWorking)
            }
            if let message = splitwise.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Splitwise")
        } footer: {
            Text(splitwise.isConnected
                 ? "Shared expenses can be added to Splitwise with one tap. Nothing is sent until you tap."
                 : "Add shared expenses to Splitwise so your roommate sees what they owe.")
        }
    }

    private func loadGroups() async {
        guard splitwise.isConnected else { groups = []; return }
        groups = (try? await splitwise.api.groups()) ?? []
        // A remembered group that no longer exists falls back to "no group".
        if splitwiseGroupID != 0, !groups.isEmpty, !groups.contains(where: { $0.id == splitwiseGroupID }) {
            splitwiseGroupID = 0
        }
    }
}
