import SwiftUI

/// Choose which Splitwise friend a person in Fin4U is. Asked once per person;
/// the choice is remembered.
struct FriendPickerView: View {
    let personName: String
    let onPick: (SplitwiseUser) -> Void

    @Environment(SplitwiseSession.self) private var splitwise
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [SplitwiseUser] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""

    private var shown: [SplitwiseUser] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return friends }
        return friends.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || ($0.email ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { ProgressView(); Text("Loading your Splitwise friends...").foregroundStyle(.secondary) }
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else if shown.isEmpty {
                    Text(friends.isEmpty
                         ? "You don't have any friends on Splitwise yet. Add them in the Splitwise app first."
                         : "No match.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { friend in
                    Button {
                        onPick(friend)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName).foregroundStyle(.primary)
                            if let email = friend.email {
                                Text(email).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search friends")
            .navigationTitle("Who is \(personName) on Splitwise?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            friends = try await splitwise.api.friends().sorted { $0.displayName < $1.displayName }
        } catch SplitwiseError.unauthorized {
            splitwise.disconnect()
            error = SplitwiseError.unauthorized.localizedDescription
        } catch {
            self.error = (error as? SplitwiseError)?.localizedDescription ?? "Couldn't load your friends."
        }
    }
}
