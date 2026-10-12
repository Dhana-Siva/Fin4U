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
    @Environment(\.dismiss) private var dismiss

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
            }
            .navigationTitle("Profile")
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
}
